# Xiangqi Solver — Backend

NestJS + TypeScript backend that turns a screenshot (or an explicit board) of a
Xiangqi (Chinese chess) position into an engine-recommended best move.

**Product flow:** screenshot → AI vision extracts board-state JSON (never a
move; the model returns a compact 10x9 `grid` string that the parser expands —
~75% fewer completion tokens than the legacy `pieces` array, which is still
accepted as a fallback) → validate + normalize → convert to FEN → Xiangqi
engine returns best move → human explanation. The `/board` endpoint skips
vision and runs the engine on a board you supply directly.

**Performance:** uploads are preprocessed server-side with sharp (EXIF
auto-rotate + downscale to the vision provider's pixel budget + JPEG re-encode)
before being base64'd into the AI call; real-engine searches run on a **warm
engine pool** of persistent Pikafish processes (NNUE + hash load once, not per
solve); and in-memory LRU caches short-circuit repeated vision extractions
(keyed by image hash) and engine searches (keyed by FEN + limits).

It runs with **zero configuration**: the default `AI_PROVIDER=mock` and
`ENGINE_PROVIDER=mock` are fully offline and deterministic, so no API keys or
binaries are required to develop or test.

---

## Quickstart

```bash
cd apps/backend
npm install
npm run start:dev      # http://0.0.0.0:3000/api  (Swagger at /api/docs)
```

No `.env` file is needed. To customize, copy `.env.example` to `.env`.

### Common scripts

| Script               | Purpose                           |
| -------------------- | --------------------------------- |
| `npm run build`      | Compile to `dist/` (strict `tsc`) |
| `npm start`          | Start (no watch)                  |
| `npm run start:dev`  | Start with watch                  |
| `npm run start:prod` | Run compiled `dist/main.js`       |
| `npm run lint`       | ESLint (flat config, must exit 0) |
| `npm run format`     | Prettier write                    |
| `npm test`           | Unit tests                        |
| `npm run test:cov`   | Unit tests with coverage          |
| `npm run test:e2e`   | Supertest end-to-end suite        |

### Docker

```bash
docker compose up --build      # backend on http://localhost:3000/api
```

---

## Environment

Every variable has a safe mock default (see `.env.example`).

| Variable                           | Default                        | Description                                                                 |
| ---------------------------------- | ------------------------------ | --------------------------------------------------------------------------- |
| `PORT`                             | `3000`                         | HTTP port (binds `0.0.0.0`)                                                 |
| `AI_PROVIDER`                      | `mock`                         | `gemini` \| `openai` \| `apikeyfun` \| `mock`                               |
| `ENGINE_PROVIDER`                  | `mock`                         | `pikafish` \| `mock`                                                        |
| `GEMINI_API_KEY`                   | _(empty)_                      | Required only when `AI_PROVIDER=gemini`                                     |
| `OPENAI_API_KEY`                   | _(empty)_                      | Required only when `AI_PROVIDER=openai`                                     |
| `OPENAI_MODEL`                     | `gpt-5.4`                      | OpenAI vision model                                                         |
| `GEMINI_MODEL`                     | `gemini-3.5-flash`             | Gemini vision model                                                         |
| `APIKEYFUN_API_KEY`                | _(empty)_                      | Required only when `AI_PROVIDER=apikeyfun`                                  |
| `APIKEYFUN_MODEL`                  | `gpt-5.5`                      | api.apikey.fun vision model                                                 |
| `LOCAL_CODEX_URL`                  | `https://codertapsu.ngrok.app` | Codex HTTP bridge base URL for allowlisted devices                          |
| `LOCAL_CODEX_TOKEN`                | _(empty)_                      | Optional bridge bearer token                                                |
| `LOCAL_CODEX_MODEL`                | _(empty)_                      | Model override; empty inherits the bridge default                           |
| `LOCAL_CODEX_REASONING_EFFORT`     | _(empty)_                      | Reasoning override; empty inherits the bridge default                       |
| `LOCAL_CODEX_TIMEOUT_MS`           | `620000`                       | Local Codex request deadline                                                |
| `AI_LOCAL_VISION_PROVIDER`         | `codex`                        | Which local bridge allowlisted devices use: `codex` \| `claude` \| `none`    |
| `LOCAL_CLAUDE_URL`                 | `http://127.0.0.1:5612`        | Mother Claude HTTP bridge base URL for allowlisted devices                  |
| `LOCAL_CLAUDE_TOKEN`               | _(empty)_                      | Mother Claude token (Bearer); required while a tunnel points at the bridge  |
| `LOCAL_CLAUDE_MODEL`               | _(empty)_                      | Model override; empty inherits the bridge default                           |
| `LOCAL_CLAUDE_EFFORT`              | _(empty)_                      | Effort override; empty inherits the bridge default                          |
| `LOCAL_CLAUDE_CWD`                 | _(empty)_                      | Conversation working directory; empty uses the bridge default               |
| `LOCAL_CLAUDE_PERMISSION_MODE`     | `default`                      | Bridge permission mode for the one-shot vision conversation                 |
| `LOCAL_CLAUDE_TIMEOUT_MS`          | `180000`                       | Local Claude request deadline (non-streaming requests cap it at 40 s)       |
| `VISION_PREPROCESS`                | `true`                         | sharp preprocessing (EXIF rotate + downscale + JPEG) before the vision call |
| `VISION_IMAGE_SHORT_SIDE`          | `768`                          | Downscale budget: shortest side (px)                                        |
| `VISION_IMAGE_LONG_SIDE`           | `2048`                         | Downscale budget: longest side (px)                                         |
| `PIKAFISH_BINARY_PATH`             | _(empty)_                      | Path to the Pikafish UCI binary                                             |
| `PIKAFISH_NNUE_PATH`               | _(empty)_                      | Path to `pikafish.nnue` (empty = next to the binary)                        |
| `ENGINE_UCI_VARIANT`               | _(empty)_                      | `UCI_Variant`; empty for Pikafish, `xiangqi` for Fairy-Stockfish            |
| `ENGINE_DEFAULT_DEPTH`             | `12`                           | Default search depth (1..30)                                                |
| `ENGINE_DEFAULT_MOVE_TIME_MS`      | `1000`                         | Default move time ms (50..60000)                                            |
| `ENGINE_THREADS`                   | `1`                            | UCI `Threads` per engine process                                            |
| `ENGINE_HASH_MB`                   | `128`                          | UCI `Hash` (MB) per engine process                                          |
| `ENGINE_MULTIPV`                   | `1`                            | Top-N ranked candidate moves                                                |
| `ENGINE_MOVE_OVERHEAD_MS`          | `10`                           | UCI `Move Overhead`                                                         |
| `ENGINE_POOL_SIZE`                 | `2`                            | Warm engine pool size = hard cap on concurrent searches                     |
| `MAX_UPLOAD_BYTES`                 | `8388608`                      | Max screenshot size (8 MB)                                                  |
| `TRUST_PROXY`                      | _(empty)_                      | Express `trust proxy`; set `loopback` behind the bundled Caddy, else both IP caps see only the proxy |
| `RATE_LIMIT_TTL`                   | `60`                           | Global per-IP throttle window (seconds)                                     |
| `RATE_LIMIT_LIMIT`                 | `30`                           | Max requests per window                                                     |
| `RATE_LIMIT_DEVICE_WINDOW_SECONDS` | `86400`                        | Per-device window for the analysis endpoints (`x-device-id` header)         |
| `RATE_LIMIT_DEVICE_LIMIT`          | `100`                          | Max analysis requests per device per window                                 |
| `RATE_LIMIT_IP_LIMIT`              | `0`                            | Max analysis requests per source IP per window (always counted); `0` = 5x the device cap |
| `HINTS_DATA_DIR`                   | `./data`                       | Runtime ledgers and device allowlists                                       |
| `LOGS_DIR`                         | `./logs`                       | Date-grouped error/failure logs                                             |

### Device-gated local vision

Screenshot and extraction requests whose `x-device-id` is listed in
`<HINTS_DATA_DIR>/local-codex-vision-devices.json` try a **local bridge** first.
Every other device continues through the normal `AI_PROVIDER` selection. If the
local bridge is offline, times out, returns an error, or returns a response that
cannot be parsed as a board, the request automatically falls back to that normal
provider (currently `apikeyfun` in production), and the result carries a warning
saying so.

The allowlist is the whole gate, so the app needs no special build: every
version already sends `x-device-id`. The file is re-read when it changes (no
restart), and `data/` is not part of the release rsync, so create it on each
server by hand. A device ID is not a secret — it travels in a request header,
and Settings can show it when the remote `ui.deviceId` flag is on — so list only
your own devices.

#### Slow local reads and the app's 60-second limit

The app gives up when no byte arrives for 60 s. The streaming endpoint
(`/screenshot/stream`, used by default) sends a `{"stage":"waiting"}` line every
15 s while the bridge works, so a local read may take the bridge's full
`LOCAL_CLAUDE_TIMEOUT_MS` / `LOCAL_CODEX_TIMEOUT_MS`. The JSON endpoints
(`/extract`, used with the on-device engine, and `/screenshot`) can't send
anything early, so they cap the local attempt at 40 s and leave the cloud
fallback time to answer.

#### Choosing the bridge — exactly one, never both

There are two local bridges, and `AI_LOCAL_VISION_PROVIDER` selects **at most
one** of them:

| Value    | Provider                    | Talks to                                     |
| -------- | --------------------------- | -------------------------------------------- |
| `codex`  | `LocalCodexVisionProvider`  | Codex HTTP bridge (`LOCAL_CODEX_URL`)        |
| `claude` | `LocalClaudeVisionProvider` | Mother Claude HTTP bridge (`LOCAL_CLAUDE_URL`) |
| `none`   | —                           | Nothing; every device uses `AI_PROVIDER`     |

This is one setting rather than two enable flags on purpose. Both bridges drive
a coding agent on the operator's own machine, and they share one device
allowlist and one fallback path — running them together would mean two competing
reads of the same screenshot with no rule for choosing between them. A single
slot makes "both at once" a state the service cannot be configured into, rather
than one it has to detect and reject.

Switching is a restart with a different value. The device allowlist, the
fallback behaviour and the response envelope are identical either way; only
`vision.provider` in the response changes (`local-codex` vs `local-claude`).

#### Local Claude specifics

`LocalClaudeVisionProvider` gives each extraction its own conversation: it
creates one (`POST /threads`), runs a single turn carrying the prompt and the
image (`POST /threads/{id}/run`), then closes it (`DELETE /threads/{id}`). The
bridge also offers a one-call `POST /chat`, which is deliberately **not** used —
that endpoint re-points the bridge's *current* conversation, so a background
vision read would silently hijack whichever conversation the operator was having.

The conversation is created with `setting_sources: []` and a disallowed-tool
list: a board read needs nothing from the filesystem or the network, and denying
those tools means a stray tool call cannot park the turn on an approval prompt
nobody is watching for. `LOCAL_CLAUDE_TIMEOUT_MS` is the backstop and defaults
to three minutes — far shorter than the Codex deadline, because a vision turn
should take seconds and failing fast is what lets the cloud fallback answer
while the user is still waiting.

If closing the conversation fails, the board is still returned, with a warning:
a lingering conversation on the bridge is untidy, not wrong, and is not worth
discarding an answer the user is waiting for.

The bridge must be **started** before it will serve requests — it does not
listen when the Mother Claude app merely opens. A request to a stopped bridge
comes back as `bridge_not_started`, and a signed-out Claude as
`claude_login_required`; both are reported as `VISION_UNAVAILABLE` (an operator
problem) rather than as a model failure, and both fall back to `AI_PROVIDER`.
`LOCAL_CLAUDE_URL` defaults to the bridge's loopback port, so a backend running
anywhere other than the operator's own machine needs a tunnel URL here.

The allowlist is a JSON object whose keys are exact device IDs; values are
ignored and may be notes. Keys starting with `_` are comments:

```json
{
  "_comment": "Devices allowed to use Local Codex vision",
  "device-id-from-the-app": "test phone"
}
```

The file is reloaded when its modification time changes. Missing, malformed, or
unreadable files produce an empty allowlist, so requests safely use the existing
provider. `data/` is runtime state: it is gitignored and excluded from release
synchronization. Create or copy this file separately on each deployed server and
keep the deployment directory persistent.

For ngrok, copy the public HTTPS origin exactly as shown by ngrok. It normally
uses public port 443, so do not append the bridge's local port (`5611` for
Codex, `5612` for Claude). Verify connectivity from the deployed backend host
before testing an image:

