import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../solver/domain/solver_enums.dart';

/// Immutable snapshot of all user-configurable settings.
///
/// The two analysis choices are INDEPENDENT:
///  - [aiKeySource]: who pays for board VISION — [AiKeySource.ours] (our key, on
///    the backend, costs hints) or [AiKeySource.own] (the user's key, on-device).
///  - [engineLocation]: where the best-move ENGINE runs — [EngineLocation.cloud]
///    (our backend Pikafish) or [EngineLocation.onDevice] (local Pikafish).
/// Only `own` + `onDevice` is fully offline (no backend, no hints).
class AppSettings extends Equatable {
  const AppSettings({
    required this.backendUrl,
    required this.aiKeySource,
    required this.engineLocation,
    required this.aiProvider,
    required this.engineProvider,
    required this.engineDepth,
    required this.engineMoveTimeMs,
    required this.engineMultiPv,
    required this.engineThreads,
    required this.engineHashMb,
    required this.language,
    required this.appLanguage,
    required this.storeScreenshots,
    required this.mySide,
    required this.onDeviceVisionModel,
  });

  final String backendUrl;

  /// Whose OpenAI key does vision (ours = backend/hints; own = on-device).
  final AiKeySource aiKeySource;

  /// Where the best-move engine runs (cloud backend vs on-device Pikafish).
  final EngineLocation engineLocation;

  final AiProvider aiProvider;
  final EngineProvider engineProvider;
  final int engineDepth;
  final int engineMoveTimeMs;

  /// How many top moves to request from the engine (Pikafish MultiPV, 1..5).
  final int engineMultiPv;

  /// Pikafish search worker threads (1..8). Ignored by the mock engine.
  final int engineThreads;

  /// Pikafish transposition-table size in MB (16..1024). Ignored by the mock engine.
  final int engineHashMb;

  /// Move-notation language code ('en' | 'vi' | 'zh') for chess-notation output.
  final String language;

  /// App UI language: 'system' (follow the device), 'vi', or 'en'. See
  /// [AppConstants.defaultAppLanguage] and the locale providers.
  final String appLanguage;

  final bool storeScreenshots;

  /// The side the user is playing. Sent to the backend as the authoritative
  /// `sideToMove`, so the engine always solves for the correct turn. Only
  /// [SideToMove.red] or [SideToMove.black] are ever stored here.
  final SideToMove mySide;

  /// User OVERRIDE for the OpenAI vision model on the On-device (BYO-key) path.
  /// Empty means "use the backend default" ([RemoteConfig.onDeviceVisionModel],
  /// default gpt-5.4). On-device vision is OpenAI-only. `gpt-4o-mini` is too weak
  /// to read the small piece glyphs reliably (it misplaces advisors/elephants).
  /// Resolve the effective model with [onDeviceVisionModelOr].
  final String onDeviceVisionModel;

  /// Empty default = follow the backend's `RemoteConfig.onDeviceVisionModel`.
  static const String _defaultOnDeviceVisionModel = '';

  /// True when ANY part of the analysis runs on our backend (vision with our
  /// key, OR the cloud engine). Drives hint metering + whether the hint UI shows.
  bool get usesBackend =>
      aiKeySource == AiKeySource.ours || engineLocation == EngineLocation.cloud;

  /// True only for `own` key + `onDevice` engine — no backend, no hints.
  bool get isFullyLocal => !usesBackend;

  /// The effective on-device vision model: the user's override if they set one,
  /// otherwise the backend-provided [fallback] (`RemoteConfig.onDeviceVisionModel`).
  String onDeviceVisionModelOr(String fallback) {
    final m = onDeviceVisionModel.trim();
    return m.isEmpty ? fallback : m;
  }

  /// Zero-config defaults derived from compile-time env (see [AppConstants]).
  factory AppSettings.defaults() => const AppSettings(
    backendUrl: AppConstants.defaultBackendUrl,
    aiKeySource: AiKeySource.ours,
    engineLocation: EngineLocation.cloud,
    aiProvider: _defaultAi,
    engineProvider: _defaultEngine,
    engineDepth: AppConstants.defaultEngineDepth,
    engineMoveTimeMs: AppConstants.defaultEngineMoveTimeMs,
    engineMultiPv: AppConstants.defaultEngineMultiPv,
    engineThreads: AppConstants.defaultEngineThreads,
    engineHashMb: AppConstants.defaultEngineHashMb,
    language: AppConstants.defaultLanguage,
    appLanguage: AppConstants.defaultAppLanguage,
    storeScreenshots: false,
    mySide: _defaultMySide,
    onDeviceVisionModel: _defaultOnDeviceVisionModel,
  );

