# Xiangqi Solver — Backend

NestJS + TypeScript backend that turns a screenshot (or an explicit board) of a
Xiangqi (Chinese chess) position into an engine-recommended best move.

**Product flow:** screenshot → AI vision extracts board-state JSON (never a move)
→ validate + normalize → convert to FEN → Xiangqi engine returns best move →
human explanation. The `/board` endpoint skips vision and runs the engine on a
board you supply directly.

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

| Script              | Purpose                                  |
| ------------------- | ---------------------------------------- |
| `npm run build`     | Compile to `dist/` (strict `tsc`)        |
| `npm start`         | Start (no watch)                         |
| `npm run start:dev` | Start with watch                         |
| `npm run start:prod`| Run compiled `dist/main.js`              |
| `npm run lint`      | ESLint (flat config, must exit 0)        |
| `npm run format`    | Prettier write                           |
| `npm test`          | Unit tests                               |
| `npm run test:cov`  | Unit tests with coverage                 |
| `npm run test:e2e`  | Supertest end-to-end suite               |

### Docker

```bash
docker compose up --build      # backend on http://localhost:3000/api
```

---

## Environment

Every variable has a safe mock default (see `.env.example`).

| Variable                     | Default               | Description                                              |
| ---------------------------- | --------------------- | -------------------------------------------------------- |
| `PORT`                       | `3000`                | HTTP port (binds `0.0.0.0`)                              |
| `AI_PROVIDER`                | `mock`                | `gemini` \| `openai` \| `mock`                          |
| `ENGINE_PROVIDER`            | `mock`                | `pikafish` \| `mock`                                    |
| `GEMINI_API_KEY`             | _(empty)_             | Required only when `AI_PROVIDER=gemini`                 |
| `OPENAI_API_KEY`             | _(empty)_             | Required only when `AI_PROVIDER=openai`                 |
| `OPENAI_MODEL`               | `gpt-4o-mini`         | OpenAI vision model                                     |
| `GEMINI_MODEL`               | `gemini-1.5-flash`    | Gemini vision model                                     |
| `PIKAFISH_BINARY_PATH`       | _(empty)_             | Path to the Pikafish UCI binary                         |
| `ENGINE_DEFAULT_DEPTH`       | `12`                  | Default search depth (1..30)                            |
| `ENGINE_DEFAULT_MOVE_TIME_MS`| `1000`                | Default move time ms (50..60000)                        |
| `MAX_UPLOAD_BYTES`           | `8388608`             | Max screenshot size (8 MB)                              |
| `RATE_LIMIT_TTL`             | `60`                  | Throttle window (seconds)                               |
| `RATE_LIMIT_LIMIT`           | `30`                  | Max requests per window                                 |

---

## Mock mode

With the defaults, the backend is fully self-contained:

- **MockVisionProvider** always "detects" the standard 32-piece start position.
- **MockEngineService** returns a deterministic opening move
  (`b2e2` for Red, `b7e7` for Black, score `+0.30`).

This makes the whole pipeline testable and demoable offline.

---

## API

All routes are prefixed with `/api`. Every response except `/api/health` is
wrapped in a success envelope; errors use an error envelope.

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
`provider?`, `sideToMove?`, `engineProvider?`, `engineDepth?`, `engineMoveTimeMs?`.
Returns `AnalysisResult`.

### `POST /api/analysis/board` (application/json)

```jsonc
{
  "sideToMove": "red",
  "pieces": [
    { "color": "red", "type": "king", "file": 4, "rank": 0 },
    { "color": "black", "type": "king", "file": 4, "rank": 9 }
  ],
  "engineDepth": 12          // optional
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
    "confidence": 0.9
  },
  "bestMove": {
    "from": { "file": 1, "rank": 2 }, "to": { "file": 4, "rank": 2 },
    "uci": "b2e2", "human": "B3 to E3", "score": "+0.30", "depth": 12
  },
  "explanation": "For Red to move, the mock engine recommends B3 to E3 ...",
  "warnings": [],
  "engine": { "provider": "mock", "ok": true },
  "vision": { "provider": "mock", "ok": true }
}
```

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

`ENGINE_PROVIDER=pikafish` spawns the Pikafish UCI binary at
`PIKAFISH_BINARY_PATH` using a **spawn args array (never a shell string)**, so
there is no command-injection surface. The UCI handshake is
`uci → uciok → isready → readyok → position fen <fen> → go depth N|movetime M →
bestmove`, with a hard timeout that kills the child (SIGTERM, then SIGKILL).

> **TODO (before production):** the exact board orientation encoded in the FEN
> (which home rank is written first, which side is file 0) must be validated
> against the real Pikafish binary. The mock engine is orientation-agnostic, so
> this only matters once a real engine is wired up.

If the binary path is empty or missing, the engine fails with a clear
`SERVICE_UNAVAILABLE` error recommending `ENGINE_PROVIDER=mock`.

---

## Security & privacy

- Uploads are validated for **mime type** (png/jpeg/webp) and **size** (≤ 8 MB);
  violations return `400`.
- Screenshots are processed **in memory and never persisted** by default; raw
  image bytes are never logged.
- Global **rate limiting** (Throttler) and per-request **timeouts** on outbound
  AI/engine calls.
- Config is read from env with safe mock defaults — **no hardcoded secrets**.
