# Backend API Reference

The NestJS backend exposes the HTTP API consumed by the Flutter app. This
document is the authoritative reference and matches the shared API contract
exactly.

- **Base prefix:** every route is under `/api`.
- **Binding:** server binds host `0.0.0.0`, port = env `PORT` (default `3000`).
- **CORS:** enabled for all origins in development.
- **Content types:** JSON for most endpoints; `multipart/form-data` for the
  screenshot uploads; `application/x-ndjson` for the streaming analysis;
  raw `application/octet-stream` for the engine-net download.
- **Rate limiting:** a global per-IP throttle covers all routes
  (`RATE_LIMIT_LIMIT` requests per `RATE_LIMIT_TTL` seconds; defaults **30 /
  60 s**). The `/api/analysis/*` endpoints and `POST /api/hints/claim` are
  additionally capped **per device** via the `x-device-id` header (rolling
  window: `RATE_LIMIT_DEVICE_LIMIT` per `RATE_LIMIT_DEVICE_WINDOW_SECONDS`;
  defaults **100 / day**; falls back to the client IP when the header is
  absent). Exceeding either cap returns **429**. `GET /api/config`,
  `GET /api/engine/net`, and the `/api/admin/*` routes skip the per-IP
  throttle (cheap, low-volume calls that must not share the analysis budget).

## Endpoint index

| Method             | Path                              | Purpose                                                  |
| ------------------ | --------------------------------- | -------------------------------------------------------- |
| GET                | `/api/health`                     | Liveness probe (no envelope).                            |
| POST               | `/api/analysis/screenshot`        | Screenshot → board recognition → engine best move.       |
| POST               | `/api/analysis/screenshot/stream` | Same, but progressive NDJSON stages (no envelope).       |
| POST               | `/api/analysis/extract`           | Vision-only board extraction (no engine).                |
| POST               | `/api/analysis/board`             | Engine on a provided position (vision bypassed).         |
| GET                | `/api/config`                     | Remote config / feature flags for the app.               |
| POST               | `/api/hints/claim`                | Install grant: starting hint balance for a device.       |
| GET                | `/api/engine/net`                 | On-device Pikafish NNUE net download (raw bytes).        |
| GET                | `/api/admin/status`               | Admin identity probe (no secret).                        |
| GET / PUT / DELETE | `/api/admin/config`               | Read / set / clear the remote-config override.           |
| GET / PUT / DELETE | `/api/admin/grants`               | Manual hint-grant allowlist (`grants.json`).             |
| GET / PUT / DELETE | `/api/admin/installs`             | Install ledger (`installs.json`).                        |

---

## Response envelope

A global NestJS interceptor wraps the payload of **every** endpoint **except**:

- `GET /api/health` — flat payload for external monitors;
- `POST /api/analysis/screenshot/stream` — NDJSON stage lines (see below);
- `GET /api/engine/net` — raw file bytes.

**Success:**

```json
{ "success": true, "data": <payload> }
```

**Error** (produced by the global exception filter, with an appropriate HTTP
status code):

```json
{
  "success": false,
  "error": {
    "code": "STRING_CODE",
    "message": "Human-readable message",
    "details": { "optional": "any" }
  }
}
```

These exceptions use the `@SkipEnvelope()` decorator, which the interceptor
reads to bypass wrapping.

---

## Shared types

### `BoardPiece` (request input)

```ts
{
  color: "red" | "black",
  type:  "king" | "advisor" | "elephant" | "horse" | "rook" | "cannon" | "pawn",
  file:  int 0..8,
  rank:  int 0..9,
  confidence?: number
}
```

### `AnalysisResult` (response payload)

```ts
{
  analysisId: string,            // uuid v4
  board: {
    sideToMove: "red" | "black" | "unknown",
    fen: string,
    pieces: Array<{
      type, color,
      position: { file, rank },
      confidence?: number
    }>,
    confidence: number
  },
  bestMove: {
    from: { file, rank },
    to:   { file, rank },
    uci:  string,                // e.g. "b2b7"
    human: string,               // localized traditional notation, e.g. "Pháo 8 tiến 5"
    notation: string,            // universal WXF code, e.g. "C8+5"
    score: string,
    depth: number
  } | null,
  candidates: Array<bestMove>,   // ranked moves (same shape as bestMove) when engineMultiPv > 1, index 0 = best; [] otherwise
  explanation: string,
  warnings: string[],
  engine: { provider: string, ok: boolean },
  vision: { provider: string, ok: boolean }
}
```

