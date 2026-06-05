/// Application-wide constants and zero-config defaults.
///
/// Values are read from the compile-time environment (`--dart-define`) with
/// safe mock defaults so the app runs with ZERO configuration on any host.
library;

class AppConstants {
  const AppConstants._();

  /// Human-readable app name (also the Home title).
  static const String appName = 'Xiangqi Solver';

  /// Default backend base URL.
  ///
  /// `10.0.2.2` is the host loopback alias from the Android emulator, so this
  /// works out of the box against a backend listening on the dev machine.
  static const String defaultBackendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Default AI (vision) provider. One of: gemini | openai | mock.
  static const String defaultAiProvider = String.fromEnvironment(
    'AI_PROVIDER',
    defaultValue: 'mock',
  );

  /// Default engine provider. One of: pikafish | mock.
  static const String defaultEngineProvider = String.fromEnvironment(
    'ENGINE_PROVIDER',
    defaultValue: 'mock',
  );

  /// Default engine search depth (1..30).
  static const int defaultEngineDepth = 12;

  /// Default engine move time budget in milliseconds (50..60000).
  static const int defaultEngineMoveTimeMs = 1500;

  /// Default number of top moves to request (Pikafish MultiPV, 1..5).
  static const int defaultEngineMultiPv = 1;

  /// Default Pikafish search threads (1..8 in the UI).
  static const int defaultEngineThreads = 1;

  /// Default Pikafish transposition-table size in MB (16..1024 in the UI).
  static const int defaultEngineHashMb = 128;

  /// Default UI language code.
  static const String defaultLanguage = 'en';

  /// Default side the user plays (whose move it is when solving): red | black.
  static const String defaultMySide = String.fromEnvironment(
    'MY_SIDE',
    defaultValue: 'red',
  );

  /// Network timeouts.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 60);
  static const Duration sendTimeout = Duration(seconds: 60);

  // ---- Platform channel names (MUST match native exactly) ----
  static const String methodChannelName = 'com.xiangqisolver/solver/methods';
  static const String eventChannelName = 'com.xiangqisolver/solver/events';

  // ---- API routing ----
  static const String apiPrefix = '/api';
  static const String healthPath = '$apiPrefix/health';
  static const String analyzeBoardPath = '$apiPrefix/analysis/board';
  static const String analyzeScreenshotPath = '$apiPrefix/analysis/screenshot';

  /// Maximum screenshot upload size accepted by the backend (8 MB).
  static const int maxUploadBytes = 8 * 1024 * 1024;
}
