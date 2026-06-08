import 'package:equatable/equatable.dart';

/// Server-driven feature flags + tunables (from `GET /api/config`). The app
/// caches the last good value and falls back to [defaults] when offline, so it
/// always has a usable config. Change behavior from the SERVER, not a release.
class RemoteConfig extends Equatable {
  const RemoteConfig({
    required this.rewardedAds,
    required this.bannerAds,
    required this.appOpenAds,
    required this.useRealAds,
    required this.freeHintsOnInstall,
    required this.ownKeyHintDivisor,
    required this.onDeviceEnabled,
    required this.onDeviceNetUrl,
    required this.onDeviceNetBytes,
    required this.onDeviceVisionModel,
    required this.showBackendSection,
    required this.showProvidersSection,
    required this.showEngineTuning,
    required this.showVisionModel,
    required this.showLicenses,
    required this.showDeviceId,
  });

  /// Whether to OFFER rewarded ads (a capped loss-leader) — default off.
  final bool rewardedAds;

  /// Whether to show banner ads (the primary format) — default on.
  final bool bannerAds;

  /// Whether to show app-open ads — default off.
  final bool appOpenAds;

  /// Whether to use the REAL ad unit ids (vs Google's test units) — default off.
  final bool useRealAds;

  /// Free hints granted once on first install.
  final int freeHintsOnInstall;

  /// With the user's OWN OpenAI key: 1 hint is charged per this many analyses.
  final int ownKeyHintDivisor;

  /// Whether on-device Pikafish is offered at all.
  final bool onDeviceEnabled;

  /// Where to download the NNUE net (the engine binary ships in the APK).
  final String onDeviceNetUrl;

  /// Expected net size in bytes (used to verify a complete download).
  final int onDeviceNetBytes;

  /// Default OpenAI model for on-device (BYO-key) board reading, unless the user
  /// overrides it in Settings. On-device vision is OpenAI-only.
  final String onDeviceVisionModel;

  /// Whether the "Backend" URL / connection-test section is shown.
  final bool showBackendSection;

  /// Whether the AI/engine "Providers" dropdowns section is shown.
  final bool showProvidersSection;

  /// Whether the "Engine tuning" sliders section is shown.
  final bool showEngineTuning;

  /// Whether the on-device "Vision model" field is shown.
  final bool showVisionModel;

  /// Whether the "Open-source licenses" entry (GPLv3 notice) is shown.
  final bool showLicenses;

  /// Whether the "Device ID" tile (shared to receive a Hint Grant) is shown.
  final bool showDeviceId;