> Note the shape difference between **input** pieces (`file`/`rank` at the top
> level) and **output** pieces (nested under `position`).

---

## `GET /api/health`

Liveness/readiness probe. **Not** wrapped in the response envelope.

**Response 200:**

```json
{
  "status": "ok",
  "timestamp": "2026-06-04T12:00:00.000Z",
  "uptimeSeconds": 123.45,
  "version": "0.1.0"
}
```

**curl:**

```bash
curl -s http://localhost:3000/api/health
```

---

## `POST /api/analysis/board`

Run the engine directly on a position you provide. **Bypasses vision.** Useful
for puzzles, tests, and debugging the engine/FEN path.

**Content-Type:** `application/json`

**Body:**

```ts
{
  provider?: "gemini" | "openai" | "mock",   // recorded in vision.provider
  sideToMove: "red" | "black" | "unknown",
  pieces: BoardPiece[],                      // 1..32 items
  engineProvider?: "pikafish" | "mock",      // default from ENGINE_PROVIDER
  engineDepth?: int 1..30,
  engineMoveTimeMs?: int 50..60000,
  engineThreads?: int 1..8,                  // Pikafish Threads
  engineHashMb?: int 1..1024,                // Pikafish Hash (MB)
  engineMultiPv?: int 1..10,                 // top-N moves; >1 fills candidates[]
  language?: "en" | "vi" | "zh"              // notation language; default "vi"
}
```

**Example request:**

```json
{
  "provider": "mock",
  "engineProvider": "mock",
  "sideToMove": "red",
  "engineDepth": 12,
  "pieces": [
    { "color": "red",   "type": "king",   "file": 4, "rank": 0 },
    { "color": "red",   "type": "rook",   "file": 0, "rank": 0 },
    { "color": "black", "type": "king",   "file": 4, "rank": 9 },
    { "color": "black", "type": "cannon", "file": 1, "rank": 7 }
  ]
}
```

**Example response (envelope + payload):**

```json
{
  "success": true,
  "data": {
    "analysisId": "5f1d4e2a-9c7b-4a1e-8b2c-0d3e4f5a6b7c",
    "board": {
      "sideToMove": "red",
      "fen": "4k4/9/1c7/9/9/9/9/9/9/R3K4 w - - 0 1",
      "pieces": [
        { "type": "king",   "color": "red",   "position": { "file": 4, "rank": 0 } },
        { "type": "rook",   "color": "red",   "position": { "file": 0, "rank": 0 } },
        { "type": "king",   "color": "black", "position": { "file": 4, "rank": 9 } },
        { "type": "cannon", "color": "black", "position": { "file": 1, "rank": 7 } }
      ],
      "confidence": 1
    },
    "bestMove": {
      "from": { "file": 0, "rank": 0 },
      "to":   { "file": 0, "rank": 9 },
      "uci":  "a0a9",
      "human": "Xe 9 tiến 9",
      "notation": "R9+9",
      "score": "+2.10",
      "depth": 12
    },
    "candidates": [],
    "explanation": "Rook lift to the back rank pressures the black king.",
    "warnings": [],
    "engine": { "provider": "mock", "ok": true },
    "vision": { "provider": "mock", "ok": true }
  }
}
```

**curl (mock mode):**

```bash
curl -s -X POST http://localhost:3000/api/analysis/board \
  -H 'Content-Type: application/json' \
  -d '{
    "provider": "mock",
    "engineProvider": "mock",
    "sideToMove": "red",
    "pieces": [
      { "color": "red",   "type": "king", "file": 4, "rank": 0 },
      { "color": "black", "type": "king", "file": 4, "rank": 9 }
    ]
  }'
```

---

## `POST /api/analysis/screenshot`

Recognize a board from a screenshot, normalize it, then run the engine.

**Content-Type:** `multipart/form-data`

**Fields:**

