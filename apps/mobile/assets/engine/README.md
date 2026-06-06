# On-device engine (Pikafish)

The **On-device** mode runs Pikafish on the phone. It has two parts:

1. **The engine binary** — `libpikafish.so`. It SHIPS in the app (release
   included) at `android/app/src/main/jniLibs/<abi>/libpikafish.so`, because
   Android only allows executing native code extracted from the APK's `lib/`
   into `nativeLibraryDir`; you cannot download + exec a binary on Android 10+.
   Pikafish is **GPLv3**, so the app is GPLv3 too — see `LICENSE-engine.md`.

2. **The NNUE net** (`pikafish.nnue`, ~50 MB) — **downloaded at runtime**, not
   bundled. `EngineNetNotifier` fetches it from the URL in the backend's
   `GET /api/config` (`ONDEVICE_NET_URL`, default the official **master-net**)
   into app storage, with progress shown in Settings. `OnDeviceEngineResolver`
   points Pikafish's `EvalFile` at it. Downloading (rather than bundling) keeps
   the 50 MB out of the APK and avoids distributing the network.

   The net MUST match the binary's architecture; `make net` during the build
   fetches exactly the master-net the source expects, so the runtime master-net
   download matches a binary built from the current source. If they ever drift,
   the engine rejects the net and on-device mode hides itself (the analyzer
   returns a board-only result with a warning).

## Build the binary (the part that ships)

```sh
# from the Pikafish/src checkout, Android NDK in PATH:
make -j8 build ARCH=armv8 COMP=ndk KERNEL=Linux OS=Android   # PIE
llvm-strip -o libpikafish.so pikafish
cp libpikafish.so <repo>/apps/mobile/android/app/src/main/jniLibs/arm64-v8a/libpikafish.so
```

`build.gradle.kts` uses `packaging { jniLibs { useLegacyPackaging = true } }` so
the `.so` is extracted to `nativeLibraryDir` (the only exec-allowed location).

## Notes
- `*.nnue` is gitignored (downloaded at runtime; never committed/bundled).
- `ONDEVICE_NET_BYTES` in the backend config is the expected net size; the app
  reuses an on-disk net only when its size matches (so a net update re-downloads).