```bash
curl -v "$LOCAL_CODEX_URL/health"
curl -v "$LOCAL_CLAUDE_URL/health"   # also reports whether the bridge is started
```

Each local-bridge attempt writes safe request metadata to the Nest console. A
failure includes the endpoint, elapsed time, HTTP status or bridge error, and
the nested Node/Undici cause (for example `ENOTFOUND`, `ECONNREFUSED`, a TLS
error, or `UND_ERR_CONNECT_TIMEOUT`). Bearer tokens and image data are never
included. The same structured failure is appended to
`<LOGS_DIR>/<YYYY-MM-DD>.log` (UTC), which can be watched with:

```bash
tail -f "${LOGS_DIR:-./logs}/$(date -u +%F).log"
```

Remote config / feature flags served by `GET /api/config` (so the mobile app is
tunable without a release) live in their own groups — `FEATURE_*` (ads + optional
UI sections), `HINTS_FREE_ON_INSTALL` / `HINTS_OWN_KEY_DIVISOR` (hint economy),
`ONDEVICE_*` (on-device engine + NNUE net download), `STORED_SCREENSHOTS_MAX`,
`APP_ICON_VARIANT`, and `ADMIN_SECRET` (admin write API; empty = disabled).
See `.env.example` for the full, documented list.

---

