# Xiangqi Solver

A **Xiangqi (Chinese Chess) training and analysis assistant**. It captures the
board from your Android screen using the official Android screen-capture API,
sends the screenshot to a backend that recognizes the position with an AI
vision model, normalizes it into a legal board, runs a Xiangqi engine, and
shows you the engine's best move on a floating overlay.

> Think of it as an over-the-board coach: point it at a position and learn the
> best continuation, the resulting evaluation, and a short explanation.

---

## ⚠️ Responsible-use / fair-play warning

This project is built for **study, post-game review, puzzle solving, and
training** — not for cheating.

- **Using a move-suggesting assistant during a live, rated, or competitive game
  on a third-party app almost certainly violates that app's Terms of Service
  and basic fair-play rules.** Do not do it. You are solely responsible for how
  you use this software.
- The app captures the screen **only** through Android's official
  `MediaProjection` API, which **always** requires an explicit per-session user
  consent dialog shown by the system. There is no hidden or silent capture.
- The app **respects `FLAG_SECURE`**: apps that mark their windows secure
  (banking apps, DRM video, and many games) will appear **black** in any
  captured frame. The solver cannot and does not bypass this — that is by
  design and is the OS protecting those apps.

Use it on your own analysis boards, study screens, and saved positions. Be a
good sport.

---

## Architecture (capture → result)

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │ Android device                                                         │
 │                                                                        │
 │  ┌───────────────┐   MethodChannel / EventChannel                      │
 │  │  Flutter UI   │ <───────────────────────────────┐                   │
 │  │ (Dart)        │                                  │                   │
 │  └──────┬────────┘                                  │                   │
 │         │ startSolverMode / captureScreenshot       │ events            │
 │         v                                            │                   │
 │  ┌──────────────────────────────────────────────────┴──────────────┐   │
 │  │ Native (Kotlin)                                                  │   │
 │  │  OverlayService (floating button)                               │   │
 │  │  ScreenCaptureService (foreground svc, mediaProjection type)    │   │
 │  │  MediaProjectionPermissionActivity (system consent)             │   │
 │  │  -> saves downscaled JPEG to cache                               │   │
 │  └──────────────────────────────┬──────────────────────────────────┘   │
 │                                 │ JPEG file path                        │
 │  ┌──────────────────────────────┴──────────────────────────────────┐   │
 │  │ Flutter HTTP client  --- multipart screenshot --->               │   │
 │  └──────────────────────────────┬──────────────────────────────────┘   │
 └─────────────────────────────────┼──────────────────────────────────────┘
                                   │  POST /api/analysis/screenshot[/stream]
                                   v
 ┌──────────────────────────────────────────────────────────────────────┐
 │ Backend (NestJS)                                                       │
 │                                                                        │
 │   AnalysisController                                                   │
 │        │                                                               │
 │        v                                                               │
 │   AI Vision provider (mock | gemini | openai)                         │
 │        │  compact 10x9 grid -> pieces                                  │
 │        v                                                               │
 │   Board validator + normalizer  -->  FEN builder                      │
 │        │  legal board + FEN                                            │
 │        v                                                               │
 │   Engine provider (mock | pikafish)  -->  best move (UCI)             │
 │        │                                                               │
 │        v                                                               │
 │   AnalysisResult (board + bestMove + explanation + warnings)          │
 └──────────────────────────────────────────┬───────────────────────────┘
                                            │  JSON (response envelope)
                                            v
                            Flutter renders best move on the overlay
