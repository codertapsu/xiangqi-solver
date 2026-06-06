import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/remote_config/remote_config_provider.dart';
import '../../../../core/utils/logger.dart';
import 'solver_providers.dart' show nativeSolverProvider;

/// State of the on-device engine's NNUE net (the binary ships in the APK; the
/// 50 MB net is downloaded at runtime).
sealed class EngineNetState extends Equatable {
  const EngineNetState();
  @override
  List<Object?> get props => const [];
}

/// On-device isn't available here (off Android, the engine binary is missing, or
/// disabled by remote config). The On-device option should be hidden.
class EngineNetUnsupported extends EngineNetState {
  const EngineNetUnsupported();
}

/// Not started yet.
class EngineNetIdle extends EngineNetState {
  const EngineNetIdle();
}

/// Downloading; [progress] is 0..1 (or null when the total is unknown).
class EngineNetDownloading extends EngineNetState {
  const EngineNetDownloading(this.progress);
  final double? progress;
  @override
  List<Object?> get props => [progress];
}

/// Net is on disk and ready; the engine can run.
class EngineNetReady extends EngineNetState {
  const EngineNetReady(this.path);
  final String path;
  @override
  List<Object?> get props => [path];
}

/// Download failed; [message] explains why. The On-device option should be
/// hidden (with the message), and [EngineNetNotifier.retry] can re-attempt.
class EngineNetFailed extends EngineNetState {
  const EngineNetFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

/// Downloads + caches the Pikafish NNUE net for on-device mode. Auto-starts in
/// the background (if on-device is enabled and supported here), verifies the
/// download is complete, and exposes progress for the Settings UI.
class EngineNetNotifier extends StateNotifier<EngineNetState> {
  EngineNetNotifier(this._ref) : super(const EngineNetIdle()) {
    unawaited(_init());
  }

  final Ref _ref;
  Dio? _dio;
  CancelToken? _cancel;
  static const String _fileName = 'pikafish.nnue';
  static const AppLogger _log = AppLogger('EngineNet');

  Future<void> _init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      state = const EngineNetUnsupported();
      return;
    }
    if (!_ref.read(remoteConfigProvider).onDeviceEnabled) {
      state = const EngineNetUnsupported();
      return;
    }
    // The engine binary must be present (it ships in jniLibs → nativeLibraryDir).
    final libDir = await _ref.read(nativeSolverProvider).nativeLibraryDir();
    if (libDir == null || !File('$libDir/libpikafish.so').existsSync()) {
      state = const EngineNetUnsupported();
      return;
    }
    await ensureDownloaded();
  }

  Future<String> _netPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// Ensure the net is downloaded. Idempotent + safe to call repeatedly; reuses
  /// an on-disk copy that matches the expected size, else downloads it.
  Future<void> ensureDownloaded() async {
    final cfg = _ref.read(remoteConfigProvider);
    final path = await _netPath();
    final file = File(path);

    if (file.existsSync() && file.lengthSync() == cfg.onDeviceNetBytes) {
      if (mounted) state = EngineNetReady(path);
      return;
    }

    if (mounted) state = const EngineNetDownloading(null);
    final tmp = '$path.download';
    _dio ??= Dio();
    _cancel = CancelToken();
    try {
      await _dio!.download(
        cfg.onDeviceNetUrl,
        tmp,
        cancelToken: _cancel,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          final denom = total > 0 ? total : cfg.onDeviceNetBytes;
          state = EngineNetDownloading(denom > 0 ? (received / denom).clamp(0.0, 1.0) : null);
        },
      );
      final tmpFile = File(tmp);
      final size = tmpFile.lengthSync();
      // Sanity: a complete net is tens of MB. Reject an obviously short/HTML body.
      if (size < 1024 * 1024) {
        await tmpFile.delete();
        throw StateError('downloaded net is only $size bytes');
      }
      if (file.existsSync()) await file.delete();
      await tmpFile.rename(path);
      _log.info('On-device net ready ($size bytes).');
      if (mounted) state = EngineNetReady(path);
    } catch (e) {
      _log.warn('Net download failed: $e');
      try {
        final t = File(tmp);
        if (t.existsSync()) await t.delete();
      } catch (_) {}
      if (mounted) {
        state = EngineNetFailed('Could not download the on-device engine. $e');
      }
    }
  }

  /// Re-attempt after a failure.
  Future<void> retry() {
    state = const EngineNetIdle();
    return ensureDownloaded();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}

final engineNetProvider = StateNotifierProvider<EngineNetNotifier, EngineNetState>((ref) {
  return EngineNetNotifier(ref);
});
