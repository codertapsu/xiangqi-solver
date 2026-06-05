# On-device engine assets

The experimental **On-device (Offline)** mode runs Pikafish directly on the
phone. Two large binaries live here / next door and are **gitignored** — drop
them in locally before building if you want the offline engine to compute moves.

> ⚠️ **The NNUE net MUST match the exact Pikafish version the binary was built
> from.** The release `pikafish.nnue` and the `master-net` are *different*
> architectures; a mismatched net loads-then-fails with
> `The network file … was not loaded successfully` / `… specify the full path …`
> and the engine exits on `go`. Always pair the net with the binary's source.

## The two files

- `pikafish.nnue` — the NNUE network (~48 MB / 50,760,458 bytes for the current
  `master` build; sha256 `a2f41d4d…`). Get it with `make net` (or the URL
  below) **from the same source checkout** you built the `.so` from:

  ```sh
  # from the Pikafish/src checkout that built libpikafish.so:
  make net   # downloads the net matching THIS source → src/pikafish.nnue
  cp src/pikafish.nnue <repo>/apps/mobile/assets/engine/pikafish.nnue
  ```
  Direct URL (master-net): https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue

  If you change the net, update `_expectedNnueBytes` in
  `lib/.../ondevice/on_device_engine_resolver.dart` to the new exact size (it's
  the cache key that forces a re-copy on upgrade).

- `android/app/src/main/jniLibs/arm64-v8a/libpikafish.so` — the engine
  executable (gitignored). Build it **from the same source** as the net:

  ```sh
  make -j8 build ARCH=armv8 COMP=ndk KERNEL=Linux OS=Android   # PIE
  llvm-strip -o libpikafish.so pikafish
  ```

  Sanity-check the pair on a host before shipping (build a host binary from the
  same source and confirm it prints `NNUE evaluation using …` for this net).

Without these files the app still works: on-device mode recognizes the board
(using your own OpenAI key) but reports the move wasn't computed, and you can
switch to Cloud mode in Settings. See `docs/ON_DEVICE_ENGINE.md`.
