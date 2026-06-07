import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../core/l10n/app_l10n.dart';
import '../core/l10n/locale_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root application widget: wires theming, localization, and the [GoRouter].
class XiangqiSolverApp extends ConsumerStatefulWidget {
  const XiangqiSolverApp({super.key});

  @override
  ConsumerState<XiangqiSolverApp> createState() => _XiangqiSolverAppState();
}

class _XiangqiSolverAppState extends ConsumerState<XiangqiSolverApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // null = follow the device locale (resolved to Vietnamese for unsupported
    // languages by [localeResolutionCallback]); a non-null value is the user's
    // explicit App-language override from Settings.
    final locale = ref.watch(localeProvider);

    // Keep the context-free accessor in sync so the data/network/on-device
    // layers (no BuildContext) produce error text in the active locale.
    AppL10n.current = ref.watch(appLocalizationsProvider);

    return MaterialApp.router(
      // Localized window/title-bar name (Vietnamese: "Quân Sư Cờ Tướng").
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Vietnamese is the primary market: any device language we don't translate
      // falls back to Vietnamese rather than the first arbitrary supported locale.
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (deviceLocale != null &&
            kSupportedLanguageCodes.contains(deviceLocale.languageCode)) {
          return Locale(deviceLocale.languageCode);
        }
        return fallbackLocale;
      },
      routerConfig: _router,
    );
  }
}
