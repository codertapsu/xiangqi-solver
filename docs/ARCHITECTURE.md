# Architecture

This document describes the layers, module boundaries, and data flow of the
Xiangqi Solver. The system has two deployable units: a **Flutter Android app**
(`apps/mobile`) and a **NestJS backend** (`apps/backend`). They communicate over
a single, versioned HTTP contract (see [`API.md`](API.md)). Within the app,
Dart and native Kotlin communicate over platform channels (see
[`ANDROID_NATIVE.md`](ANDROID_NATIVE.md)). Where the solve latency goes — and
the warm engine pool, caches, and streaming that attack it — is covered in
[`PERFORMANCE.md`](PERFORMANCE.md).

---

## 1. High-level layers

```
┌─────────────────────────────────────────────────────────────┐
│ Presentation        Flutter widgets, overlay rendering        │
├─────────────────────────────────────────────────────────────┤
│ App / Use cases     Solver controller, capture+analyze flow   │
├─────────────────────────────────────────────────────────────┤
│ Platform bridge     MethodChannel / EventChannel (Dart side)  │
│                     <----> Kotlin services (native side)      │
├─────────────────────────────────────────────────────────────┤
│ Transport           HTTP client  <----> NestJS controllers    │
├─────────────────────────────────────────────────────────────┤
│ Domain (backend)    Board model, coordinates, FEN/UCI, rules  │
├─────────────────────────────────────────────────────────────┤
│ Infrastructure      AI vision providers, engine providers,    │
│ (backend)           storage                                   │
└─────────────────────────────────────────────────────────────┘
```

The design follows **clean-architecture** principles: dependencies point
inward toward the domain. The domain (board representation, coordinate system,
FEN/UCI conversion, validation) knows nothing about NestJS, HTTP, Gemini,
OpenAI, or Pikafish. Outer layers depend on the domain, never the reverse.

---

## 2. Backend module boundaries

The backend is organized into NestJS modules, each with a single
responsibility. The directory layout under `apps/backend/src`:

```
src/
├── main.ts                      Bootstrap: bind 0.0.0.0:PORT, global prefix /api,
│                                CORS, global interceptor + exception filter.
├── config/                      Typed env config (PORT, AI_PROVIDER, ENGINE_*, keys).
├── common/
│   ├── decorators/              @SkipEnvelope() (read by the response interceptor).
│   ├── interceptors/            Response envelope interceptor.
│   ├── filters/                 Global exception -> error envelope.
│   ├── dto/                     Shared DTOs / validation pipes.
│   ├── types/                   Shared cross-module types (AnalysisResult, etc.).
│   └── utils/                   LruCache (backs the vision + engine caches).
└── modules/
    ├── health/                  GET /api/health (envelope-skipped).
    ├── analysis/                Orchestrates vision -> board -> engine.
    │   └── dto/                 Request DTOs for /screenshot and /board.
    ├── ai/                      Vision abstraction + sharp image preprocessing.
    │   ├── providers/           mock | gemini | openai implementations.
    │   └── prompts/             Prompt templates for the vision models.
    ├── board/                   Domain: validator + normalizer + FEN/UCI.
    ├── engine/                  Engine abstraction: mock | pikafish.
    └── storage/                 Optional, opt-in image/result persistence.
```

### Boundary rules

- **`analysis`** is the orchestrator. It depends on `ai`, `board`, and
  `engine` through their public service interfaces. It contains no provider- or
  engine-specific logic.
- **`ai`** exposes one `VisionProvider` interface. Adding `gemini`/`openai`/a
  new provider does not change callers (strategy pattern, selected by the
  `provider` field or `AI_PROVIDER` env).
- **`engine`** exposes one `EngineProvider` interface. `mock` and `pikafish`
  are interchangeable implementations.
- **`board`** is the pure domain. It is the only place that knows the
  coordinate system, FEN/UCI rules, legality/normalization. It has no I/O and
  no framework dependencies, which makes it trivially unit-testable.
- **`common`** holds the global envelope interceptor, exception filter, and the
  `@SkipEnvelope()` decorator (used by `health`).

---

## 3. The board domain (heart of the system)

