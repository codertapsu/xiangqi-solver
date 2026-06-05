# On-Device Pikafish & Backendless Architecture — Feasibility Report

> Status: **analysis only, nothing implemented.** This evaluates packaging the
> Pikafish engine into the Flutter Android app and moving AI vision off the
> backend (the "no backend at all" idea). Sources: the Pikafish repo at
> `…/Pikafish` (`git describe` → `Pikafish-2026-01-02-134-gfd168f68`) and the
> prebuilt `Pikafish.2026-01-02/` package.

## TL;DR

| Question | Verdict |
|---|---|
| On-device **engine** (Pikafish on Android) | ✅ **Feasible** — Pikafish has official NDK support. |
| Ship the **prebuilt** Android binary as-is | ⚠️ **Probably works** via the jniLibs `lib*.so` trick; recompiling PIE with the NDK is the robust path. |
| Move **AI vision** (OpenAI/Gemini) into the app | ❌ **Not recommended** — embeds extractable API keys → cost-abuse risk. |
| **Fully backendless** | ⚠️ Possible but impractical (needs an on-device board-detection ML model). |
| **Recommended** | On-device engine **+ a thin AI-proxy backend** (vision only). |

---

## 1. Running the prebuilt binary on Android

The prebuilt Android binaries are:

```
Pikafish.2026-01-02/Android/pikafish-armv8          ELF 64-bit aarch64, statically linked, ET_EXEC, ~1.7 MB
Pikafish.2026-01-02/Android/pikafish-armv8-dotprod  ELF 64-bit aarch64, statically linked, ET_EXEC, ~1.7 MB
```

(`armv8` = baseline arm64-v8a; `armv8-dotprod` = arm64-v8a with the dot-product
NEON extension for faster NNUE eval on Cortex-A76+.)

Two real Android constraints:

1. **W^X / SELinux — you cannot `exec()` a file in the app's data dir.** Since
   API 29 the OS refuses to execute files written to `filesDir`/`cacheDir`.
   **Workaround (the accepted one):** ship the binary inside the APK as
   `android/app/src/main/jniLibs/arm64-v8a/libpikafish.so`. The installer
   extracts it to the app's **nativeLibraryDir**, which is read+execute but not
   writable — `Process.start()` from there is allowed. (Requires
   `android:extractNativeLibs="true"`.) Many chess apps ship engines exactly
   this way.

2. **PIE.** Both prebuilt binaries are **ET_EXEC** (non-PIE). *Correction to a
   common claim:* a **statically-linked ET_EXEC is not subject to ASLR
   load-failure* — the kernel maps it at its fixed addresses and simply doesn't
   randomize it; the dynamic linker (which enforces PIE) isn't involved for a
   static binary. So the prebuilt static binaries will **likely run** via the
   jniLibs trick. The residual risk is that some hardened Android builds reject
   non-PIE executables; the clean fix is to **recompile PIE with the NDK** (§2),
   which the build system already supports.

**Verdict:** try the prebuilt `.so` first; if a device refuses it, recompile.

---

## 2. Compiling Pikafish with the Android NDK (robust path)

`src/Makefile` has first-class NDK support:

```makefile
# To cross-compile for Android, use NDK version r27c or later.
ifeq ($(COMP),ndk)
    CXX=aarch64-linux-android29-clang++   # for arch=armv8
```

```bash
# arm64-v8a, PIE, with dot-product:
make -C src COMP=ndk ARCH=armv8-dotprod EXTRA_CXXFLAGS="-fPIE" EXTRA_LDFLAGS="-pie" -j
```

~10 min for a clean build. Output → copy as
`jniLibs/arm64-v8a/libpikafish.so`. Drive it over UCI from Dart with
`Process.start()` (same command sequence as our backend
`pikafish-engine.service.ts`), or compile as a JNI lib and call via a platform
channel / `dart:ffi`.

---

## 3. The NNUE network (~51 MB)

`Pikafish.2026-01-02/pikafish.nnue` is **51 MB, uncompressed**. Options:

