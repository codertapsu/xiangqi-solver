import 'native_solver_event.dart';

/// Abstraction over the native Android solver integration.
///
/// Implemented by [MethodChannelNativeSolver] on Android and
/// [NoopNativeSolver] everywhere else. Programming to this interface keeps the
/// rest of the app platform-agnostic and trivially testable (inject a fake).
///
/// All methods may throw [PlatformChannelException] on failure; callers should
/// surface a clear message rather than swallowing errors.
abstract interface class NativeSolverPlatform {
  /// `true` only when running on real Android with the native plugin wired up.
  bool get isSupported;

  /// Broadcast stream of native events. Safe to listen to even when
  /// unsupported (it simply never emits).
  Stream<NativeSolverEvent> get events;

  /// Returns whether the "draw over other apps" permission is granted.
  Future<bool> checkOverlayPermission();

  /// Opens the system overlay-settings screen. Resolves once launched.
  Future<void> requestOverlayPermission();

  /// Launches the official MediaProjection consent dialog.
  /// Resolves `true` iff the user grants screen-capture permission.
  Future<bool> requestScreenCapturePermission();

  /// Starts the foreground service + floating overlay. Requires overlay and
  /// projection permissions to have been granted first.
  Future<void> startSolverMode();

  /// Stops the foreground service and removes the overlay.
  Future<void> stopSolverMode();

  /// Returns whether solver mode is currently running.
  Future<bool> isSolverModeRunning();

  /// Captures a screenshot and returns the absolute path to a PNG in app
  /// cache. Throws [PlatformChannelException] on failure (e.g. FLAG_SECURE).
  Future<String> captureScreenshot();

  /// Updates the floating overlay's result panel so the user can see the
  /// outcome without leaving the other app. [kind] is one of
  /// `loading` | `result` | `error`.
  Future<void> updateOverlay({
    required String title,
    String? detail,
    required String kind,
  });

  /// Opens the resizable focus-area selector over the screen (Solver Mode must
  /// be running). The chosen box is remembered and future captures crop to it.
  Future<void> startRegionSelection();

  /// Clears any focus area so captures use the full screen again.
  Future<void> clearCaptureRegion();

  /// Releases any resources (e.g. the event subscription). Idempotent.
  Future<void> dispose();
}