## Mock mode

With the defaults, the backend is fully self-contained:

- **MockVisionProvider** always "detects" the standard 32-piece start position.
- **MockEngineService** returns a deterministic opening move
  (`b2e2` for Red, `b7e7` for Black, score `+0.30`).

This makes the whole pipeline testable and demoable offline.

---

## API

All routes are prefixed with `/api`. Every response except `/api/health` and
the NDJSON `/api/analysis/screenshot/stream` is wrapped in a success envelope;
errors use an error envelope.

```jsonc
// success
{ "success": true, "data": <payload> }
// error
{ "success": false, "error": { "code": "BAD_REQUEST", "message": "...", "details": [...] } }
```

### `GET /api/health` (not wrapped)

```json
{ "status": "ok", "timestamp": "2026-06-04T00:00:00.000Z", "uptimeSeconds": 12, "version": "0.1.0" }
```

### `POST /api/analysis/screenshot` (multipart/form-data)

Fields: `screenshot` (image file, required, png/jpeg/webp, ≤ 8 MB),
`provider?`, `sideToMove?`, `engineProvider?`, `engineDepth?` (1..30),
`engineMoveTimeMs?` (50..60000), `engineThreads?` (1..8), `engineHashMb?`
(1..1024), `engineMultiPv?` (1..10), `language?`.
Returns `AnalysisResult`. Omitting `provider` uses the server's `AI_PROVIDER`
default, so the operator can switch cloud vision fleet-wide.

