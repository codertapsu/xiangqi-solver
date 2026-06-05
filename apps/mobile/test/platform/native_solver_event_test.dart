import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/core/platform/native_solver_event.dart';

void main() {
  group('NativeSolverEvent.fromMap', () {
    test('parses the overlay switch-side action', () {
      final event = NativeSolverEvent.fromMap({'type': 'overlayActionSwitchSide'});
      expect(event, isA<OverlayActionSwitchSideEvent>());
    });

    test('still parses the existing overlay actions', () {
      expect(
        NativeSolverEvent.fromMap({'type': 'overlayActionAnalyze'}),
        isA<OverlayActionAnalyzeEvent>(),
      );
      expect(
        NativeSolverEvent.fromMap({'type': 'overlayActionStop'}),
        isA<OverlayActionStopEvent>(),
      );
    });

    test('maps an unknown type to UnknownEvent (never throws)', () {
      final event = NativeSolverEvent.fromMap({'type': 'somethingNew'});
      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).rawType, 'somethingNew');
    });
  });
}
