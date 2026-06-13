# Performance

This document explains where solve latency comes from and what the system does
about it: the live optimizations (each with the reasoning, the owning source
file, and its knobs), the env-var tuning table, and the roadmap for the one
stage that still dominates — LLM vision.

---

## 1. Where the time goes

A cloud solve (`POST /api/analysis/screenshot` or `…/screenshot/stream`) is a
five-stage pipeline:

```
  upload            vision             board prep         engine           notation
 phone ──► VPS ──► LLM reads the ──►  validate +     ──► Pikafish     ──► UCI -> human +
                   board image        normalize + FEN    best move        explanation
```

**Before** this round of work, a typical solve took **~15–30 s**:

- the phone uploaded a full-resolution lossless PNG (1–8 MB) over mobile data;
- the backend base64'd those bytes straight into the vision request, and the
  model wrote back a verbose per-piece JSON array — completion tokens stream
  serially, so output size *is* latency;
- every request spawned a fresh Pikafish process and re-loaded the ~50 MB NNUE
  network before searching;
- nothing was reused across identical retries.

**After**, the same solve typically takes **~5–10 s**, and the profile is
**vision-dominated**: the LLM read (~4–9 s) is the overwhelming share, while
upload, preprocessing, board prep, engine, and notation together contribute
well under a second. The engine stage was measured end-to-end (real HTTP
against a running backend, M-series dev Mac):

| Engine scenario                          | Latency  |
| ---------------------------------------- | -------- |
| Cold first solve (pool spawn + NNUE load) | ~240 ms |
| Warm solve, default depth 12              | ~28 ms  |
| Warm solve, depth 16                      | ~208 ms |
| Cached repeat (same FEN + limits)         | ~2 ms   |

This is also why section 4 exists: every remaining big win lives in the vision
stage.

---

## 2. The optimizations

### 2.1 Grid-first vision output (~75% fewer completion tokens)

The model now returns the board as a compact 10x9 FEN-like `grid` (ten strings
of nine characters, plus `boardDetected` / `redHomeAtTop` / `sideToMove` /
`confidence` / `warnings`) instead of a verbose per-piece JSON array. Earlier
prompts demanded both, and the array — which merely restated the grid —
roughly **quadrupled** the completion tokens, the dominant share of vision
latency since output tokens stream serially. It also gave the model a second
chance to mis-transcribe. The parser expands the grid to structured pieces and
rotates to canonical engine coordinates deterministically in code; the legacy
`pieces` array is still accepted as a fallback so cached or third-party
responses keep working.

- `apps/backend/src/modules/ai/prompts/board-extraction.prompt.ts` (the prompt)
- `apps/backend/src/modules/ai/vision-response.schema.ts` (grid expansion + fallback)
- `apps/mobile/lib/features/solver/data/ondevice/direct_openai_vision.dart`
  (the own-key on-device mirror of the same contract)

### 2.2 Client-side image downscaling

Vision providers scale images down to their own pixel budget before reading
them (OpenAI "high" detail: fit within 2048 px, then shortest side to 768 px),
so pixels beyond that budget cost upload time — often over mobile data —
without the model ever seeing the difference. All three image sources now
downscale **on the device** to that same budget:

- **Android capture** saves a downscaled **JPEG quality 92** (`.jpg`, shortest
  side ≤ 768 / longest ≤ 2048) instead of the previous full-resolution PNG —
  `apps/mobile/android/app/src/main/kotlin/com/codertapsu/xiangqi_solver/ScreenCaptureService.kt`
  (budget constants in `Constants.kt`: `CAPTURE_MAX_SHORT_SIDE` /
  `CAPTURE_MAX_LONG_SIDE` / `CAPTURE_JPEG_QUALITY`).
- **Gallery picker** requests `maxWidth`/`maxHeight` 2048 at `imageQuality` 92 —
  `apps/mobile/lib/features/solver/presentation/pages/home_page.dart`.
- **iOS share extension** re-encodes shared images to a downscaled JPEG via
  ImageIO (memory-bounded downsampled decode), which also converts HEIC —
  the backend only accepts PNG/JPEG/WebP —
  `apps/mobile/ios/ShareExtension/ShareViewController.swift`.

### 2.3 Server-side preprocessing (sharp)

