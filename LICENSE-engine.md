# On-device engine license (Pikafish — GPLv3)

The mobile app's optional **On-device** mode bundles the **Pikafish** Xiangqi
engine binary (`apps/mobile/android/app/src/main/jniLibs/<abi>/libpikafish.so`)
and runs it on the device to compute the best move.

Pikafish is licensed under the **GNU General Public License, version 3 (GPLv3)**.
Because this app **distributes the Pikafish binary**, the app as a whole is
offered under the **GPLv3** as well.

## Source code

- **Pikafish** (the engine): <https://github.com/official-pikafish/Pikafish>
  — the complete corresponding source for the bundled binary, including the
  build instructions used to produce the Android `.so` (NDK, `ARCH=armv8`,
  `COMP=ndk`). See `apps/mobile/assets/engine/README.md` for the exact build.
- **This app**: its source is available under the GPLv3. **Written offer:** for
  three years, we will provide the complete corresponding source of the app and
  the engine on request to the contact email in the app's privacy policy, on a
  physical medium, for no more than our cost of distribution.

## NNUE network (not distributed)

The Pikafish **NNUE evaluation network** is **not** bundled with the app. It is
**downloaded at runtime** from the official Pikafish Networks releases
(`https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue`),
the same way the desktop engine obtains it. The app therefore does not
distribute the network.

## In-app notice

This notice is surfaced in the app under **Settings → Open-source licenses**
(the OS-standard license page), registered at startup via `LicenseRegistry`.

A full copy of the GPLv3 text is available at
<https://www.gnu.org/licenses/gpl-3.0.txt>.
