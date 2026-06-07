import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../../features/solver/presentation/providers/solver_providers.dart'
    show settingsProvider;

/// Language codes the app UI is translated into. A device locale outside this
/// set falls back to [fallbackLocale] (Vietnamese — the primary market).
const Set<String> kSupportedLanguageCodes = {'vi', 'en'};

/// Locale used when the device language isn't one we translate.
const Locale fallbackLocale = Locale('vi');

/// Resolves the EFFECTIVE app locale from the user's `appLanguage` setting and
/// the current [deviceLocale]. 'system' follows the device when supported, else
/// Vietnamese. Kept as a free function so the context-free
/// [appLocalizationsProvider] and the `MaterialApp` resolution agree.
Locale resolveAppLocale(String appLanguage, Locale deviceLocale) {
  switch (appLanguage) {
    case 'vi':
      return const Locale('vi');
    case 'en':
      return const Locale('en');
    default: // 'system'
      return kSupportedLanguageCodes.contains(deviceLocale.languageCode)
          ? Locale(deviceLocale.languageCode)
          : fallbackLocale;
  }
}

/// The explicit locale to hand `MaterialApp` (`null` = follow the device, where
/// the app's `localeResolutionCallback` applies the Vietnamese fallback).
final localeProvider = Provider<Locale?>((ref) {
  final lang = ref.watch(settingsProvider.select((s) => s.appLanguage));
  switch (lang) {
    case 'vi':
      return const Locale('vi');
    case 'en':
      return const Locale('en');
    default:
      return null; // system — resolved by the MaterialApp callback
  }
});

/// Context-free [AppLocalizations] for notifiers/services that produce
/// user-facing text without a `BuildContext`. Widgets should prefer
/// `AppLocalizations.of(context)`; this resolves the same locale so both agree.
///
/// Rebuilds when the user changes `appLanguage`. It reads the device locale once
/// (a system locale change typically rebuilds the whole app anyway).
final appLocalizationsProvider = Provider<AppLocalizations>((ref) {
  final lang = ref.watch(settingsProvider.select((s) => s.appLanguage));
  final device = PlatformDispatcher.instance.locale;
  return lookupAppLocalizations(resolveAppLocale(lang, device));
});
