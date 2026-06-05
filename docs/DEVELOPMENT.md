# Development Guide

How to work in the Xiangqi Solver monorepo: set up, run checks, extend the AI
vision and engine layers, and follow the project's coding and testing
conventions.

---

## 1. Dev workflow

```bash
# One-time: make scripts executable
chmod +x scripts/*.sh

# Install all dependencies (backend deps + flutter pub get if Flutter present)
bash scripts/setup.sh

# Run everything in mock mode (no paid APIs, no engine binary)
cd apps/backend
AI_PROVIDER=mock ENGINE_PROVIDER=mock npm run start:dev

# In another terminal, run the app against the backend
cd apps/mobile
flutter run
# Emulator -> backend base URL is http://10.0.2.2:3000
# Physical device -> use the host's LAN IP (same Wi-Fi)
```

Iterate on the backend with `npm run start:dev` (watch mode). Iterate on the
app with Flutter hot reload (`r`) / hot restart (`R`).

---

## 2. Running checks

Run the tolerant, monorepo-wide quality gate from the repo root:

```bash
bash scripts/check.sh
```

It runs:

- **Backend:** `npm run lint`, `npm test`, `npm run build` (in `apps/backend`).
- **Mobile:** `flutter analyze`, `flutter test` (in `apps/mobile`) — **only if
  Flutter is on PATH**; otherwise these steps are clearly marked `SKIPPED`.

The script keeps going after a failure, prints a `[PASS]/[FAIL]/[SKIP]`
summary, and exits non-zero **only** when a real check fails (skips never fail
the run). Use it locally before pushing and as the basis for CI.

You can also run pieces directly:

```bash
# Backend
cd apps/backend && npm run lint && npm test && npm run build

# Mobile
cd apps/mobile && flutter analyze && flutter test
```

---

## 3. Adding a new AI vision provider

Vision providers live under `apps/backend/src/modules/ai/providers` and
implement the module's `VisionProvider` interface. They are selected by the
request `provider` field or the `AI_PROVIDER` env default.

1. **Create the provider** in `modules/ai/providers/<name>.provider.ts`
   implementing the same interface as `mock`/`gemini`/`openai`. It takes an
   image (buffer + mime type) and returns recognized pieces with confidences in
   the **input** `BoardPiece` shape (`color`, `type`, `file` 0..8, `rank`
   0..9, `confidence?`).
2. **Add it to the provider enum / factory** so `provider: "<name>"` resolves
   to your implementation, and read any keys/config from `config/`.
3. **Prompts** (for LLM-based providers) go under `modules/ai/prompts`. Reuse
   the existing coordinate/FEN conventions so output maps cleanly to the
   domain. Never log raw image bytes.
4. **Keep the domain untouched.** Your provider returns recognized pieces; the
   `board` module validates/normalizes and builds the FEN. Do not embed
   coordinate or FEN logic in a provider.
5. **Add tests:** a unit test with a stubbed model response asserting the
   provider maps output into the correct `BoardPiece[]`, plus error handling
   (sets `vision.ok=false` / surfaces warnings rather than throwing 500s where
   reasonable).
6. **Document it** in [`API.md`](API.md) (provider enum) and the README env
   table if it needs new env vars.

---

## 4. Adding a new engine

Engine providers live under `apps/backend/src/modules/engine` and implement the
`EngineProvider` interface. They are selected by the request `engineProvider`
field or the `ENGINE_PROVIDER` env default.

1. **Create the provider** implementing the same interface as
   `mock`/`pikafish`. Input: a FEN + side to move + optional `engineDepth` /
   `engineMoveTimeMs`. Output: a best move in **UCI** (e.g. `b2b7`) plus
   `score` and `depth`, or `null` when no move exists.
2. **Let the domain do coordinate/FEN work.** The engine consumes the FEN the
   `board` module produced and returns UCI; the domain converts UCI back into
   `{from,to}` / `human`. Do not reimplement coordinate math in the engine.
3. **External binaries (like Pikafish):** spawn over UCI, read `PIKAFISH_PATH`
   / `PIKAFISH_NNUE_PATH` (or your engine's equivalents) from `config/`, and
   apply `engineDepth` / `engineMoveTimeMs` limits. Fail soft: set
   `engine.ok=false` and add a warning rather than crashing the request.
4. **Add tests:** unit-test the UCI parsing/limits with a fake process; the
   `mock` engine keeps the rest of the suite hermetic.
5. **Orientation check (important):** before trusting a real engine, validate
   that the FEN orientation we emit matches what the engine expects (see the
   Pikafish TODO in [`API.md`](API.md) and the README). A mirrored board
   silently produces wrong moves.

---

## 5. Coding standards

- **TypeScript/NestJS (backend):**
  - Keep modules single-responsibility; respect the boundaries in
    [`ARCHITECTURE.md`](ARCHITECTURE.md) (orchestrator → providers/domain;
    domain depends on nothing).
  - Validate all request input with DTOs/validation pipes; never trust client
    input (file size/type, enums, integer ranges).
  - All responses go through the global envelope; errors through the global
    exception filter with a stable `code`.
  - Lint must pass (`npm run lint`); fix warnings rather than suppressing them.
- **Dart/Flutter (mobile):**
  - `flutter analyze` must be clean; follow `analysis_options.yaml`.
  - Keep the platform-channel contract in one place and match the names/shapes
    in [`ANDROID_NATIVE.md`](ANDROID_NATIVE.md) exactly.
- **Kotlin (native):**
  - One responsibility per component (activity vs services); emit the exact
    event shapes from the contract.
- **General:**
  - No secrets in the repo (`.env` is gitignored; keys live on the backend
    only).
  - No raw image/screenshot bytes in logs.
  - Update the docs in `docs/` whenever you change a contract.

---

## 6. Testing strategy

- **Domain (board) — exhaustive unit tests.** This is the highest-value target:
  - file/rank ↔ column-letter mapping (`0->a … 8->i`),
  - UCI building (`{file:1,rank:2}->{file:1,rank:7}` == `"b2b7"`),
  - human notation (`UPPER(col)+(rank+1)`, e.g. `B3`→`B8`),
  - FEN placement order (rank 9 → rank 0), empty-run collapsing, side flag,
  - **the canonical start FEN asserted exactly:**
    `rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1`,
  - validator/normalizer behavior (out-of-bounds, duplicates → warnings).
- **Providers — unit tests with stubs/mocks.** Test mapping and error handling;
  never hit real Gemini/OpenAI/Pikafish in unit tests.
- **Orchestration (analysis) — service tests** wiring mock vision + mock engine
  to assert the full `AnalysisResult` shape and the `vision.ok` / `engine.ok` /
  `warnings` behavior on degraded paths.
- **API/e2e — mock mode.** Hit `/api/health`, `/api/analysis/board`, and
  `/api/analysis/screenshot` with mock providers to verify the response
  envelope, validation errors (oversized/unsupported upload), and status codes.
- **Mobile — `flutter test`** for Dart logic (channel-message
  encoding/decoding, the capture→post flow with a faked channel and HTTP).
- **Run `bash scripts/check.sh`** before every push; wire it into CI as the
  single entry point.