| Field             | Type        | Required | Notes                                                              |
| ----------------- | ----------- | -------- | ------------------------------------------------------------------ |
| `screenshot`      | image file  | yes      | `image/png`, `image/jpeg`, or `image/webp` (sniffed from magic bytes, not the declared mime); max `MAX_UPLOAD_BYTES` (default **8 MB**). |
| `provider`        | string enum | no       | `gemini` \| `openai` \| `mock`; **omit** to use the server's `AI_PROVIDER` (this is the app's "Auto" mode). When `AI_PROVIDER_ENFORCE=true` the server **ignores this field entirely** and always uses `AI_PROVIDER` — so the operator can switch the cloud vision provider fleet-wide even for already-installed apps that send an explicit value. |
| `sideToMove`      | string enum | no       | `red` \| `black` \| `unknown`.                                     |
| `engineProvider`  | string enum | no       | `pikafish` \| `mock`; default from `ENGINE_PROVIDER` env. Ignored (forced to `ENGINE_PROVIDER`) when `ENGINE_PROVIDER_ENFORCE=true`. |
| `engineDepth`     | int 1..30   | no       | Engine search depth.                                               |
| `engineMoveTimeMs`| int 50..60000| no      | Per-move think time in ms.                                         |
| `engineThreads`   | int 1..8    | no       | Pikafish `Threads`.                                                |
| `engineHashMb`    | int 1..1024 | no       | Pikafish `Hash` (MB).                                              |
| `engineMultiPv`   | int 1..10   | no       | Top-N moves (`MultiPV`); >1 fills `candidates[]`.                  |
| `language`        | string enum | no       | `en` \| `vi` \| `zh`; notation language. Default `vi`.            |

**Response payload:** `AnalysisResult` (same shape as `/board`), with
`vision.provider` reflecting the chosen vision provider and
`board.pieces`/`board.confidence` derived from recognition. When
`engineMultiPv > 1`, `candidates[]` holds the ranked moves (index 0 = best).

**Server-side image preprocessing:** before the vision call the server
normalizes the upload — EXIF auto-rotate, downscale to shortest side ≤
`VISION_IMAGE_SHORT_SIDE` (default 768) / longest side ≤
`VISION_IMAGE_LONG_SIDE` (default 2048), JPEG re-encode. Images already within
that budget are passed through untouched. Toggle with `VISION_PREPROCESS`
(default `true`).

**Caching:** usable vision extractions (keyed on provider + side hint + SHA-256
of the original upload) and engine results (keyed on provider + FEN + search
limits) are kept in in-memory LRU caches, so re-submitting an identical image
or position returns in milliseconds. The engine itself runs in a **warm pool**
of persistent Pikafish processes (`ENGINE_POOL_SIZE`, default 2 — also the hard
cap on concurrent searches; excess requests queue, and the queue is bounded).

**curl (mock mode — any small PNG works; mock ignores image bytes):**

```bash
curl -s -X POST http://localhost:3000/api/analysis/screenshot \
  -F 'screenshot=@./sample.png;type=image/png' \
  -F 'provider=mock' \
  -F 'engineProvider=mock' \
  -F 'sideToMove=red'
```

**Errors:**

| HTTP | `code`                   | When                                                        |
| ---- | ------------------------ | ----------------------------------------------------------- |
| 400  | `MISSING_FILE`           | No `screenshot` file in the form.                           |
| 400  | `FILE_TOO_LARGE`         | Upload exceeds `MAX_UPLOAD_BYTES`.                          |
| 400  | `UNSUPPORTED_MEDIA_TYPE` | Magic bytes are not a real PNG/JPEG/WebP.                   |
| 400  | `NO_BOARD_DETECTED`      | Vision found no pieces after board repair.                  |
| 503  | `ENGINE_BUSY`            | Warm engine pool's wait queue is full (>32 waiting).        |

**Example error (file too large):**

```json
{
  "success": false,
  "error": {
    "code": "FILE_TOO_LARGE",
    "message": "File too large (9437184 bytes). Maximum is 8388608 bytes."
  }
}
```

---

## `POST /api/analysis/screenshot/stream`

Same work and same form fields as `/screenshot`, but **progressive**: the
response is `application/x-ndjson` — one JSON object per line as each stage
completes, so the client can render the recognized board while the engine is
still searching. **Not** wrapped in the response envelope.

**Content-Type (request):** `multipart/form-data` — identical fields to
`/screenshot`.

**Response headers:** `200 OK`, `Content-Type: application/x-ndjson;
charset=utf-8`, `Cache-Control: no-cache`, `X-Accel-Buffering: no` (disables
nginx/Caddy proxy buffering so stages reach the client live).

**Stage lines (in order):**

```jsonl
{"stage":"received"}
{"stage":"board","board":{"sideToMove":"red","fen":"…","pieces":[…],"confidence":0.9,"warnings":[]}}
{"stage":"done","data":{ …AnalysisResult… }}
```