Defense-in-depth for clients that did *not* downscale (older app versions,
curl, camera photos): before the upload is base64'd into the vision request,
the backend bakes EXIF orientation into the pixels (a sideways camera photo
would otherwise reach the model rotated), downscales to shortest side 768 /
longest side 2048, and re-encodes as JPEG quality 90 — typically 1–5 MB →
100–300 KB with pixel-identical model input. Images already within the budget
are skipped when small, and in-budget **JPEGs are never re-encoded** (clients
already encode at quality 92; a second lossy pass would only degrade the piece
glyphs). It fails open: any decode error sends the original bytes through
untouched, and the output is never allowed to be larger than the input.

- `apps/backend/src/modules/ai/image-preprocess.service.ts`
- Env: `VISION_PREPROCESS` (default `true`), `VISION_IMAGE_SHORT_SIDE` (768),
  `VISION_IMAGE_LONG_SIDE` (2048).

### 2.4 Warm engine pool

Previously a fresh Pikafish process was spawned per request, paying process
startup + NNUE network load (~50 MB) + hash allocation on every solve —
hundreds of ms to seconds on a small VPS. The backend now keeps a small pool
of **warm, persistent** engine processes: the expensive initialization happens
once per process, and a warm search is just `ucinewgame / position / go`
(per-search UCI options are applied only as deltas).

- `ENGINE_POOL_SIZE` (default **2**) is the **hard concurrency cap**: at most
  that many searches run simultaneously, which also bounds engine RAM/CPU.
- Further requests queue **FIFO, bounded**: beyond 32 waiters the request is
  shed with `ENGINE_BUSY` instead of piling up.
- Idle engines shut down after **5 minutes** to release memory between bursts.
- When both depth and movetime are set, the search is sent with **both**
  bounds (`go depth D movetime M`) and stops at whichever hits first — a
  pathological position can no longer run unbounded by time.

Measured (real HTTP, M-series dev Mac): cold first solve ~240 ms, warm solve
~28 ms at depth 12, ~208 ms at depth 16, cached repeat ~2 ms.

- `apps/backend/src/modules/engine/pikafish-engine.service.ts`

### 2.5 Result caches (in-memory LRU)

Identical work repeats constantly — retry taps, history re-solves, re-shared
screenshots, common openings — so both expensive stages are memoized:

- **Vision cache** (100 entries): keyed
  `provider | sideToMove hint | sha256(original upload bytes)` — keying on the
  *original* bytes means a hit also skips the sharp preprocessing. Only
  **usable** extractions are cached (board detected + both generals present):
  vision is nondeterministic and the UI tells the user to retry on a garbled
  read, so pinning a failure for byte-identical retries would make that advice
  a lie. — `apps/backend/src/modules/ai/ai.service.ts`
- **Engine cache** (500 entries): keyed
  `provider | fen | depth | moveTimeMs | threads | hashMb | multiPv`. The raw
  UCI transcript is stripped before caching/returning — it is debug-only and
  can reach hundreds of KB per long search. —
  `apps/backend/src/modules/engine/engine.service.ts`
- Shared LRU: `apps/backend/src/common/utils/lru-cache.ts`

### 2.6 Progressive streaming endpoint

`POST /api/analysis/screenshot/stream` does the same work as `/screenshot` but
emits **NDJSON**, one JSON object per line as each stage completes:

```
{"stage":"received"}                       upload accepted
{"stage":"board","board":{...}}            vision + repair done
{"stage":"done","data":<AnalysisResult>}   engine + notation done
{"stage":"error","error":{code,message}}   failure after streaming began
```

This attacks **perceived** latency: vision finishes seconds before the engine,
so the client renders the recognized board while the engine is still
searching. Errors before the first byte (missing/invalid file) still use the
standard `{ success:false, error }` envelope with a real HTTP status; the
response sets `X-Accel-Buffering: no` so proxies deliver stages live.

The app consumes it in the "our key + cloud engine" mode: the `board` stage is
painted into the loading state and the floating overlay immediately, and a
404/405 (`STREAM_UNAVAILABLE`) falls back to the fused `/screenshot` endpoint
for backends that predate the stream.

- `apps/backend/src/modules/analysis/analysis.controller.ts`
- `apps/mobile/lib/features/solver/data/analysis_api.dart`
  (`analyzeScreenshotStreamed`),
  `apps/mobile/lib/features/solver/presentation/providers/solver_providers.dart`

### 2.7 Warm on-device engine (mobile)

