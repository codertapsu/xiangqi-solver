import 'dart:io';

import '../../../../core/platform/native_solver_platform.dart';
import '../../../../core/utils/logger.dart';
import 'on_device_engine.dart';
import 'uci_engine_client.dart';

/// Resolves the on-device engine from:
///   - the Pikafish executable shipped as `jniLibs/<abi>/libpikafish.so`,
///     extracted by the OS into the app's native-library dir (read+exec), and
///   - the NNUE net DOWNLOADED at runtime (see EngineNetNotifier), whose path is
///     passed in once the download completes.
///
/// The binary ships in RELEASE now (the app is GPLv3 — see LICENSE-engine); the
/// 50 MB net is fetched at runtime rather than bundled. Returns
/// [UnavailableOnDeviceEngine] off Android, or when the binary or net is missing
/// (e.g. the net hasn't finished downloading).
class OnDeviceEngineResolver {
  OnDeviceEngineResolver(this._native);

  final NativeSolverPlatform _native;
  static const AppLogger _log = AppLogger('OnDeviceEngine');
  static const String _libName = 'libpikafish.so';

  Future<OnDeviceEngine> resolve(String? nnuePath) async {
    final libDir = await _native.nativeLibraryDir();
    if (libDir == null) return const UnavailableOnDeviceEngine();

    final binaryPath = '$libDir/$_libName';
    if (!File(binaryPath).existsSync()) {
      _log.warn('On-device engine binary not found at $binaryPath.');
      return const UnavailableOnDeviceEngine();
    }

    if (nnuePath == null || !File(nnuePath).existsSync()) {
      // A netless engine would just hang on `go`; stay unavailable so the
      // analyzer returns a clean board-only result with a clear warning.
      _log.info('On-device NNUE net not available yet; engine unavailable.');
      return const UnavailableOnDeviceEngine();
    }

    _log.info('On-device engine ready: binary=$binaryPath, nnue=$nnuePath');
    return ProcessOnDeviceEngine(binaryPath: binaryPath, nnuePath: nnuePath);
  }
}