The `board` module owns the rules described precisely in
[`API.md`](API.md#xiangqi-coordinate--fenuci-spec):

- **Coordinates:** `file` 0..8 (0 = Red far-left), `rank` 0..9 (0 = Red home).
- **UCI:** `file -> column letter` (`0->a … 8->i`), move = `fromCol+fromRank+toCol+toRank`.
- **Human notation:** `UPPER(col)+(rank+1)`.
- **FEN:** placement written rank 9 (Black home) down to rank 0 (Red home);
  piece letters `K A B N R C P` (uppercase = Red); side `w`/`b`;
  full form `"<placement> <side> - - 0 1"`.

The **validator + normalizer** sit between raw AI output and the engine:

1. **Validate** the recognized pieces (in-bounds, known type/color).
2. **Normalize** into a canonical, engine-ready board — dedup overlapping
   pieces, drop impossible/low-confidence detections, surface issues as
   `warnings` rather than hard failures where reasonable.
3. **Build the FEN** for the engine, and convert engine UCI output back into
   `{from, to}`, `uci`, and `human` strings for display.

This isolation is what lets us swap a mock vision provider (deterministic
board) for a real one without touching engine code, and swap a mock engine for
Pikafish without touching vision code.

---

## 4. Data flow — capture to result

The entry points produce the same `AnalysisResult`:

- `POST /api/analysis/screenshot` runs **vision → board → engine**.
- `POST /api/analysis/screenshot/stream` runs the identical pipeline but
  responds as **NDJSON**, flushing a line per stage so the client can render
  the recognized board while the engine is still searching:
  `{"stage":"received"}` → `{"stage":"board","board":{sideToMove,fen,pieces,confidence,warnings}}`
  → `{"stage":"done","data":<AnalysisResult>}`, or
  `{"stage":"error","error":{code,message}}` if a failure occurs after
  streaming began (pre-stream validation errors use the normal envelope).
- `POST /api/analysis/board` skips vision and runs **board → engine** on a
  position you supply (useful for tests, puzzles, and debugging).

```
screenshot (multipart, client-downscaled JPEG)        board (json)
        │                                                  │
        v                                                  │
 [vision LRU cache] ── hit (skips preprocess + LLM) ──┐    │
  key: provider|sideHint|sha256(upload)               │    │
        │ miss                                        │    │
        v                                             │    │
 [image preprocess (sharp)]                           │    │
  EXIF auto-rotate, downscale to ≤768 short /         │    │
  ≤2048 long side, JPEG q90 (skipped if in budget)    │    │
        v                                             │    │
  [AI VisionProvider]                                 │    │
   mock|gemini|openai                                 │    │
        │ compact 10x9 "grid"                         │    │
        v                                             │    │
 [grid -> pieces (parser expands; legacy              │    │
  pieces[] accepted as fallback)] ◄───────────────────┘    │ given pieces
        └──────────────┬───────────────────────────────────┘
                       v
            [Board repair / validator]
                       v
              [Board normalizer]  --> warnings[]
                       v
                 [FEN builder] --> fen, sideToMove   ··> "board" stage (stream)
                       v
 [engine LRU cache] ── hit (skips the engine) ──┐
  key: provider|fen|limits                      │
        │ miss                                  │
        v                                       │
            [Warm engine pool]                  │
             mock|pikafish — ENGINE_POOL_SIZE   │
             persistent processes, bounded      │
             FIFO queue, 5-min idle shutdown    │
        │ bestmove (UCI) | none                 │
        └──────────────┬────────────────────────┘
                       v
            [UCI -> {from,to}/human]
                       v
                 AnalysisResult                      ··> "done" stage (stream)
   { analysisId, board, bestMove, explanation,
     warnings, engine:{provider,ok}, vision:{provider,ok} }
```

Cache notes: the vision cache keys on the **original** upload bytes (so a hit
skips preprocessing too) and only stores **usable** extractions (board
detected, both generals present); the engine cache stores results with the raw
UCI transcript stripped.

The mobile app's default `AiProvider` is **`auto`**: the request simply omits
`provider`, so the backend's `AI_PROVIDER` env decides — letting the operator
A/B switch the fleet's cloud vision model without an app release. An explicit
`provider` value still overrides.

Provider/engine failures are **degraded, not fatal**: `engine.ok` /
`vision.ok` flags and `warnings[]` communicate partial results, and `bestMove`
may be `null` when no move is available.

---

## 5. Sequence: one capture-to-result round trip

```
User    Flutter        Native(Kotlin)        Backend            AI        Engine
 │         │                 │                   │                │           │
 │ tap "analyze" (overlay)   │                   │                │           │
 │────────────────────────►  │ overlayActionAnalyze (EventChannel)│           │
 │         │ ◄───────────────│                   │                │           │
 │         │ captureScreenshot() (MethodChannel)  │               │           │
 │         │────────────────►│ grab frame via MediaProjection     │           │
 │         │                 │ downscale (≤768/2048) + save JPEG q92          │
 │         │ ◄───────────────│ return absolute path               │           │
 │         │ screenshotCaptured{path,w,h} (event) │               │           │
 │         │                 │                   │                │           │
 │         │ POST /api/analysis/screenshot (multipart JPEG) ────► │           │
 │         │                 │                   │ vision cache? — on miss:   │
 │         │                 │                   │ preprocess (sharp), then   │
 │         │                 │                   │ recognize ───► │           │
 │         │                 │                   │ ◄── 10x9 grid  │           │
 │         │                 │                   │ grid->pieces, repair+      │
 │         │                 │                   │ normalize+FEN              │
 │         │                 │                   │ engine cache? — on miss:   │
 │         │                 │                   │ bestmove ───► warm pool ──►│
 │         │                 │                   │ ◄──────────── UCI bestmove │
 │         │                 │                   │ UCI -> {from,to}/human     │
 │         │ ◄─────────────────── AnalysisResult (JSON envelope)  │           │
 │ ◄─── overlay shows best move + score + explanation             │           │
```

The streaming variant (`POST /api/analysis/screenshot/stream`) is the same
round trip, except the backend flushes `{"stage":"received"}` on upload and
`{"stage":"board",...}` as soon as repair/normalize/FEN finish — so the
overlay can draw the recognized board **before** the engine returns — then
`{"stage":"done","data":AnalysisResult}`. Because the warm engine pool keeps
persistent Pikafish processes (no spawn-per-request), warm solves are
engine-bound rather than startup-bound, and cache hits short-circuit the AI
and engine hops entirely.

If overlay/projection permissions are not granted, native emits
`permissionDenied{permission}` and the flow stops before capture. On capture
failure, native emits `screenshotFailed{reason,code}` (or `captureScreenshot`
throws a `PlatformException`).

---

## 6. Why these boundaries

- **Testability:** the `board` domain is pure and exhaustively unit-tested
  (coordinate math, the canonical start FEN, round-tripping UCI). Providers are
  behind interfaces so the orchestrator is tested with mocks.
- **Cost control & offline dev:** mock providers give a full end-to-end flow
  with **no paid APIs and no engine binary**.
- **Swappability:** new AI vision models or engines are added as new strategy
  implementations without touching orchestration or the domain.
- **Safety/clarity of the platform bridge:** all native capabilities are
  funneled through one `MethodChannel` and one `EventChannel` with an exact,
  documented contract, so the Dart and Kotlin sides evolve independently as
  long as the contract holds.
