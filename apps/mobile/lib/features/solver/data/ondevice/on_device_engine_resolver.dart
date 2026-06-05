import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../../../core/platform/native_solver_platform.dart';
import '../../../../core/utils/logger.dart';
import 'on_device_engine.dart';
import 'uci_engine_client.dart';

/// Resolves the bundled on-device engine:
///   - the Pikafish executable shipped as `jniLibs/<abi>/libpikafish.so`,
///     extracted by the OS into the app's native-library dir (exec-allowed);
///   - the NNUE network, copied once from a bundled asset into app storage.
///
/// Returns [UnavailableOnDeviceEngine] when either is missing (e.g. off Android,
/// or the NNUE asset wasn't bundled).
class OnDeviceEngineResolver {
  OnDeviceEngineResolver(this._native);

  final NativeSolverPlatform _native;
  static const AppLogger _log = AppLogger('OnDeviceEngine');

  static const String _libName = 'libpikafish.so';
  static const String _nnueAsset = 'assets/engine/pikafish.nnue';
  static const String _nnueFileName = 'pikafish.nnue';

  /// EXACT byte size of the bundled `pikafish.nnue` — the master-net that
  /// matches the architecture our `libpikafish.so` was built for. Used as the
  /// cache key: we reuse the on-disk copy ONLY when its size matches this, which
  /// also forces a re-copy after an engine/net upgrade (otherwise a stale,
  /// version-mismatched net would be served and the engine would reject it).
  /// MUST be updated together with the bundled net (see assets/engine/README.md).
  static const int _expectedNnueBytes = 50760458;

  Future<OnDeviceEngine> resolve() async {
    final libDir = await _native.nativeLibraryDir();
    if (libDir == null) return const UnavailableOnDeviceEngine();

    final binaryPath = '$libDir/$_libName';
    if (!File(binaryPath).existsSync()) {
      _log.warn('On-device engine binary not found at $binaryPath.');
      return const UnavailableOnDeviceEngine();
    }

    final nnuePath = await _ensureNnue();
    if (nnuePath == null) {
      // A netless engine would just hang on `go`; stay unavailable so the
      // analyzer returns a clean board-only result with a clear warning.
      _log.warn('On-device engine NNUE could not be installed; engine unavailable.');
      return const UnavailableOnDeviceEngine();
    }
    _log.info('On-device engine ready: binary=$binaryPath, nnue=$nnuePath');
    return ProcessOnDeviceEngine(binaryPath: binaryPath, nnuePath: nnuePath);
  }

  /// Installs the NNUE from the bundled asset into app storage on first use.
  /// Reuses the on-disk copy only on an EXACT size match (so a stale net from a
  /// previous app version is replaced, not served). Writes to a temp file and
  /// renames (atomic) with a post-write size check, so a crash or short write
  /// can't leave a truncated net behind. Returns the path, or null on failure.
  Future<String?> _ensureNnue() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_nnueFileName');
      if (file.existsSync() && file.lengthSync() == _expectedNnueBytes) {
        return file.path;
      }

      final data = await rootBundle.load(_nnueAsset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      if (tmp.lengthSync() != bytes.length) {
        await tmp.delete();
        throw StateError('NNUE copy is ${tmp.lengthSync()} of ${bytes.length} bytes.');
      }
      if (file.existsSync()) await file.delete();
      await tmp.rename(file.path);
      _log.info('Installed NNUE (${file.lengthSync()} bytes) at ${file.path}.');
      return file.path;
    } catch (e) {
      _log.warn('NNUE install failed: $e');
      return null;
    }
  }
}