- **Bundle as a Flutter asset** → +51 MB APK; copy to a readable dir on first
  run and point `EvalFile` at it (or set the engine's `cwd` to that dir).
- **Download on first run** from a CDN → small APK, but the first analysis waits
  on a 51 MB download.
- **Hybrid:** ship in assets, fall back to download.

The engine looks for `pikafish.nnue` in its working directory by default, or set
`setoption name EvalFile value <abs-path>` (the backend already does this).

---

## 4. Moving AI vision into the app — the key blocker

Embedding the OpenAI/Gemini call in Flutter means **embedding the API key in the
app**, which is:

- **Extractable** — `strings`/decompilation finds keys even when obfuscated.
- **Interceptable** — a proxy/rooted device captures the request.
- **Abusable** — a leaked vision key can run up large bills quickly.

So **"no backend at all" is not safe for vision.** Practical alternatives:

1. **Thin AI-proxy backend (recommended):** the app sends the screenshot to a
   tiny `/api/analysis/extract` endpoint that returns *only* the board pieces;
   the engine runs **on-device**. Keys stay server-side; cost is one cheap
   vision call per analysis, zero per engine search.
2. **On-device board-detection ML** (TFLite/ONNX): truly offline, but a 2–3
   month modeling effort with new failure modes (lighting/angle).
3. **BYO-key**: poor UX; still exposed at runtime. Not recommended.

---

## 4a. Product direction (captured for the future "offline" mode)

The intended UX when on-device mode ships (not built yet):

- Present it as a **user-friendly named mode** (e.g. **"Offline / On-device"** or
  **"Pro (local engine)"**) rather than exposing "Pikafish/jniLibs".
- In that mode the user **brings their own OpenAI API key**, entered in Settings
  and stored only on-device; the **app calls the OpenAI API directly** with that
  key (no backend in the loop). This sidesteps *our* key-exposure/cost risk by
  moving the cost and the key to the user — acceptable for a BYO-key power mode,
  unlike shipping *our* key in the binary.
- The engine then runs locally, so this mode needs **no backend at all**.
- Implementation notes for later: add an `EngineMode`/provider switch (cloud
  backend vs on-device), a secure key field (e.g. `flutter_secure_storage`), a
  direct OpenAI vision client in Dart, and the local UCI engine wrapper from §6.

## 5. Licensing (must-read before distribution)

- **Pikafish is GPLv3** (`Copying.txt`). Bundling the engine makes the app a
  covered work: you must **offer the full app source under GPLv3**. (GPLv3 apps
  are allowed on both Google Play and the App Store — e.g. VLC — but the source
  obligation stands.)
- **NNUE weights are non-commercial by default** (`NNUE-License.md`): "No
  commercial use without permission." Distributing on a commercial channel
  (Play Store) requires **explicit permission** from the Pikafish authors, or
  using a CC0-licensed net if one applies to your file. **Verify this before
  shipping.**

---

## 6. Recommendation

**On-device engine + thin AI-proxy backend.**

```
Flutter app ── local Pikafish (jniLibs lib*.so, UCI over Process.start)
            │      └─ pikafish.nnue (asset/cache)
            └── POST /api/analysis/extract → thin backend → OpenAI/Gemini (keys server-side)
```

- Engine analysis becomes **free + offline** (no per-analysis API cost).
- Vision keys stay **off-device**.
- Effort: ~**2 weeks** for one developer (NDK build, jniLibs, a Dart UCI client,
  NNUE packaging, refactor the backend to a vision-only endpoint, multi-device
  testing).

### Migration sketch (when we choose to do it)

1. ~~Add `/api/analysis/extract` (vision only)~~ — **done.** Returns the
   recognized board (`ExtractionResult`) with no engine analysis; AI key stays
   server-side. Dart client ready (`AnalysisApi.extractBoard` → `BoardState`).
   See [API.md](API.md#post-apianalysisextract).
2. ~~Feature-flagged **"On-device" mode** skeleton~~ — **done.** A
   `EngineMode` setting (Cloud / On-device) in Settings, a secure **BYO OpenAI
   key** field (`flutter_secure_storage` via `SecureKeyStore`), and the engine
   seam (`OnDeviceEngine` + `UnavailableOnDeviceEngine` stub) wired through
   `OnDeviceAnalyzer`. Selecting On-device routes analysis locally and reports a
   clear "engine not bundled yet" failure — the UX is honest and the seam is in
   place. Files: `lib/core/security/secure_key_store.dart`,
   `lib/features/solver/data/ondevice/`.
3. ~~A Dart OpenAI vision client (BYO key, port of the backend
   `openai.provider`)~~ — **done.** `DirectOpenAiVisionClient` (same strict
   prompt + `detail:"high"` + JSON parsing) wired through `OnDeviceAnalyzer`.
   On-device mode now recognizes the board with the user's key and returns it
   (no move yet). File:
   `lib/features/solver/data/ondevice/direct_openai_vision.dart`.
4. ~~Implement `OnDeviceEngine` with a bundled Pikafish (NDK/jniLibs over
   UCI)~~ — **done (pending on-device verification).**
   - **Binary:** cross-compiled a **PIE aarch64** Pikafish on the macOS host with
     NDK 29 — `make -j8 build ARCH=armv8 COMP=ndk KERNEL=Linux OS=Android`
     (`KERNEL=Linux` skips the host's Darwin-only flags; `OS=Android` adds
     `-fPIE -pie`), then `llvm-strip`. Output → `android/app/src/main/jniLibs/
     arm64-v8a/libpikafish.so` (gitignored; ET_DYN/PIE, ~1.27 MB).
   - **UCI driver:** `uci_engine_client.dart` (`UciEngineClient`) — a faithful
     port of `pikafish-engine.service.ts`: `Process.start` (no shell, cwd = the
     binary's dir), `uci`→`uciok`, set `EvalFile`/`Threads`/`Hash`/`MultiPV`
     before `isready`, then `ucinewgame`/`position fen`/`go depth`, parse
     `info`/`bestmove` incl. MultiPV; `quit`+kill in `finally`. Backed by
     `ProcessOnDeviceEngine`. Host-tested against a fake UCI shell script.
   - **Packaging:** native libs are extracted to the exec-allowed
     `nativeLibraryDir` via `packaging { jniLibs { useLegacyPackaging = true } }`
     in `app/build.gradle.kts` (the modern replacement for
     `android:extractNativeLibs="true"`, which AGP now rejects in the manifest).
     A `nativeLibraryDir` MethodChannel method (MainActivity →
     `applicationInfo.nativeLibraryDir`) hands Dart the path.
5. ~~Dart port of board repair/normalize/FEN + move notation to build the full
   `AnalysisResult` locally~~ — **done (pending on-device verification).**
   `local/local_fen.dart`, `local/local_uci.dart`, `local/board_repair.dart`,
   `local/local_notation.dart` (all faithful ports, unit-tested against the
   backend's expected outputs — e.g. start-position FEN and `炮二平五`/`C2=5`).
   `OnDeviceAnalyzer` now runs vision → repair → engine → **localized**
   `BestMove` (+ MultiPV candidates) entirely on-device. The NNUE ships as a
   gitignored Flutter asset (`assets/engine/pikafish.nnue`) and
   `OnDeviceEngineResolver` copies it to app storage on first use.

### 6. Real-device testing — three issues found & fixed

The PIE binary **`exec()`s** fine from `nativeLibraryDir` (the riskiest unknown
— resolved). On-device testing then surfaced three concrete issues, each fixed:

1. **Blind timeouts.** The UCI client only watched stdout for `bestmove`, so any
   engine that started then died just hit a 20 s timeout with no detail. Now it
   captures **stderr + the process exit code** and reports `ENGINE_EXITED (code
   N): <engine's last words>` (surfaced into the result warnings). This is what
   made issues 2–3 diagnosable at all. (Also fixed a self-inflicted stall: never
   `flush()` stdin while a prior flush is pending — batch one write+flush/phase.)
2. **Vision model too weak.** On-device used `gpt-4o-mini`, which misreads the
   piece glyphs → illegal boards (`Unsupported position … advisor(s) on invalid
   positions`). Cloud used `gpt-5.4`. Added an **On-device "Vision model"
   setting** (`AppSettings.onDeviceVisionModel`, default `gpt-4o`); set it to the
   model your Cloud backend uses for parity. The analyzer now also turns an
   "illegal position" rejection into a friendly recapture/stronger-model hint.
3. **NNUE/binary version mismatch (the real engine blocker).** `libpikafish.so`
   was built from the Pikafish source **HEAD** (NNUE struct `Network`, expects
   the **master-net**, 50.76 MB), but we bundled the **January release** net
   (53.2 MB, `Networks`-era). The engine opens the file, can't parse the
   wrong-architecture net, and exits on `go` (`The network file … was not loaded
   successfully`). Proven by building a host binary from the same source and
   reproducing both outcomes. **The net MUST match the exact source the binary
   was built from** — fixed by bundling the matching master-net. The resolver
   keys its on-disk cache on the net's **exact size** so a device holding the
   stale net re-installs the correct one. See `assets/engine/README.md`.

Until a clean board → move is confirmed end-to-end, On-device mode degrades
honestly (recognizes the board, explains why no move, points to Cloud mode).

### Risks

Subprocess lifecycle (avoid zombies), NNUE not found, non-PIE rejection on
hardened devices (recompile PIE), GPLv3 source obligation, NNUE commercial
permission. All are manageable; none are blockers for the engine.
