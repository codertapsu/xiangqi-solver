/// Application-wide constants and zero-config defaults.
///
/// Values are read from the compile-time environment (`--dart-define`) with
/// safe mock defaults so the app runs with ZERO configuration on any host.
library;

class AppConstants {
  const AppConstants._();

  /// Non-localized app name fallback (international brand). The visible title is
  /// localized at runtime via `AppLocalizations.appTitle` (Vietnamese market:
  /// "Quân Sư Cờ Tướng"); this is only the MaterialApp default before the first
  /// localized frame and the value used where no [BuildContext] is available.
  static const String appName = 'Xiangqi Strategist';

  /// Public privacy policy (hosted on the codertapsu Firebase site). Generated
  /// from codertapsu-web/apps.json (slug `xiangqi-solver`).
  static const String privacyPolicyUrl =
      'https://codertapsu-web.web.app/xiangqi-solver/privacy';

  /// Default backend base URL.
  ///
  /// Points at the live backend so an installed release works out of the box.
  /// It's plain HTTP for now (no TLS yet) — the app reaches it via the scoped
  /// cleartext exception in res/xml/network_security_config.xml. Override per
  /// build with `--dart-define=BACKEND_URL=...` or at runtime in Settings; for
  /// local dev against the Android emulator use `http://10.0.2.2:3000`.
  static const String defaultBackendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://103.157.205.175:3000',
  );

  /// Default AI (vision) provider. One of: auto | gemini | openai | mock.
  ///
  /// `auto` OMITS the provider field from requests, so the BACKEND's
  /// `AI_PROVIDER` decides (openai on the deployed server) — this is what lets
  /// the operator A/B switch cloud vision (e.g. to Gemini 3 Flash) for the
  /// whole fleet without an app release. An explicit value still overrides the
  /// server. For offline/local dev against the mock backend, override with
  /// `--dart-define=AI_PROVIDER=mock` or pick "Mock" in Settings → Providers
  /// (the local backend's own zero-config default is mock, so `auto` works
  /// there too).
  static const String defaultAiProvider = String.fromEnvironment(
    'AI_PROVIDER',
    defaultValue: 'auto',
  );

  /// Default engine provider. One of: pikafish | mock. Real by default for the
  /// same reason as [defaultAiProvider]; override with
  /// `--dart-define=ENGINE_PROVIDER=mock` for local mock-backend dev.
  static const String defaultEngineProvider = String.fromEnvironment(
    'ENGINE_PROVIDER',
    defaultValue: 'pikafish',
  );

  /// Default engine mode: cloud (backend) | onDevice (experimental offline).
  static const String defaultEngineMode = String.fromEnvironment(
    'ENGINE_MODE',
    defaultValue: 'cloud',
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

  /// Default move-notation language code (chess notation output, not the UI).
  /// Vietnamese-first (the primary market): 'vi' | 'en' | 'zh'.
  static const String defaultLanguage = 'vi';

  /// Default app UI language: 'vi' (Vietnamese — the primary market, the default),
  /// 'en', or 'system' (follow the device, falling back to Vietnamese). Override
  /// in Settings → Language → App language.
  static const String defaultAppLanguage = 'vi';

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
  static const String configPath = '$apiPrefix/config';
  static const String analyzeBoardPath = '$apiPrefix/analysis/board';
  static const String analyzeScreenshotPath = '$apiPrefix/analysis/screenshot';

  /// Progressive (NDJSON) variant of [analyzeScreenshotPath]: emits the
  /// recognized board as soon as vision finishes, then the full result.
  static const String analyzeScreenshotStreamPath =
      '$apiPrefix/analysis/screenshot/stream';
  static const String analyzeExtractPath = '$apiPrefix/analysis/extract';

  /// Install-grant: starting hint balance for this device on (re)install.
  static const String hintsClaimPath = '$apiPrefix/hints/claim';

  /// Admin API (device-id + shared-secret protected; see AdminApi).
  static const String adminStatusPath = '$apiPrefix/admin/status';
  static const String adminConfigPath = '$apiPrefix/admin/config';
  static const String adminGrantsPath = '$apiPrefix/admin/grants';
  static const String adminInstallsPath = '$apiPrefix/admin/installs';

  /// SharedPreferences key for the stable per-device id (also sent as the
  /// `x-device-id` header). Seeded from a reinstall-stable id at startup.
  static const String deviceIdPrefKey = 'device.id';

  /// Maximum screenshot upload size accepted by the backend (8 MB).
  static const int maxUploadBytes = 8 * 1024 * 1024;
}
