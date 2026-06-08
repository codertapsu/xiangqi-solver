import 'native_solver_event.dart';
import 'native_solver_platform.dart';

/// No-op implementation used on non-Android hosts (and in tests).
///
/// Every call resolves to a benign default so the UI runs end-to-end on a
/// desktop or in CI without a device. [isSupported] is `false` so the UI can
/// disable native-only affordances and explain why.
class NoopNativeSolver implements NativeSolverPlatform {
  const NoopNativeSolver();

  @override
  bool get isSupported => false;

  @override
  Stream<NativeSolverEvent> get events => const Stream<NativeSolverEvent>.empty();

  @override
  Future<bool> checkOverlayPermission() async => false;

  @override
  Future<void> requestOverlayPermission() async {}

  @override
  Future<bool> requestScreenCapturePermission() async => false;

  @override
  Future<void> startSolverMode() async {}

  @override
  Future<void> stopSolverMode() async {}

  @override
  Future<bool> isSolverModeRunning() async => false;

  @override
  Future<String> captureScreenshot() async {
    throw UnsupportedError(
      'Screen capture is only available on Android devices.',
    );
  }

  @override
  Future<void> updateOverlay({
    required String title,
    String? detail,
    required String kind,
  }) async {}

  @override
  Future<void> startRegionSelection() async {}

  @override
  Future<void> clearCaptureRegion() async {}

  @override
  Future<String?> nativeLibraryDir() async => null;

  @override
  Future<void> setOverlaySide(String side) async {}

  @override
  Future<void> setAppIcon(String variant) async {}

  @override
  Future<void> dispose() async {}
}
