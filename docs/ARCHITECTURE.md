# Architecture

This document describes the layers, module boundaries, and data flow of the
Xiangqi Solver. The system has two deployable units: a **Flutter Android app**
(`apps/mobile`) and a **NestJS backend** (`apps/backend`). They communicate over
a single, versioned HTTP contract (see [`API.md`](API.md)). Within the app,
Dart and native Kotlin communicate over platform channels (see
[`ANDROID_NATIVE.md`](ANDROID_NATIVE.md)).

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
│   └── types/                   Shared cross-module types (AnalysisResult, etc.).
└── modules/
    ├── health/                  GET /api/health (envelope-skipped).
    ├── analysis/                Orchestrates vision -> board -> engine.
    │   └── dto/                 Request DTOs for /screenshot and /board.
    ├── ai/                      Vision abstraction.
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

The two entry points produce the same `AnalysisResult`:

- `POST /api/analysis/screenshot` runs **vision → board → engine**.
- `POST /api/analysis/board` skips vision and runs **board → engine** on a
  position you supply (useful for tests, puzzles, and debugging).

```
screenshot (multipart)            board (json)
        │                              │
        v                              │
  [AI VisionProvider]                  │
   mock|gemini|openai                  │
        │ recognized pieces            │ given pieces
        └──────────────┬───────────────┘
                       v
              [Board validator]
                       v
              [Board normalizer]  --> warnings[]
                       v
                 [FEN builder] --> fen, sideToMove
                       v
              [EngineProvider]
               mock|pikafish
                       │ bestmove (UCI) | none
                       v
            [UCI -> {from,to}/human]
                       v
                 AnalysisResult
   { analysisId, board, bestMove, explanation,
     warnings, engine:{provider,ok}, vision:{provider,ok} }
```

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
 │         │                 │ save PNG to cache                  │           │
 │         │ ◄───────────────│ return absolute path               │           │
 │         │ screenshotCaptured{path,w,h} (event) │               │           │
 │         │                 │                   │                │           │
 │         │ POST /api/analysis/screenshot (multipart PNG) ─────► │           │
 │         │                 │                   │ recognize ───► │           │
 │         │                 │                   │ ◄───── pieces  │           │
 │         │                 │                   │ validate+normalize+FEN     │
 │         │                 │                   │ bestmove ─────────────────►│
 │         │                 │                   │ ◄──────────── UCI bestmove │
 │         │ ◄─────────────────── AnalysisResult (JSON envelope)  │           │
 │ ◄─── overlay shows best move + score + explanation             │           │
```

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
