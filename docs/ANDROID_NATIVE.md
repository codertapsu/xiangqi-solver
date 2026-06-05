# Android Native Layer

The Flutter app drives Android-specific capabilities — screen capture, the
floating overlay, and the foreground service — through native **Kotlin** code,
bridged by Flutter platform channels. This document is the authoritative
contract between the Dart side (`apps/mobile/lib`) and the native side
(`apps/mobile/android`).

---

## Platform channels

| Channel        | Name                                       | Direction          |
| -------------- | ------------------------------------------ | ------------------ |
| MethodChannel  | `com.xiangqisolver/solver/methods`         | Dart → native call |
| EventChannel   | `com.xiangqisolver/solver/events`          | native → Dart stream |

The names must match **exactly** on both sides.

### Methods (`MethodChannel`)

| Method                              | Result    | Behavior                                                                                          |
| ----------------------------------- | --------- | ------------------------------------------------------------------------------------------------ |
| `checkOverlayPermission()`          | `bool`    | Whether "Display over other apps" is granted.                                                    |
| `requestOverlayPermission()`        | `void`    | Opens the system overlay-settings screen.                                                        |
| `requestScreenCapturePermission()`  | `bool`    | Launches the official `MediaProjection` consent dialog; resolves `true` **iff** the user grants. |
| `startSolverMode()`                 | `void`    | Requires overlay **and** projection granted; starts the foreground service + floating overlay.   |
| `stopSolverMode()`                  | `void`    | Stops solver mode (overlay + service).                                                            |
| `isSolverModeRunning()`             | `bool`    | Whether solver mode is currently active.                                                          |
| `captureScreenshot()`               | `String`  | Absolute path to a saved PNG in app cache. Throws `PlatformException` (with a `code`) on failure. |

### Events (`EventChannel`)

Each event is a `Map` with a `"type"` key:

| Event                                                  | Meaning                                                  |
| ------------------------------------------------------ | -------------------------------------------------------- |
| `{ type: "solverModeStarted" }`                        | Foreground service + overlay are up.                     |
| `{ type: "solverModeStopped" }`                        | Solver mode stopped.                                     |
| `{ type: "screenshotCaptured", path, width, height }`  | A frame was captured and saved (`path:String`, `width:int`, `height:int`). |
| `{ type: "screenshotFailed", reason, code }`           | Capture failed (`reason:String`, `code:String`).         |
| `{ type: "permissionDenied", permission }`             | A required permission was denied; `permission:"overlay"|"projection"`. |
| `{ type: "overlayActionAnalyze" }`                     | User tapped "Analyze" on the floating overlay.           |
| `{ type: "overlayActionStop" }`                        | User tapped "Stop" on the floating overlay.              |

---

## Native components

Four native pieces implement the contract above.

### 1. `MainActivity`

- The single Flutter activity host.
- Registers the `MethodChannel` and `EventChannel` handlers.
- Receives results of permission Activities/dialogs (overlay settings,
  MediaProjection consent) and forwards them to the channel results / event
  sink.
- Routes `MethodChannel` calls to the appropriate service/activity and relays
  service callbacks back to Dart as `EventChannel` events.

### 2. `MediaProjectionPermissionActivity`

- A thin, transparent activity launched to request the **official**
  `MediaProjection` consent (`MediaProjectionManager.createScreenCaptureIntent()`).
- Returns the user's decision so `requestScreenCapturePermission()` resolves
  `true` only when granted; emits `permissionDenied{permission:"projection"}`
  on denial.
- Hands the granted projection token to `ScreenCaptureService`.

### 3. `ScreenCaptureService`

- A **foreground service** that holds the `MediaProjection` and an
  `ImageReader`/`VirtualDisplay` to grab frames.
- On Android 14+ it declares the foreground-service type
  **`mediaProjection`** and must post its notification before capture.
- `captureScreenshot()` grabs the latest frame, encodes a PNG into the **app
  cache**, returns the absolute path, and emits
  `screenshotCaptured{path,width,height}`. On failure it emits
  `screenshotFailed{reason,code}` and the method throws a `PlatformException`.

### 4. `OverlayService`

- Draws the floating overlay (the "Analyze"/"Stop" button) on top of other apps
  using `SYSTEM_ALERT_WINDOW` (the `TYPE_APPLICATION_OVERLAY` window type).
- Emits `overlayActionAnalyze` / `overlayActionStop` when the user taps,
  letting Dart orchestrate capture + the backend call without bringing the app
  to the foreground.

---

## Permission & consent flow

```
1. checkOverlayPermission()  -> bool
   if false: requestOverlayPermission()  (opens system settings)
             user grants "Display over other apps"

2. requestScreenCapturePermission()
   -> system MediaProjection consent dialog
   -> resolves true iff granted
      (on denial: event permissionDenied{permission:"projection"})

3. startSolverMode()
   requires overlay AND projection granted
   -> starts ScreenCaptureService (foreground) + OverlayService
   -> event solverModeStarted

4. (user taps overlay) -> event overlayActionAnalyze
   -> Dart calls captureScreenshot()
   -> event screenshotCaptured{path,width,height}
   -> Dart POSTs the PNG to /api/analysis/screenshot

5. stopSolverMode() -> event solverModeStopped
```

If `startSolverMode()` is called without the required grants, the native side
emits the relevant `permissionDenied{permission}` event and does not start.

---

## Android 14+ foreground-service-type notes

- Using `MediaProjection` from a foreground service on **Android 14 (API 34)+**
  requires the service to declare the **`mediaProjection`** foreground-service
  type, and the manifest to hold
  `FOREGROUND_SERVICE_MEDIA_PROJECTION`.
- The foreground notification must be posted **before** capture begins.
- On **Android 13 (API 33)+** the app needs `POST_NOTIFICATIONS` to show the
  mandatory foreground-service notification.
- Required manifest permissions:
  - `SYSTEM_ALERT_WINDOW` — the overlay.
  - `FOREGROUND_SERVICE` — run the capture service in foreground.
  - `FOREGROUND_SERVICE_MEDIA_PROJECTION` — Android 14+ typed service.
  - `POST_NOTIFICATIONS` — Android 13+ notification.

---

## `FLAG_SECURE` behavior

Apps that mark their windows with `FLAG_SECURE` (banking, DRM video, some
games) are **excluded from MediaProjection frames** by the operating system.
Captured frames of those screens come back **black**. This is intentional OS
protection; the solver **cannot and does not** bypass it. Test the app against
ordinary screens and your own analysis boards. See the README's responsible-use
warning.

---

## Limitations

- **One projection session at a time.** The consent is per-session; if the
  system tears down the projection, the app must re-request it.
- **Black frames on secure content** (see `FLAG_SECURE` above) — not a bug.
- **No silent/background capture.** Every capture session is gated behind the
  system consent dialog by design.
- **Cache-only screenshots.** PNGs are written to the app cache and are not
  persisted long-term by default; the OS may reclaim cache space.
- **OEM variance.** Overlay behavior, notification requirements, and
  battery/background restrictions vary by manufacturer and Android version;
  test on target devices.