### `POST /api/analysis/screenshot/stream` (multipart/form-data → NDJSON)

Same fields and work as `/screenshot`, but **progressive**: the response is
`application/x-ndjson` (not enveloped) — one JSON object per line as each
stage completes, so a client can render the recognized board while the engine
is still searching.

```jsonc
{"stage":"received"}                                  // upload accepted
{"stage":"board","board":{"sideToMove":"red","fen":"...","pieces":[...],"confidence":0.9,"warnings":[]}}
{"stage":"done","data":<AnalysisResult>}              // or, on failure mid-stream:
{"stage":"error","error":{"code":"...","message":"..."}}
```

Validation errors before the first byte (missing/invalid file) still get the
standard error envelope with a real HTTP status.

### `POST /api/analysis/extract` (multipart/form-data)

Vision-only: recognizes the board and returns it **without** running the
engine, for clients that compute the move themselves (e.g. the app's on-device
engine) while keeping the AI key server-side.

### `POST /api/analysis/board` (application/json)

```jsonc
{
  "sideToMove": "red",
  "pieces": [
    { "color": "red", "type": "king", "file": 4, "rank": 0 },
    { "color": "black", "type": "king", "file": 4, "rank": 9 },
  ],
  "engineDepth": 12, // optional
}
```

Returns `AnalysisResult` (vision is bypassed).

