import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';
import '../utils/logger.dart';
import 'native_solver_event.dart';
import 'native_solver_platform.dart';

/// Android implementation backed by a [MethodChannel] (commands) and an
/// [EventChannel] (native -> Dart events).
///
/// The channel names and method/event shapes match the shared platform
/// contract exactly. Method results are mapped to typed exceptions; the event
/// stream is broadcast and lazily parsed into [NativeSolverEvent]s.
class MethodChannelNativeSolver implements NativeSolverPlatform {
  MethodChannelNativeSolver({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methods =
           methodChannel ?? const MethodChannel(AppConstants.methodChannelName),
       _eventChannel =
           eventChannel ?? const EventChannel(AppConstants.eventChannelName);

  final MethodChannel _methods;
  final EventChannel _eventChannel;
  static const AppLogger _log = AppLogger('NativeSolver');

  Stream<NativeSolverEvent>? _events;

  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<NativeSolverEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map<NativeSolverEvent>(_parseEvent)
        .handleError((Object error, StackTrace _) {
          _log.warn('Event stream error: $error');
        })
        .asBroadcastStream();
  }

  NativeSolverEvent _parseEvent(dynamic raw) {
    if (raw is Map) {
      return NativeSolverEvent.fromMap(raw);
    }
    _log.warn('Unexpected event payload: $raw');
    return UnknownEvent(raw.runtimeType.toString());
  }

  @override
  Future<bool> checkOverlayPermission() =>
      _invokeBool('checkOverlayPermission');

  @override
  Future<void> requestOverlayPermission() =>
      _invokeVoid('requestOverlayPermission');

  @override
  Future<bool> requestScreenCapturePermission() =>
      _invokeBool('requestScreenCapturePermission');

  @override
  Future<void> startSolverMode() => _invokeVoid('startSolverMode');

  @override
  Future<void> stopSolverMode() => _invokeVoid('stopSolverMode');

  @override
  Future<bool> isSolverModeRunning() => _invokeBool('isSolverModeRunning');

  @override
  Future<String> captureScreenshot() async {
    try {
      final path = await _methods.invokeMethod<String>('captureScreenshot');
      if (path == null || path.isEmpty) {
        throw const PlatformChannelException(
          'The native layer returned an empty screenshot path.',
          code: 'EMPTY_PATH',
        );
      }
      return path;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _mapMissingPlugin(e);
    }
  }

  @override
  Future<void> updateOverlay({
    required String title,
    String? detail,
    required String kind,
  }) {
    return _invokeVoidArgs('updateOverlay', {
      'title': title,
      'detail': detail,
      'kind': kind,
    });
  }

  @override
  Future<void> startRegionSelection() => _invokeVoid('startRegionSelection');

  @override
  Future<void> clearCaptureRegion() => _invokeVoid('clearCaptureRegion');

  @override
  Future<String?> nativeLibraryDir() async {
    try {
      return await _methods.invokeMethod<String>('nativeLibraryDir');
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _mapMissingPlugin(e);
    }
  }

  @override
  Future<void> setOverlaySide(String side) =>
      _invokeVoidArgs('setOverlaySide', {'side': side});

  @override
  Future<void> dispose() async {
    _events = null;
  }

  // --- helpers ---

  Future<bool> _invokeBool(String method) async {
    try {
      return await _methods.invokeMethod<bool>(method) ?? false;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _mapMissingPlugin(e);
    }
  }

  Future<void> _invokeVoid(String method) async {
    try {
      await _methods.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _mapMissingPlugin(e);
    }
  }

  Future<void> _invokeVoidArgs(String method, Map<String, dynamic> args) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _mapMissingPlugin(e);
    }
  }

  PlatformChannelException _mapPlatformException(PlatformException e) {
    _log.warn('PlatformException ${e.code}: ${e.message}');
    return PlatformChannelException(
      e.message ?? 'A native error occurred.',
      code: e.code,
    );
  }

  PlatformChannelException _mapMissingPlugin(MissingPluginException e) {
    _log.warn('MissingPluginException: ${e.message}');
    return const PlatformChannelException(
      'The native solver plugin is not available on this platform.',
      code: 'MISSING_PLUGIN',
    );
  }
}