  static const RemoteConfig defaults = RemoteConfig(
    rewardedAds: false,
    bannerAds: true,
    appOpenAds: false,
    useRealAds: true,
    freeHintsOnInstall: 10,
    ownKeyHintDivisor: 3,
    onDeviceEnabled: true,
    onDeviceNetUrl:
        'https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue',
    onDeviceNetBytes: 50760458,
    onDeviceVisionModel: 'gpt-5.4',
    // Optional settings sections are HIDDEN by default; the server reveals them.
    showBackendSection: false,
    showProvidersSection: false,
    showEngineTuning: false,
    showVisionModel: false,
    showLicenses: false,
    showDeviceId: false,
  );

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    final ads = (json['ads'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hints = (json['hints'] as Map?)?.cast<String, dynamic>() ?? const {};
    final od = (json['onDevice'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ui = (json['ui'] as Map?)?.cast<String, dynamic>() ?? const {};
    return RemoteConfig(
      rewardedAds: ads['rewarded'] as bool? ?? defaults.rewardedAds,
      bannerAds: ads['banner'] as bool? ?? defaults.bannerAds,
      appOpenAds: ads['appOpen'] as bool? ?? defaults.appOpenAds,
      useRealAds: ads['useReal'] as bool? ?? defaults.useRealAds,
      freeHintsOnInstall:
          (hints['freeOnInstall'] as num?)?.toInt() ?? defaults.freeHintsOnInstall,
      ownKeyHintDivisor:
          (hints['ownKeyDivisor'] as num?)?.toInt() ?? defaults.ownKeyHintDivisor,
      onDeviceEnabled: od['enabled'] as bool? ?? defaults.onDeviceEnabled,
      onDeviceNetUrl: od['netUrl'] as String? ?? defaults.onDeviceNetUrl,
      onDeviceNetBytes: (od['netBytes'] as num?)?.toInt() ?? defaults.onDeviceNetBytes,
      onDeviceVisionModel: od['visionModel'] as String? ?? defaults.onDeviceVisionModel,
      showBackendSection: ui['backend'] as bool? ?? defaults.showBackendSection,
      showProvidersSection: ui['providers'] as bool? ?? defaults.showProvidersSection,
      showEngineTuning: ui['engineTuning'] as bool? ?? defaults.showEngineTuning,
      showVisionModel: ui['visionModel'] as bool? ?? defaults.showVisionModel,
      showLicenses: ui['licenses'] as bool? ?? defaults.showLicenses,
      showDeviceId: ui['deviceId'] as bool? ?? defaults.showDeviceId,
    );
  }

  Map<String, dynamic> toJson() => {
    'ads': {
      'rewarded': rewardedAds,
      'banner': bannerAds,
      'appOpen': appOpenAds,
      'useReal': useRealAds,
    },
    'hints': {'freeOnInstall': freeHintsOnInstall, 'ownKeyDivisor': ownKeyHintDivisor},
    'onDevice': {
      'enabled': onDeviceEnabled,
      'netUrl': onDeviceNetUrl,
      'netBytes': onDeviceNetBytes,
      'visionModel': onDeviceVisionModel,
    },
    'ui': {
      'backend': showBackendSection,
      'providers': showProvidersSection,
      'engineTuning': showEngineTuning,
      'visionModel': showVisionModel,
      'licenses': showLicenses,
      'deviceId': showDeviceId,
    },
  };

  RemoteConfig copyWith({
    bool? rewardedAds,
    bool? bannerAds,
    bool? appOpenAds,
    bool? useRealAds,
    int? freeHintsOnInstall,
    int? ownKeyHintDivisor,
    bool? onDeviceEnabled,
    String? onDeviceNetUrl,
    int? onDeviceNetBytes,
    String? onDeviceVisionModel,
    bool? showBackendSection,
    bool? showProvidersSection,
    bool? showEngineTuning,
    bool? showVisionModel,
    bool? showLicenses,
    bool? showDeviceId,
  }) {
    return RemoteConfig(
      rewardedAds: rewardedAds ?? this.rewardedAds,
      bannerAds: bannerAds ?? this.bannerAds,
      appOpenAds: appOpenAds ?? this.appOpenAds,
      useRealAds: useRealAds ?? this.useRealAds,
      freeHintsOnInstall: freeHintsOnInstall ?? this.freeHintsOnInstall,
      ownKeyHintDivisor: ownKeyHintDivisor ?? this.ownKeyHintDivisor,
      onDeviceEnabled: onDeviceEnabled ?? this.onDeviceEnabled,
      onDeviceNetUrl: onDeviceNetUrl ?? this.onDeviceNetUrl,
      onDeviceNetBytes: onDeviceNetBytes ?? this.onDeviceNetBytes,
      onDeviceVisionModel: onDeviceVisionModel ?? this.onDeviceVisionModel,
      showBackendSection: showBackendSection ?? this.showBackendSection,
      showProvidersSection: showProvidersSection ?? this.showProvidersSection,
      showEngineTuning: showEngineTuning ?? this.showEngineTuning,
      showVisionModel: showVisionModel ?? this.showVisionModel,
      showLicenses: showLicenses ?? this.showLicenses,
      showDeviceId: showDeviceId ?? this.showDeviceId,
    );
  }

  @override
  List<Object?> get props => [
    rewardedAds,
    bannerAds,
    appOpenAds,
    useRealAds,
    freeHintsOnInstall,
    ownKeyHintDivisor,
    onDeviceEnabled,
    onDeviceNetUrl,
    onDeviceNetBytes,
    onDeviceVisionModel,
    showBackendSection,
    showProvidersSection,
    showEngineTuning,
    showVisionModel,
    showLicenses,
    showDeviceId,
  ];
}