### `AnalysisResult` shape

```jsonc
{
  "analysisId": "<uuid v4>",
  "board": {
    "sideToMove": "red",
    "fen": "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1",
    "pieces": [{ "type": "rook", "color": "black", "position": { "file": 0, "rank": 9 } }],
    "confidence": 0.9,
  },
  "bestMove": {
    "from": { "file": 1, "rank": 2 },
    "to": { "file": 4, "rank": 2 },
    "uci": "b2e2",
    "human": "B3 to E3",
    "score": "+0.30",
    "depth": 12,
  },
  "explanation": "For Red to move, the mock engine recommends B3 to E3 ...",
  "warnings": [],
  "engine": { "provider": "mock", "ok": true },
  "vision": { "provider": "mock", "ok": true },
}
```

The backend also serves `GET /api/config` (remote config / feature flags for
the app), `POST /api/hints/claim` (install grant), `GET /api/engine/net`
(on-device NNUE net download), and `/api/admin/*` (admin API, gated by
`ADMIN_SECRET`).

---

## Coordinate, FEN & UCI spec

- **file** 0..8 (0 = Red far-left), **rank** 0..9 (0 = Red home, 9 = Black home).
- file → column letter: `0→a … 8→i`.
- **UCI** = `fromCol+fromRank+toCol+toRank`, e.g. `{file:1,rank:2}→{file:1,rank:7}` = `b2b7`.
- **Human** = `UPPER(col)+(rank+1)`, e.g. `B3 to B8`.
- **FEN letters:** King `K`, Advisor `A`, Elephant `B`, Horse `N`, Rook `R`,
  Cannon `C`, Pawn `P`. Uppercase = Red, lowercase = Black. Placement is written
  rank 9 first (Black home, top) down to rank 0, ranks joined by `/`, empty runs
  collapsed into digits. Full FEN = `<placement> <side> - - 0 1` (`w` = Red).
- Canonical start FEN:
  `rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1`.

---

## Pikafish notes

`ENGINE_PROVIDER=pikafish` runs the Pikafish UCI binary at
`PIKAFISH_BINARY_PATH` in a **warm engine pool**: up to `ENGINE_POOL_SIZE`
(default 2) persistent processes are kept alive between requests, so the UCI
handshake + NNUE + hash load happen once per process instead of per solve.
The pool size is also the hard cap on **concurrent** searches — extra requests
wait in a bounded FIFO queue (more than 32 waiting → `ENGINE_BUSY`), and idle
engines shut down after 5 minutes to release memory. Processes are spawned
with a **spawn args array (never a shell string)**, so there is no
command-injection surface, and a hard timeout kills a hung child (SIGTERM,
then SIGKILL).

When both depth and move time are set, the search is sent as
`go depth D movetime M` — the engine stops at whichever bound it reaches
first. Measured over real HTTP on an M-series dev Mac: cold first solve
240 ms, warm solve 28 ms, cached repeat 2 ms, depth-16 warm 208 ms.

The board orientation encoded in the FEN (which home rank is written first,
which side is file 0) has been **validated against the real Pikafish binary**
(known FENs fed to a live process, output compared to a trusted reference).

If the binary path is empty or missing, the engine fails with a clear
`SERVICE_UNAVAILABLE` error recommending `ENGINE_PROVIDER=mock`.

---

## Security & privacy

- Uploads are validated for **mime type** (png/jpeg/webp) and **size** (≤ 8 MB);
  violations return `400`.
- Screenshots are processed **in memory and never persisted** by default; raw
  image bytes are never logged.
- Caches are **in-memory LRU only**: vision extractions are keyed by
  `(provider | sideHint | sha256 of the original upload)` and cached only when
  usable (board detected + both generals present); engine results are keyed by
  `(provider | fen | limits)` with the raw UCI transcript stripped.
- Global **rate limiting** (Throttler) and per-request **timeouts** on outbound
  AI/engine calls.
- Config is read from env with safe mock defaults — **no hardcoded secrets**.