The on-device engine mirrors the backend pool with a persistent
`WarmUciSession`: the process spawn + ~50 MB NNUE load from flash + hash
allocation happen once, and each subsequent search is option-deltas plus
`ucinewgame / position / go`. On a mid-range phone this turns a 1–3 s
per-solve engine cold start into tens of ms. The session disposes itself after
**2 minutes** idle to release the engine's RAM (net + hash) between solving
sessions, searches are serialized, and a killed/dead session is never reused
(a late `bestmove` from an aborted search must never answer the next
position).

- `apps/mobile/lib/features/solver/data/ondevice/uci_engine_client.dart`

---

## 3. Tuning

| Env var                  | Default                  | Effect on latency / throughput                                                                                                                                                  |
| ------------------------ | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ENGINE_POOL_SIZE`       | `2` (1..16)              | Warm engine processes = max concurrent searches. Raise for more parallel solves; each warm engine holds the NNUE net + hash in RAM, so size it to the host.                     |
| `ENGINE_DEFAULT_DEPTH`   | `12` (1..30)             | Server default when a request omits `engineDepth`. **Note: the app sends `engineDepth=12` explicitly**, so changing this does *not* override app clients — only bare API calls. |
| `VISION_PREPROCESS`      | `true`                   | Toggle the server-side sharp downscale/re-encode (section 2.3).                                                                                                                  |
| `VISION_IMAGE_SHORT_SIDE`| `768` (256..4096)        | Target shortest side for the vision payload. Mirrors the provider's own tiling budget; raising it costs upload + tiles for no model-visible gain.                                |
| `VISION_IMAGE_LONG_SIDE` | `2048` (512..8192)       | Target longest side for the vision payload.                                                                                                                                      |
| `AI_PROVIDER`            | `mock`                   | Default vision provider when the request omits `provider`. The app's default provider is **`auto`**, which omits the field — so this one env var A/B-switches cloud vision fleet-wide (e.g. to Gemini 3 Flash) without an app release. Explicit per-request values still override. |
| `OPENAI_MODEL`           | `gpt-5.4`                | OpenAI vision model id.                                                                                                                                                          |
| `GEMINI_MODEL`           | `gemini-3.5-flash` | Gemini vision model id.                                                                                                                                                          |

Per-request engine knobs are clamped by the DTOs: `engineThreads` ≤ 8,
`engineHashMb` ≤ 1024 — a single request cannot commandeer the host.

---

## 4. Roadmap: replacing LLM vision with an on-device board detector

> **Status: NOT implemented.** This is a design sketch for the next big win.

With every other stage now in the tens-to-hundreds of milliseconds, the LLM
vision call (~4–9 s) is the entire remaining latency story — and it is also
the entire per-solve API cost. A Xiangqi board is, however, an unusually easy
computer-vision target: a rigid 9×10 line lattice with at most one disc per
intersection and a closed set of glyphs. The plan:

1. **Board localization — classical CV, no ML.** The grid itself is a strong
   structural prior: adaptive threshold + line detection (Hough/LSD), find the
   dominant 9×10 lattice, fit a homography, and rectify the board crop. This
   also replaces today's manual focus-area crop for screenshots where the
   board is embedded in app chrome.
2. **Piece classification — a small CNN per intersection.** Crop each of the
   90 intersections and classify with a MobileNet-class model exported to
   TFLite: **~32 classes including empty** (7 piece types × 2 colors across
   glyph/skin variants, plus empty and marker/occlusion states). Estimated
   **< 5 MB** on disk and **~50–150 ms** for a full board on a mid-range
   phone — versus seconds and an API bill for the LLM.
3. **Training data — self-play renders, not photos.** Render positions from
   engine self-play onto the popular Xiangqi app skins (board themes, piece
   sets, traditional/simplified glyphs), then augment: scale, blur, JPEG
   artifacts, highlight/last-move markers, cursors, partial occlusion. Labels
   are free and exact because the renderer knows the position.
4. **Confidence-gated fallback.** Below a per-cell or whole-board confidence
   threshold, fall back to today's LLM vision path. Both paths already speak
   the same grid-shaped contract (section 2.1), so they are interchangeable
   behind the existing extraction interface.

**Expected effect:** removes the dominant 4–9 s vision latency *and* the
per-solve OpenAI cost for the vast majority of solves, and — combined with the
warm on-device engine (section 2.7) — makes the fully-offline mode complete:
capture → detect → solve with no network at all.