```

---

## Monorepo structure

```
xiangqi-solver/
├── apps/
│   ├── mobile/          Flutter Android app + native Kotlin
│   │                    (overlay, MediaProjection, foreground service,
│   │                     screenshot capture, Method/EventChannel)
│   └── backend/         NestJS API
│                        (health, analysis, AI vision providers,
│                         board validator/normalizer/FEN, engine)
├── docs/
│   ├── ARCHITECTURE.md  Layers, module boundaries, data flow
│   ├── API.md           Full HTTP API reference + curl examples
│   ├── ANDROID_NATIVE.md Method/EventChannel + native components
│   └── DEVELOPMENT.md   Dev workflow, adding providers/engines, testing
├── scripts/
│   ├── setup.sh         Install backend + Flutter deps
│   └── check.sh         Lint + test + build (tolerant, with summary)
├── README.md            This file
└── .gitignore
```

---

## Requirements / toolchain

| Tool         | Version (suggested)        | Used by         |
| ------------ | -------------------------- | --------------- |
| Node.js      | 20 LTS or newer            | backend         |
| npm          | 10+ (ships with Node 20)   | backend         |
| Flutter SDK  | 3.22+ (Dart 3.x)           | mobile app      |
| Android SDK  | API 34 (Android 14) +      | mobile app      |
| JDK          | 17 (for Gradle/Android)    | mobile build    |
| Docker       | optional                   | backend (run)   |
| Pikafish     | optional (real engine)     | backend engine  |

You can run the **entire end-to-end flow with zero paid APIs and no engine
binary** using **mock mode** (see below).

---

## Setup

From the repo root:

```bash
# Installs backend deps (npm ci/install) and runs `flutter pub get`
# if Flutter is on your PATH. Prints what it did vs skipped.
chmod +x scripts/*.sh    # one time
bash scripts/setup.sh
```

To run all quality checks at any time (lint + test + build; Flutter steps are
skipped cleanly if Flutter is not installed):

```bash
bash scripts/check.sh
```

The same checks run hosted on every push / pull request via GitHub Actions —
see [`.github/workflows/ci.yml`](.github/workflows/ci.yml) (backend lint +
unit + e2e + build; Flutter analyze + test).

---

## Running the backend

```bash
cd apps/backend

# Install (if not done by scripts/setup.sh)
npm install

# Development (watch mode)
npm run start:dev

# Production-style
npm run build
npm run start:prod
```

The server binds `0.0.0.0` on `PORT` (default **3000**). All routes are
prefixed with `/api`. CORS is enabled for all origins in development.

Quick smoke test:

```bash
curl -s http://localhost:3000/api/health
# {"status":"ok","timestamp":"...","uptimeSeconds":...,"version":"..."}
```

### Backend with Docker

```bash
cd apps/backend
docker build -t xiangqi-backend .
docker run --rm -p 3000:3000 \
  -e AI_PROVIDER=mock \
  -e ENGINE_PROVIDER=mock \
  xiangqi-backend
```

---

## Running the Flutter app

```bash
cd apps/mobile

flutter pub get

# Run on a connected device or emulator
flutter run

# Build a release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

The app needs the backend's base URL. On the Android **emulator**, the host
machine is reachable at **`http://10.0.2.2:3000`** (not `localhost`). On a
**physical device**, use your computer's LAN IP, e.g. `http://192.168.1.50:3000`,
and make sure both are on the same network.

---

## Android permissions explained

| Permission / consent                       | Why it is needed                                                                 |
| ------------------------------------------ | -------------------------------------------------------------------------------- |
| `SYSTEM_ALERT_WINDOW` (overlay)            | Draw the floating "analyze" button on top of other apps.                         |
| `FOREGROUND_SERVICE`                       | Keep the capture service alive while you switch to the board app.                |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION`      | Android 14+ requires this typed foreground service to use `MediaProjection`.     |
| `POST_NOTIFICATIONS` (Android 13+)         | Show the mandatory foreground-service notification.                              |
| MediaProjection consent (runtime dialog)   | Per-session system dialog the user must accept to allow screen capture.          |

### Consent flow

1. App checks/requests **overlay** permission
   (`checkOverlayPermission` / `requestOverlayPermission`) — this opens the
   system overlay settings screen.
2. App requests **screen capture** (`requestScreenCapturePermission`) — this
   launches the official `MediaProjection` consent dialog and resolves `true`
   only if the user grants it.
3. With both granted, `startSolverMode` starts the foreground service and the
   floating overlay. `captureScreenshot` then saves a downscaled JPEG to the
   app cache and returns its absolute path.

See [`docs/ANDROID_NATIVE.md`](docs/ANDROID_NATIVE.md) for full details.

---

## Environment variables (backend)

| Variable                      | Default                  | Description                                                            |
| ----------------------------- | ------------------------ | ---------------------------------------------------------------------- |
| `PORT`                        | `3000`                   | HTTP port; server binds `0.0.0.0`.                                     |
| `AI_PROVIDER`                 | `mock`                   | Default vision provider: `mock` \| `gemini` \| `openai`.               |
| `ENGINE_PROVIDER`             | `mock`                   | Default engine: `mock` \| `pikafish`.                                  |
| `GEMINI_API_KEY`              | —                        | Required when `AI_PROVIDER=gemini`.                                    |
| `GEMINI_MODEL`                | `gemini-3-flash-preview` | Gemini vision model id.                                                |
| `OPENAI_API_KEY`              | —                        | Required when `AI_PROVIDER=openai`.                                    |
| `OPENAI_MODEL`                | `gpt-5.4`                | OpenAI vision model id.                                                |
| `VISION_PREPROCESS`           | `true`                   | Server-side image normalization (EXIF auto-rotate + downscale + JPEG re-encode) before the vision call. |
| `VISION_IMAGE_SHORT_SIDE`     | `768`                    | Downscale budget: shortest side, px.                                   |
| `VISION_IMAGE_LONG_SIDE`      | `2048`                   | Downscale budget: longest side, px.                                    |
| `PIKAFISH_BINARY_PATH`        | —                        | Absolute path to the Pikafish UCI binary (when `ENGINE_PROVIDER=pikafish`). |
| `PIKAFISH_NNUE_PATH`          | —                        | Path to the Pikafish NNUE weights file; empty = `pikafish.nnue` next to the binary. |
| `ENGINE_DEFAULT_DEPTH`        | `12`                     | Default engine search depth (1..30).                                   |
| `ENGINE_DEFAULT_MOVE_TIME_MS` | `1000`                   | Default per-move think time in ms (50..60000).                         |
| `ENGINE_POOL_SIZE`            | `2`                      | Warm engine pool size — persistent engine processes; also the hard cap on concurrent searches. |

This is the core set. See [`apps/backend/.env.example`](apps/backend/.env.example)
for the full list (engine UCI tuning, rate limits, hint economy, remote-config
feature flags, admin API).

Create `apps/backend/.env` (it is gitignored). Example:

```dotenv
PORT=3000
AI_PROVIDER=mock
ENGINE_PROVIDER=mock
```

---

## Mock mode walkthrough (zero paid APIs, no engine binary)

Mock mode runs the **entire** capture-to-result flow without any external API
key or engine. The vision provider returns a deterministic recognized board and
the engine provider returns a deterministic best move.

1. Start the backend in mock mode:

   ```bash
   cd apps/backend
   AI_PROVIDER=mock ENGINE_PROVIDER=mock npm run start:dev
   ```

2. Health check:

   ```bash
   curl -s http://localhost:3000/api/health
   ```

3. Analyze a board **without any image** (bypasses vision, runs the engine on
   a position you provide):

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

4. Analyze a **screenshot** through the mock vision provider (any small PNG
   works — the mock ignores its contents and returns a fixed board):

   ```bash
   curl -s -X POST http://localhost:3000/api/analysis/screenshot \
     -F 'screenshot=@./sample.png;type=image/png' \
     -F 'provider=mock' \
     -F 'engineProvider=mock' \
     -F 'sideToMove=red'
   ```

5. Same analysis, **progressively** (NDJSON: one JSON object per line —
   `{"stage":"received"}` → `{"stage":"board",...}` as soon as vision finishes
   → `{"stage":"done","data":...}` when the engine is done):

   ```bash
   curl -sN -X POST http://localhost:3000/api/analysis/screenshot/stream \
     -F 'screenshot=@./sample.png;type=image/png' \
     -F 'provider=mock' \
     -F 'engineProvider=mock'
   ```

You will get a full `AnalysisResult` envelope back. See
[`docs/API.md`](docs/API.md) for the exact response shape.

---

## Using Gemini vision

1. Get an API key from Google AI Studio.
2. Set the backend environment:

   ```dotenv
   AI_PROVIDER=gemini
   GEMINI_API_KEY=your-key-here
   # GEMINI_MODEL=...   # optional override
   ```

3. Send a real screenshot to `POST /api/analysis/screenshot` with
   `provider=gemini` (or leave it off to use the `AI_PROVIDER` default).

## Using OpenAI vision

1. Get an API key from the OpenAI platform.
2. Set the backend environment:

   ```dotenv
   AI_PROVIDER=openai
   OPENAI_API_KEY=your-key-here
   # OPENAI_MODEL=...   # optional override
   ```

3. Send `provider=openai` on the request, or use the default.

---

## Pikafish (real engine) setup

[Pikafish](https://github.com/official-pikafish/Pikafish) is a strong open-source
Xiangqi engine that speaks UCI.

1. Build or download a Pikafish binary for your OS/CPU.
2. Download the matching NNUE weights file if your build requires it.
3. Point the backend at them:

   ```dotenv
   ENGINE_PROVIDER=pikafish
   PIKAFISH_BINARY_PATH=/absolute/path/to/pikafish
   PIKAFISH_NNUE_PATH=/absolute/path/to/pikafish.nnue
   ```

4. Tune with `ENGINE_DEFAULT_DEPTH` and/or `ENGINE_DEFAULT_MOVE_TIME_MS`, or
   pass `engineDepth` / `engineMoveTimeMs` per request.

Engines run in a **warm pool**: up to `ENGINE_POOL_SIZE` (default 2)
persistent Pikafish processes stay alive between requests, so the NNUE net and
hash load once per process instead of per solve. Pool size is also the hard cap
on concurrent searches — extra requests queue, and idle engines shut down after
5 minutes.

> **Note:** the board orientation our FEN builder produces has been verified
> against the real Pikafish binary (known FENs fed to a live process, engine
> output compared to a trusted reference). The FEN spec is documented in
> [`docs/API.md`](docs/API.md).

---

## Troubleshooting

| Symptom                                            | Cause / fix                                                                                                   |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Overlay button never appears                       | Overlay permission denied. Re-trigger `requestOverlayPermission`; grant "Display over other apps" in Settings.|
| Screen-capture consent keeps failing               | Projection permission denied. The system dialog must be accepted each session; `requestScreenCapturePermission` returns `false` if declined. |
| Screenshot is **all black**                        | Target app sets `FLAG_SECURE` (banking, DRM, some games). This is intentional OS protection and cannot be bypassed. Test on a normal app/board. |
| App can't reach backend on the **emulator**        | Use `http://10.0.2.2:3000`, not `localhost`/`127.0.0.1`. The emulator maps `10.0.2.2` to the host machine.    |
| App can't reach backend on a **physical device**   | Use the host's LAN IP (e.g. `http://192.168.1.50:3000`); same Wi-Fi; check firewall.                          |
| Browser/cross-origin call blocked                  | CORS is enabled for all origins in dev. If you locked it down, re-allow your origin or restore dev CORS.       |
| `cleartext` HTTP blocked on device                 | Android blocks plain HTTP by default in release builds; for local dev use a network-security config or HTTPS.  |
| Engine results look wrong / mirrored               | FEN orientation is verified against real Pikafish (see the note above); double-check `sideToMove` and the recognized board in the response `warnings`. |

---

## Privacy & policy notes

- **No permanent screenshot storage by default.** Captured screenshots
  (downscaled JPEGs) live in the app's cache and are sent for analysis; the
  backend does not persist images by default. Storage providers, if enabled,
  are opt-in.
- **API keys live on the backend only.** The mobile app never embeds Gemini /
  OpenAI keys. It only talks to your backend.
- **No raw image logging.** The backend must not log raw screenshot bytes or
  base64 image payloads. Log metadata (size, provider, timing) only.
- **Explicit consent only.** Screen capture always uses Android's official
  `MediaProjection` consent dialog. `FLAG_SECURE` windows are never captured.

---

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — layers, boundaries, data flow.
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) — solve-latency architecture: warm engine pool, caches, image budgets, streaming.
- [`docs/API.md`](docs/API.md) — full HTTP API reference + curl examples.
- [`docs/ANDROID_NATIVE.md`](docs/ANDROID_NATIVE.md) — native components & channels.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — dev workflow, extending providers/engines.