- `received` — upload accepted (sent immediately after validation).
- `board` — vision + board repair done, **before** the engine runs. The
  `board` object is `{ sideToMove, fen, pieces, confidence, warnings }`
  (pieces in the output shape, with nested `position`).
- `done` — engine + notation done; `data` is the full `AnalysisResult`,
  exactly as `/screenshot` would return it.

**Error semantics — two cases:**

1. **Before the first byte** (missing/oversize/invalid file): the standard
   `{ "success": false, "error": … }` envelope with a real HTTP status — same
   as `/screenshot`.
2. **After streaming began** (vision/engine failure): HTTP status is already
   `200`; the stream ends with an error line instead of `done`, mirroring the
   envelope's `{ code, message }` shape:

```json
{"stage":"error","error":{"code":"NO_BOARD_DETECTED","message":"No Xiangqi board was detected in the screenshot."}}
```

**curl (mock mode; `-N` disables curl buffering):**

```bash
curl -sN -X POST http://localhost:3000/api/analysis/screenshot/stream \
  -F 'screenshot=@./sample.png;type=image/png' \
  -F 'provider=mock' \
  -F 'engineProvider=mock' \
  -F 'sideToMove=red'
```

---

## `POST /api/analysis/extract`

**Vision-only**: recognize and normalize the board, then return it **without
running the engine**. Intended for clients that compute the move themselves
(e.g. an on-device engine), keeping the AI key server-side. See
[ON_DEVICE_ENGINE.md](ON_DEVICE_ENGINE.md).

**Content-Type:** `multipart/form-data`

**Fields:**

| Field        | Type        | Required | Notes                                                           |
| ------------ | ----------- | -------- | --------------------------------------------------------------- |
| `screenshot` | image file  | yes      | `image/png`, `image/jpeg`, or `image/webp`; max `MAX_UPLOAD_BYTES` (default **8 MB**). |
| `provider`   | string enum | no       | `gemini` \| `openai` \| `mock`; omit to use the server's `AI_PROVIDER`. |
| `sideToMove` | string enum | no       | `red` \| `black` \| `unknown` (authoritative when set).         |

**Response payload (`ExtractionResult` — no `bestMove`/`engine`/`explanation`):**

```json
{
  "success": true,
  "data": {
    "extractionId": "uuid",
    "board": { "sideToMove": "red", "fen": "…", "pieces": [ /* … */ ], "confidence": 0.9 },
    "warnings": [],
    "vision": { "provider": "mock", "ok": true }
  }
}
```

`400 NO_BOARD_DETECTED` is returned only when no pieces are recognized at all.

**curl (mock mode):**

```bash
curl -s -X POST http://localhost:3000/api/analysis/extract \
  -F 'screenshot=@./sample.png;type=image/png' \
  -F 'provider=mock' \
  -F 'sideToMove=red'
```

---

## `GET /api/config`

Remote config / feature flags for the app. The app fetches this on launch and
caches the last good value, so behavior (ad formats, free-hint count, own-key
hint divisor, on-device engine availability + net URL, visible settings
sections, launcher-icon variant) is tunable **from the server** without
shipping a new app version. Skips the per-IP throttle.

Values come from env defaults (`FEATURE_*`, `HINTS_*`, `ONDEVICE_*`,
`STORED_SCREENSHOTS_MAX`, `APP_ICON_VARIANT`), overlaid by the admin override
(`config-overrides.json`, managed via `/api/admin/config`) when present. The
override is re-read per request, so an admin edit takes effect on the user's
next launch without a server restart.

**Response payload (envelope-wrapped; values below are the env defaults):**

```json
{
  "success": true,
  "data": {
    "ads": { "rewarded": false, "banner": true, "appOpen": false, "useReal": false },
    "hints": { "freeOnInstall": 10, "ownKeyDivisor": 3 },
    "onDevice": {
      "enabled": true,
      "netUrl": "http://103.157.205.175:3000/api/engine/net",
      "netBytes": 50760458,
      "visionModel": "gpt-5.4"
    },
    "history": { "storedScreenshotsMax": 5 },
    "ui": {
      "backend": false,
      "providers": false,
      "engineTuning": false,
      "visionModel": false,
      "licenses": false,
      "deviceId": false
    },
    "appIcon": { "variant": "auto" }
  }
}
```

