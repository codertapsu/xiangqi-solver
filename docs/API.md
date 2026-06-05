# Backend API Reference

The NestJS backend exposes the HTTP API consumed by the Flutter app. This
document is the authoritative reference and matches the shared API contract
exactly.

- **Base prefix:** every route is under `/api`.
- **Binding:** server binds host `0.0.0.0`, port = env `PORT` (default `3000`).
- **CORS:** enabled for all origins in development.
- **Content types:** JSON for most endpoints; `multipart/form-data` for the
  screenshot upload.

---

## Response envelope

A global NestJS interceptor wraps the payload of **every** endpoint **except**
`GET /api/health`.

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

`GET /api/health` is **not** wrapped — it uses the `@SkipEnvelope()` decorator,
which the interceptor reads to bypass wrapping.

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
    human: string,               // e.g. "B3"
    score: string,
    depth: number
  } | null,
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
  pieces: BoardPiece[],
  engineProvider?: "pikafish" | "mock",      // default from ENGINE_PROVIDER
  engineDepth?: int 1..30,
  engineMoveTimeMs?: int 50..60000
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
      "human": "A1",
      "score": "+2.10",
      "depth": 12
    },
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
| `screenshot`      | image file  | yes      | `image/png`, `image/jpeg`, or `image/webp`; **max 8 MB**.          |
| `provider`        | string enum | no       | `gemini` \| `openai` \| `mock`; default from `AI_PROVIDER` env.    |
| `sideToMove`      | string enum | no       | `red` \| `black` \| `unknown`.                                     |
| `engineProvider`  | string enum | no       | `pikafish` \| `mock`; default from `ENGINE_PROVIDER` env.          |
| `engineDepth`     | int 1..30   | no       | Engine search depth.                                               |
| `engineMoveTimeMs`| int 50..60000| no      | Per-move think time in ms.                                         |
| `engineThreads`   | int 1..1024 | no       | Pikafish `Threads`.                                                |
| `engineHashMb`    | int 1..32768| no       | Pikafish `Hash` (MB).                                              |
| `engineMultiPv`   | int 1..10   | no       | Top-N moves (`MultiPV`); >1 fills `candidates[]`.                  |
| `language`        | string enum | no       | `en` \| `vi` \| `zh`; notation language. Default `en`.            |

**Response payload:** `AnalysisResult` (same shape as `/board`), with
`vision.provider` reflecting the chosen vision provider and
`board.pieces`/`board.confidence` derived from recognition. When
`engineMultiPv > 1`, `candidates[]` holds the ranked moves (index 0 = best).

**curl (mock mode — any small PNG works; mock ignores image bytes):**

```bash
curl -s -X POST http://localhost:3000/api/analysis/screenshot \
  -F 'screenshot=@./sample.png;type=image/png' \
  -F 'provider=mock' \
  -F 'engineProvider=mock' \
  -F 'sideToMove=red'
```

**Example error (file too large):**

```json
{
  "success": false,
  "error": {
    "code": "PAYLOAD_TOO_LARGE",
    "message": "Screenshot exceeds the 8 MB limit.",
    "details": { "maxBytes": 8388608 }
  }
}
```

**Example error (unsupported type):**

```json
{
  "success": false,
  "error": {
    "code": "UNSUPPORTED_MEDIA_TYPE",
    "message": "screenshot must be image/png, image/jpeg, or image/webp."
  }
}
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
| `screenshot` | image file  | yes      | `image/png`, `image/jpeg`, or `image/webp`; **max 8 MB**.       |
| `provider`   | string enum | no       | `gemini` \| `openai` \| `mock`; default from `AI_PROVIDER` env. |
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

## Xiangqi coordinate + FEN/UCI spec

The backend implements this precisely; it is covered by unit tests.

### Coordinates

- `file`: int **0..8** (`0` = Red far-left file, `8` = Red far-right file).
- `rank`: int **0..9** (`0` = Red home rank where Red pieces start, `9` = Black home rank).
- file index → column letter: `0->a, 1->b, 2->c, 3->d, 4->e, 5->f, 6->g, 7->h, 8->i`.

### UCI moves

- `UCI = fromCol + fromRank + toCol + toRank`.
- Example: `{file:1,rank:2} -> {file:1,rank:7}` = **`b2b7`**.

### Human notation

- `Human = UPPER(col) + (rank + 1)`.
- Example: `b2b7` → from **`B3`** to **`B8`**.

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