  static const SideToMove _defaultMySide =
      AppConstants.defaultMySide == 'black'
      ? SideToMove.black
      : SideToMove.red;

  static const AiProvider _defaultAi =
      AppConstants.defaultAiProvider == 'gemini'
      ? AiProvider.gemini
      : AppConstants.defaultAiProvider == 'openai'
      ? AiProvider.openai
      : AiProvider.mock;

  static const EngineProvider _defaultEngine =
      AppConstants.defaultEngineProvider == 'pikafish'
      ? EngineProvider.pikafish
      : EngineProvider.mock;

  AppSettings copyWith({
    String? backendUrl,
    AiKeySource? aiKeySource,
    EngineLocation? engineLocation,
    AiProvider? aiProvider,
    EngineProvider? engineProvider,
    int? engineDepth,
    int? engineMoveTimeMs,
    int? engineMultiPv,
    int? engineThreads,
    int? engineHashMb,
    String? language,
    String? appLanguage,
    bool? storeScreenshots,
    SideToMove? mySide,
    String? onDeviceVisionModel,
  }) {
    return AppSettings(
      backendUrl: backendUrl ?? this.backendUrl,
      aiKeySource: aiKeySource ?? this.aiKeySource,
      engineLocation: engineLocation ?? this.engineLocation,
      aiProvider: aiProvider ?? this.aiProvider,
      engineProvider: engineProvider ?? this.engineProvider,
      engineDepth: engineDepth ?? this.engineDepth,
      engineMoveTimeMs: engineMoveTimeMs ?? this.engineMoveTimeMs,
      engineMultiPv: engineMultiPv ?? this.engineMultiPv,
      engineThreads: engineThreads ?? this.engineThreads,
      engineHashMb: engineHashMb ?? this.engineHashMb,
      language: language ?? this.language,
      appLanguage: appLanguage ?? this.appLanguage,
      storeScreenshots: storeScreenshots ?? this.storeScreenshots,
      mySide: mySide ?? this.mySide,
      onDeviceVisionModel: onDeviceVisionModel ?? this.onDeviceVisionModel,
    );
  }

  @override
  List<Object?> get props => [
    backendUrl,
    aiKeySource,
    engineLocation,
    aiProvider,
    engineProvider,
    engineDepth,
    engineMoveTimeMs,
    engineMultiPv,
    engineThreads,
    engineHashMb,
    language,
    appLanguage,
    storeScreenshots,
    mySide,
    onDeviceVisionModel,
  ];
}

