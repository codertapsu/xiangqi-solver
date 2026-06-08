import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/solver/presentation/providers/solver_providers.dart'
    show settingsProvider;
import '../l10n/locale_providers.dart' show resolveAppLocale;
import '../remote_config/remote_config_provider.dart';

/// The launcher icon + name variant to display: `'vi'` or `'en'`.
///
/// The backend can force it via `RemoteConfig.appIconVariant` (`'vi'`/`'en'`);
/// the default `'auto'` follows the in-app **App-language** setting (which itself
/// resolves the device locale → Vietnamese fallback). So the launcher name+icon
/// track the in-app language regardless of the phone's system language.
///
/// The actual switch happens via `NativeSolverPlatform.setAppIcon` (activity-
/// alias), applied by the app root on startup and whenever this value changes.
final appIconVariantProvider = Provider<String>((ref) {
  final override = ref.watch(
    remoteConfigProvider.select((c) => c.appIconVariant),
  );
  if (override == 'vi' || override == 'en') return override;
  final appLanguage = ref.watch(settingsProvider.select((s) => s.appLanguage));
  final device = PlatformDispatcher.instance.locale;
  return resolveAppLocale(appLanguage, device).languageCode; // 'vi' | 'en'
});
