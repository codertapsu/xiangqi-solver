import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/core/platform/native_solver_event.dart';
import 'package:xiangqi_solver/core/platform/native_solver_platform.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

/// A fake native layer with a controllable event stream that records the sides
/// pushed to the (would-be) overlay toggle.
class _FakeNative implements NativeSolverPlatform {
  final StreamController<NativeSolverEvent> _events =
      StreamController<NativeSolverEvent>.broadcast();
  final List<String> sidesPushed = [];

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

  // --- Unused in this test: benign defaults. ---
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

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({ProviderContainer container, _FakeNative native})> boot() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final native = _FakeNative();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        nativeSolverProvider.overrideWithValue(native),
      ],
    );
    addTearDown(container.dispose);
    // Instantiating the notifier subscribes it to the native event stream.
    container.read(solverModeProvider);
    await _settle();
    return (container: container, native: native);
  }

  test('overlay switch-side event flips mySide and echoes it to the overlay', () async {
    final (:container, :native) = await boot();
    expect(container.read(settingsProvider).mySide, SideToMove.red);

    native.emit(const OverlayActionSwitchSideEvent());
    await _settle();

    expect(container.read(settingsProvider).mySide, SideToMove.black);
    expect(native.sidesPushed.last, 'black');

    // Toggling again returns to Red.
    native.emit(const OverlayActionSwitchSideEvent());
    await _settle();

    expect(container.read(settingsProvider).mySide, SideToMove.red);
    expect(native.sidesPushed.last, 'red');
  });

  test('starting solver mode mirrors the current side onto the overlay', () async {
    final (:container, :native) = await boot();
    // Pretend the user already plays Black.
    await container
        .read(settingsProvider.notifier)
        .patch((s) => s.copyWith(mySide: SideToMove.black));

    native.emit(const SolverModeStartedEvent());
    await _settle();

    expect(native.sidesPushed.last, 'black');
  });
}