- `ads.*` — which ad formats the app may show, and whether to use the real
  AdMob unit ids (vs Google's test units).
- `hints.freeOnInstall` — starter hints granted on first install (see
  `/api/hints/claim`); `hints.ownKeyDivisor` — with the user's **own** OpenAI
  key, 1 hint is charged per N analyses (metering is client-side).
- `onDevice.*` — on-device Pikafish availability, the NNUE net download URL
  (defaults to this backend's own `GET /api/engine/net`), the expected net
  size in bytes (download verification), and the default OpenAI vision model
  for the on-device (BYO-key) board reading.
- `history.storedScreenshotsMax` — how many analyzed screenshots the app keeps
  on device.
- `ui.*` — visibility of optional Settings sections (all default hidden).
- `appIcon.variant` — `auto` \| `vi` \| `en` launcher icon + name variant
  (`auto` follows the in-app App-language).

**curl:**

```bash
curl -s http://localhost:3000/api/config
```

---

## `POST /api/hints/claim`

Install grant. The app calls this **once on first launch** (before seeding its
device-local hint wallet) to learn how many hints this install starts with.
Keyed by the stable `x-device-id` header, so a reinstall on the same device is
recognized and does **not** re-grant the free hints. Guarded by the per-device
rate cap on top of the global per-IP throttle.

**Headers:**

| Header        | Required | Notes                                                  |
| ------------- | -------- | ------------------------------------------------------ |
| `x-device-id` | yes      | 8–256 chars; else `400 INVALID_DEVICE_ID`.             |

**Response payload (envelope-wrapped):**

```json
{ "success": true, "data": { "hints": 10, "source": "first_install" } }
```

`source` explains the balance (priority order, highest first):

| `source`        | `hints`                              | When                                                       |
| --------------- | ------------------------------------ | ---------------------------------------------------------- |
| `grant`         | the granted amount                   | Device is in the manual "Hint Grants" allowlist — wins on EVERY (re)install while listed. |
| `returning`     | `0`                                  | Device already in the install ledger (no re-grant).        |
| `first_install` | `HINTS_FREE_ON_INSTALL` (default 10) | Brand-new device; it is recorded in the ledger.            |

The ledger (`installs.json`) and allowlist (`grants.json`) live in
`HINTS_DATA_DIR` (default `./data`) and are managed via `/api/admin/*`.

**curl:**

```bash
curl -s -X POST http://localhost:3000/api/hints/claim \
  -H 'x-device-id: my-device-0001'
```

---

## `GET /api/engine/net`

Serves the Pikafish NNUE **master-net** that the on-device engine downloads,
so the app fetches it from our backend (the host it already talks to) instead
of GitHub releases. Returns **raw bytes** (no envelope) and **skips the per-IP
throttle**.

- **Source file:** `ONDEVICE_NET_PATH` (default
  `./release/engine/master-net.nnue`); must be the master-net of
  `ONDEVICE_NET_BYTES` bytes (default `50760458`) — the app verifies the
  downloaded size.
- **Response headers:** `Content-Type: application/octet-stream`,
  `Cache-Control: public, max-age=31536000, immutable`, plus `Content-Length`
  and **HTTP range support** (resumable downloads) via Express `sendFile`.
- **404 `NET_UNAVAILABLE`** (envelope-wrapped) when `ONDEVICE_NET_PATH` is
  unset or the file is missing.

**curl (resumable):**

```bash
curl -s -C - -o master-net.nnue http://localhost:3000/api/engine/net
```

---

## Admin API (`/api/admin/*`)

Management API for remote config, hint grants, and the install ledger. All
routes skip the per-IP throttle.

**Auth** — every route **except** `GET /api/admin/status` requires BOTH:

| Header           | Check                                                        |
| ---------------- | ------------------------------------------------------------ |
| `x-device-id`    | Must be a key in `<HINTS_DATA_DIR>/admins.json` (hand-edited allowlist, re-read on change; keys starting with `_` are comments). |
| `x-admin-secret` | Must equal env `ADMIN_SECRET` (constant-time compare). Empty `ADMIN_SECRET` = admin write API **disabled** (fail closed). |

Failure → `403 ADMIN_FORBIDDEN`. All responses are envelope-wrapped.

### `GET /api/admin/status`

Identity probe (no secret): tells the app whether to show the admin UI.

```json
{ "success": true, "data": { "isAdmin": true } }
```

### `GET /api/admin/config` / `PUT /api/admin/config` / `DELETE /api/admin/config`

Remote-config override (persisted to `config-overrides.json`; users pick it up
on their next launch via `GET /api/config`).

- **GET** → `{ "features": <Features>, "overridden": boolean }` — the
  effective config (override if set, else env defaults).
- **PUT** — body is a **complete** `Features` object (same shape as the
  `GET /api/config` payload), validated against the schema; invalid →
  `400 INVALID_CONFIG` with per-field issues in `details`. Returns
  `{ "features": …, "overridden": true }`.
- **DELETE** — clears the override (back to env defaults). Returns
  `{ "features": …, "overridden": false }`.

### `GET /api/admin/grants` / `PUT /api/admin/grants` / `DELETE /api/admin/grants`

Manual hint-grant allowlist (`grants.json`) consumed by `/api/hints/claim`.

- **GET** → `{ "<deviceId>": <hints>, … }`.
- **PUT** — body `{ "deviceId": string, "hints": number }` (`hints` ≥ 0,
  floored to an integer; else `400 INVALID_GRANT`). Returns
  `{ "deviceId", "hints" }`.
- **DELETE** — body `{ "deviceId": string }`. Returns `{ "removed": "<id>" }`.

### `GET /api/admin/installs` / `PUT /api/admin/installs` / `DELETE /api/admin/installs`

Install ledger (`installs.json`) — the anti-reinstall record behind
`/api/hints/claim`. Deleting a device makes its next claim count as a fresh
install again.

- **GET** → `{ "<deviceId>": "<firstSeen ISO timestamp>", … }`.
- **PUT** — body `{ "deviceId": string, "firstSeen"?: string }` (`firstSeen`
  defaults to now). Returns `{ "deviceId", "firstSeen" }`.
- **DELETE** — body `{ "deviceId": string }`. Returns `{ "removed": "<id>" }`.

`deviceId` must be 8–256 chars on all mutations (else `400 INVALID_DEVICE_ID`).

**curl (set a grant):**

```bash
curl -s -X PUT http://localhost:3000/api/admin/grants \
  -H 'x-device-id: my-admin-device-01' \
  -H 'x-admin-secret: ********' \
  -H 'Content-Type: application/json' \
  -d '{ "deviceId": "friend-device-0001", "hints": 50 }'
```

---

## Xiangqi coordinate + FEN/UCI spec

The backend implements this precisely; it is covered by unit tests.

### Coordinates

- `file`: int **0..8** (`0` = Red far-left file, `8` = Red far-right file).
- `rank`: int **0..9** (`0` = Red home rank where Red pieces start, `9` = Black home rank).
- file index → column letter: `0->a, 1->b, 2->c, 3->d, 4->e, 5->f, 6->g, 7->h, 8->i`.

### UCI moves

- `UCI = fromCol + fromRank + toCol + toRank`.
- Example: `{file:1,rank:2} -> {file:1,rank:7}` = **`b2b7`**.

### Human / WXF notation

- `bestMove.human` is **localized traditional notation** (the relative form
  players actually use) in the request `language` (`en` \| `vi` \| `zh`,
  default `vi`). Each side numbers files 1..9 from its **own right** (Red
  file = `9 - file`, Black file = `file + 1`).
- `bestMove.notation` is the **universal WXF code** (e.g. `C8+5`, `H8+7`,
  `+R=4`).
- Example: `b2b7` with a Red cannon on b2 → `vi` "Pháo 8 tiến 5", `en`
  "Cannon 8 advances 5", WXF `C8+5`.

### FEN (Pikafish / standard)

- Piece letters: King = `K`, Advisor = `A`, Elephant = `B`, Horse = `N`,
  Rook = `R`, Cannon = `C`, Pawn = `P`. **Uppercase = Red, lowercase = Black.**
- Placement is written **rank 9 first** (Black home, top) **down to rank 0**
  (Red home, bottom); ranks joined by `/`.
- Within a rank, list file `0..8` left to right; collapse consecutive empty
  squares into a digit.
- Full FEN = `"<placement> <side> - - 0 1"`; `side` = `w` for Red to move,
  else `b`.

**Canonical start position** (asserted EXACTLY in a unit test):

```
rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1
```

> **TODO (must verify before production):** the exact board **orientation** of
> the FEN we produce must be validated against the **real Pikafish binary**.
> Feed a known position, compare Pikafish's reported board/best move against a
> trusted reference, and confirm files/ranks/side are not mirrored before
> trusting real-engine output.
