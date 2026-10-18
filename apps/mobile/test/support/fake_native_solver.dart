import 'dart:async';

import 'package:xiangqi_solver/core/platform/native_solver_event.dart';
import 'package:xiangqi_solver/core/platform/native_solver_platform.dart';

/// A fake native layer with a controllable event stream that records the sides
/// pushed to the (would-be) overlay toggle and the permission/start calls.
class FakeNativeSolver implements NativeSolverPlatform {
  final StreamController<NativeSolverEvent> _events =
      StreamController<NativeSolverEvent>.broadcast();
  final List<String> sidesPushed = [];

  /// Whether "display over other apps" is granted (flip it to simulate the
  /// user granting it in system settings).
  bool overlayGranted = false;

  /// What the screen-capture consent dialog answers.
  bool captureGranted = false;

  /// Native calls, in order (e.g. `requestOverlayPermission`, `startSolverMode`).
  final List<String> calls = [];

  void emit(NativeSolverEvent event) => _events.add(event);

  @override
  bool get isSupported => true;

  @override
  Stream<NativeSolverEvent> get events => _events.stream;

  @override
  Future<void> setOverlaySide(String side) async => sidesPushed.add(side);

  @override
  Future<void> setAppIcon(String variant) async {}

  @override
  Future<bool> isSolverModeRunning() async => false;

  @override
  Future<bool> checkOverlayPermission() async => overlayGranted;
  @override
  Future<void> requestOverlayPermission() async =>
      calls.add('requestOverlayPermission');
  @override
  Future<bool> requestScreenCapturePermission() async {
    calls.add('requestScreenCapturePermission');
    return captureGranted;
  }
  @override
  Future<void> startSolverMode() async => calls.add('startSolverMode');

  // --- Unused by the current tests: benign defaults. ---
  @override
  Future<void> stopSolverMode() async {}
  @override
  Future<String> captureScreenshot() async => '';
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
  Future<void> dispose() async {}
}
