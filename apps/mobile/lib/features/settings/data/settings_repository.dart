import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../solver/domain/solver_enums.dart';

/// Immutable snapshot of all user-configurable settings.
///
/// API keys deliberately live ONLY on the backend; nothing secret is stored
/// here. [storeScreenshots] defaults to `false` for privacy.
class AppSettings extends Equatable {
  const AppSettings({
    required this.backendUrl,
    required this.aiProvider,
    required this.engineProvider,
    required this.engineDepth,
    required this.engineMoveTimeMs,
    required this.engineMultiPv,
    required this.engineThreads,
    required this.engineHashMb,
    required this.language,
    required this.storeScreenshots,
    required this.mySide,
  });

  final String backendUrl;
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
  final String language;
  final bool storeScreenshots;

  /// The side the user is playing. Sent to the backend as the authoritative
  /// `sideToMove`, so the engine always solves for the correct turn. Only
  /// [SideToMove.red] or [SideToMove.black] are ever stored here.
  final SideToMove mySide;

  /// Zero-config defaults derived from compile-time env (see [AppConstants]).
  factory AppSettings.defaults() => const AppSettings(
    backendUrl: AppConstants.defaultBackendUrl,
    aiProvider: _defaultAi,
    engineProvider: _defaultEngine,
    engineDepth: AppConstants.defaultEngineDepth,
    engineMoveTimeMs: AppConstants.defaultEngineMoveTimeMs,
    engineMultiPv: AppConstants.defaultEngineMultiPv,
    engineThreads: AppConstants.defaultEngineThreads,
    engineHashMb: AppConstants.defaultEngineHashMb,
    language: AppConstants.defaultLanguage,
    storeScreenshots: false,
    mySide: _defaultMySide,
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
    AiProvider? aiProvider,
    EngineProvider? engineProvider,
    int? engineDepth,
    int? engineMoveTimeMs,
    int? engineMultiPv,
    int? engineThreads,
    int? engineHashMb,
    String? language,
    bool? storeScreenshots,
    SideToMove? mySide,
  }) {
    return AppSettings(
      backendUrl: backendUrl ?? this.backendUrl,
      aiProvider: aiProvider ?? this.aiProvider,
      engineProvider: engineProvider ?? this.engineProvider,
      engineDepth: engineDepth ?? this.engineDepth,
      engineMoveTimeMs: engineMoveTimeMs ?? this.engineMoveTimeMs,
      engineMultiPv: engineMultiPv ?? this.engineMultiPv,
      engineThreads: engineThreads ?? this.engineThreads,
      engineHashMb: engineHashMb ?? this.engineHashMb,
      language: language ?? this.language,
      storeScreenshots: storeScreenshots ?? this.storeScreenshots,
      mySide: mySide ?? this.mySide,
    );
  }

  @override
  List<Object?> get props => [
    backendUrl,
    aiProvider,
    engineProvider,
    engineDepth,
    engineMoveTimeMs,
    engineMultiPv,
    engineThreads,
    engineHashMb,
    language,
    storeScreenshots,
    mySide,
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
  static const String _kAiProvider = 'settings.aiProvider';
  static const String _kEngineProvider = 'settings.engineProvider';
  static const String _kEngineDepth = 'settings.engineDepth';
  static const String _kEngineMoveTimeMs = 'settings.engineMoveTimeMs';
  static const String _kEngineMultiPv = 'settings.engineMultiPv';
  static const String _kEngineThreads = 'settings.engineThreads';
  static const String _kEngineHashMb = 'settings.engineHashMb';
  static const String _kLanguage = 'settings.language';
  static const String _kStoreScreenshots = 'settings.storeScreenshots';
  static const String _kMySide = 'settings.mySide';

  /// Loads the persisted settings, merging over [AppSettings.defaults].
  AppSettings load() {
    final defaults = AppSettings.defaults();
    return AppSettings(
      backendUrl: _readString(_kBackendUrl, defaults.backendUrl),
      aiProvider: AiProvider.fromWire(
        _prefs.getString(_kAiProvider) ?? defaults.aiProvider.wireValue,
      ),
      engineProvider: EngineProvider.fromWire(
        _prefs.getString(_kEngineProvider) ??
            defaults.engineProvider.wireValue,
      ),
      engineDepth: _clampInt(
        _prefs.getInt(_kEngineDepth) ?? defaults.engineDepth,
        1,
        30,
      ),
      engineMoveTimeMs: _clampInt(
        _prefs.getInt(_kEngineMoveTimeMs) ?? defaults.engineMoveTimeMs,
        50,
        60000,
      ),
      engineMultiPv: _clampInt(
        _prefs.getInt(_kEngineMultiPv) ?? defaults.engineMultiPv,
        1,
        5,
      ),
      engineThreads: _clampInt(
        _prefs.getInt(_kEngineThreads) ?? defaults.engineThreads,
        1,
        8,
      ),
      engineHashMb: _clampInt(
        _prefs.getInt(_kEngineHashMb) ?? defaults.engineHashMb,
        16,
        1024,
      ),
      language: _readString(_kLanguage, defaults.language),
      storeScreenshots:
          _prefs.getBool(_kStoreScreenshots) ?? defaults.storeScreenshots,
      mySide: _readSide(_prefs.getString(_kMySide), defaults.mySide),
    );
  }

  /// Persists [settings]. Returns the same value for fluent use.
  Future<AppSettings> save(AppSettings settings) async {
    await Future.wait([
      _prefs.setString(_kBackendUrl, settings.backendUrl.trim()),
      _prefs.setString(_kAiProvider, settings.aiProvider.wireValue),
      _prefs.setString(_kEngineProvider, settings.engineProvider.wireValue),
      _prefs.setInt(_kEngineDepth, _clampInt(settings.engineDepth, 1, 30)),
      _prefs.setInt(
        _kEngineMoveTimeMs,
        _clampInt(settings.engineMoveTimeMs, 50, 60000),
      ),
      _prefs.setInt(_kEngineMultiPv, _clampInt(settings.engineMultiPv, 1, 5)),
      _prefs.setInt(_kEngineThreads, _clampInt(settings.engineThreads, 1, 8)),
      _prefs.setInt(_kEngineHashMb, _clampInt(settings.engineHashMb, 16, 1024)),
      _prefs.setString(_kLanguage, settings.language),
      _prefs.setBool(_kStoreScreenshots, settings.storeScreenshots),
      _prefs.setString(_kMySide, settings.mySide.wireValue),
    ]);
    return settings;
  }

  String _readString(String key, String fallback) {
    final value = _prefs.getString(key);
    if (value == null || value.trim().isEmpty) return fallback;
    return value;
  }

  /// Parses a stored side, constraining it to the two playable sides; anything
  /// missing or malformed (incl. "unknown") falls back to [fallback].
  SideToMove _readSide(String? value, SideToMove fallback) {
    final parsed = SideToMove.fromWire(value);
    return parsed == SideToMove.red || parsed == SideToMove.black
        ? parsed
        : fallback;
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}