/// Persists [AppSettings] to [SharedPreferences] under stable keys.
///
/// All reads are defensive: a missing or malformed value falls back to the
/// corresponding default, so a corrupt store never breaks startup.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _kBackendUrl = 'settings.backendUrl';
  static const String _kAiKeySource = 'settings.aiKeySource';
  static const String _kEngineLocation = 'settings.engineLocation';
  // Legacy single-mode key (pre-2x2). Read only for one-time migration.
  static const String _kLegacyEngineMode = 'settings.engineMode';
  static const String _kAiProvider = 'settings.aiProvider';
  static const String _kEngineProvider = 'settings.engineProvider';
  static const String _kEngineDepth = 'settings.engineDepth';
  static const String _kEngineMoveTimeMs = 'settings.engineMoveTimeMs';
  static const String _kEngineMultiPv = 'settings.engineMultiPv';
  static const String _kEngineThreads = 'settings.engineThreads';
  static const String _kEngineHashMb = 'settings.engineHashMb';
  static const String _kLanguage = 'settings.language';
  static const String _kAppLanguage = 'settings.appLanguage';
  static const String _kStoreScreenshots = 'settings.storeScreenshots';
  static const String _kMySide = 'settings.mySide';
  static const String _kOnDeviceVisionModel = 'settings.onDeviceVisionModel';

  /// Loads the persisted settings, merging over [AppSettings.defaults].
  AppSettings load() {
    final defaults = AppSettings.defaults();

    // Migrate the pre-2x2 single 'engineMode' setting if the new keys are unset.
    // Old 'onDevice' meant BYO-key vision + local engine → own + onDevice.
    final legacy = _prefs.getString(_kLegacyEngineMode);
    final migratedKey = legacy == 'onDevice' ? AiKeySource.own : AiKeySource.ours;
    final migratedEngine =
        legacy == 'onDevice' ? EngineLocation.onDevice : EngineLocation.cloud;

    return AppSettings(
      backendUrl: _readString(_kBackendUrl, defaults.backendUrl),
      aiKeySource: AiKeySource.fromWire(
        _prefs.getString(_kAiKeySource) ?? migratedKey.wireValue,
      ),
      engineLocation: EngineLocation.fromWire(
        _prefs.getString(_kEngineLocation) ?? migratedEngine.wireValue,
      ),
      aiProvider: AiProvider.fromWire(
        _prefs.getString(_kAiProvider) ?? defaults.aiProvider.wireValue,
      ),
      engineProvider: EngineProvider.fromWire(
        _prefs.getString(_kEngineProvider) ?? defaults.engineProvider.wireValue,
      ),
      engineDepth: _clampInt(_prefs.getInt(_kEngineDepth) ?? defaults.engineDepth, 1, 30),
      engineMoveTimeMs: _clampInt(
        _prefs.getInt(_kEngineMoveTimeMs) ?? defaults.engineMoveTimeMs,
        50,
        60000,
      ),
      engineMultiPv: _clampInt(_prefs.getInt(_kEngineMultiPv) ?? defaults.engineMultiPv, 1, 5),
      engineThreads: _clampInt(_prefs.getInt(_kEngineThreads) ?? defaults.engineThreads, 1, 8),
      engineHashMb: _clampInt(_prefs.getInt(_kEngineHashMb) ?? defaults.engineHashMb, 16, 1024),
      language: _readString(_kLanguage, defaults.language),
      appLanguage: _readAppLanguage(defaults.appLanguage),
      storeScreenshots: _prefs.getBool(_kStoreScreenshots) ?? defaults.storeScreenshots,
      mySide: _readSide(_prefs.getString(_kMySide), defaults.mySide),
      onDeviceVisionModel: _readString(_kOnDeviceVisionModel, defaults.onDeviceVisionModel),
    );
  }

  /// Persists [settings]. Returns the same value for fluent use.
  Future<AppSettings> save(AppSettings settings) async {
    await Future.wait([
      _prefs.setString(_kBackendUrl, settings.backendUrl.trim()),
      _prefs.setString(_kAiKeySource, settings.aiKeySource.wireValue),
      _prefs.setString(_kEngineLocation, settings.engineLocation.wireValue),
      _prefs.setString(_kAiProvider, settings.aiProvider.wireValue),
      _prefs.setString(_kEngineProvider, settings.engineProvider.wireValue),
      _prefs.setInt(_kEngineDepth, _clampInt(settings.engineDepth, 1, 30)),
      _prefs.setInt(_kEngineMoveTimeMs, _clampInt(settings.engineMoveTimeMs, 50, 60000)),
      _prefs.setInt(_kEngineMultiPv, _clampInt(settings.engineMultiPv, 1, 5)),
      _prefs.setInt(_kEngineThreads, _clampInt(settings.engineThreads, 1, 8)),
      _prefs.setInt(_kEngineHashMb, _clampInt(settings.engineHashMb, 16, 1024)),
      _prefs.setString(_kLanguage, settings.language),
      _prefs.setString(_kAppLanguage, settings.appLanguage),
      _prefs.setBool(_kStoreScreenshots, settings.storeScreenshots),
      _prefs.setString(_kMySide, settings.mySide.wireValue),
      // Stored as-is (empty = "follow the backend default"); resolved at use.
      _prefs.setString(_kOnDeviceVisionModel, settings.onDeviceVisionModel.trim()),
    ]);
    return settings;
  }

  String _readString(String key, String fallback) {
    final value = _prefs.getString(key);
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  /// Reads the app UI language, constraining it to a supported value; anything
  /// missing or unknown falls back to [fallback] (default 'system').
  String _readAppLanguage(String fallback) {
    final value = _prefs.getString(_kAppLanguage);
    return (value == 'system' || value == 'vi' || value == 'en') ? value! : fallback;
  }

  /// Parses a stored side, constraining it to the two playable sides; anything
  /// missing or malformed (incl. "unknown") falls back to [fallback].
  SideToMove _readSide(String? value, SideToMove fallback) {
    final parsed = SideToMove.fromWire(value);
    return parsed == SideToMove.red || parsed == SideToMove.black ? parsed : fallback;
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
