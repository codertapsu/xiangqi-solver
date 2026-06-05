import 'package:equatable/equatable.dart';

/// Which permission was denied, as reported by the native layer.
enum DeniedPermission {
  overlay('overlay'),
  projection('projection'),
  unknown('unknown');

  const DeniedPermission(this.wireValue);

  final String wireValue;

  static DeniedPermission fromWire(String? value) {
    return DeniedPermission.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => DeniedPermission.unknown,
    );
  }
}

/// Events streamed from native over the EventChannel.
///
/// Each native event is a `Map` with a `type` key; [NativeSolverEvent.fromMap]
/// parses it into one of these strongly-typed variants. Unknown types map to
/// [UnknownEvent] rather than throwing, so a future native addition cannot
/// crash the Dart side.
sealed class NativeSolverEvent extends Equatable {
  const NativeSolverEvent();

  /// Parses a raw event map. Returns [UnknownEvent] for unrecognized shapes.
  factory NativeSolverEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type']?.toString();
    switch (type) {
      case 'solverModeStarted':
        return const SolverModeStartedEvent();
      case 'solverModeStopped':
        return const SolverModeStoppedEvent();
      case 'screenshotCaptured':
        return ScreenshotCapturedEvent(
          path: map['path']?.toString() ?? '',
          width: _asInt(map['width']),
          height: _asInt(map['height']),
        );
      case 'screenshotFailed':
        return ScreenshotFailedEvent(
          reason: map['reason']?.toString() ?? 'Unknown reason',
          code: map['code']?.toString() ?? 'unknown',
        );
      case 'permissionDenied':
        return PermissionDeniedEvent(
          permission: DeniedPermission.fromWire(map['permission']?.toString()),
        );
      case 'overlayActionAnalyze':
        return const OverlayActionAnalyzeEvent();
      case 'overlayActionStop':
        return const OverlayActionStopEvent();
      default:
        return UnknownEvent(type ?? 'null');
    }
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class SolverModeStartedEvent extends NativeSolverEvent {
  const SolverModeStartedEvent();

  @override
  List<Object?> get props => const [];
}

class SolverModeStoppedEvent extends NativeSolverEvent {
  const SolverModeStoppedEvent();

  @override
  List<Object?> get props => const [];
}

class ScreenshotCapturedEvent extends NativeSolverEvent {
  const ScreenshotCapturedEvent({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;

  @override
  List<Object?> get props => [path, width, height];
}

class ScreenshotFailedEvent extends NativeSolverEvent {
  const ScreenshotFailedEvent({required this.reason, required this.code});

  final String reason;
  final String code;

  @override
  List<Object?> get props => [reason, code];
}

class PermissionDeniedEvent extends NativeSolverEvent {
  const PermissionDeniedEvent({required this.permission});

  final DeniedPermission permission;

  @override
  List<Object?> get props => [permission];
}

class OverlayActionAnalyzeEvent extends NativeSolverEvent {
  const OverlayActionAnalyzeEvent();

  @override
  List<Object?> get props => const [];
}

class OverlayActionStopEvent extends NativeSolverEvent {
  const OverlayActionStopEvent();

  @override
  List<Object?> get props => const [];
}

class UnknownEvent extends NativeSolverEvent {
  const UnknownEvent(this.rawType);

  final String rawType;

  @override
  List<Object?> get props => [rawType];
}
