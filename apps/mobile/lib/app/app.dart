import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../core/l10n/app_l10n.dart';
import '../core/l10n/locale_providers.dart';
import '../core/platform/app_icon_provider.dart';
import '../features/solver/presentation/providers/solver_providers.dart'
    show nativeSolverProvider;
import 'router.dart';
import 'theme/app_theme.dart';

/// Root application widget: wires theming, localization, and the [GoRouter].
class XiangqiSolverApp extends ConsumerStatefulWidget {
  const XiangqiSolverApp({super.key});

  @override
  ConsumerState<XiangqiSolverApp> createState() => _XiangqiSolverAppState();
}

class _XiangqiSolverAppState extends ConsumerState<XiangqiSolverApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter();

  /// The launcher variant we've already pushed to native this session, so we
  /// only call across the channel when it actually changed.
  String? _appliedIconVariant;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Apply the launcher icon + name variant once at startup (handles a fresh
    // install whose default alias doesn't match the device language, and any
    // change made in a previous session). The toggle here happens BEHIND the app
    // UI, so the user never witnesses it. The real reconciliation after an
    // in-session language change is done in [didChangeAppLifecycleState].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyAppIcon(ref.read(appIconVariantProvider));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Switch the launcher icon + name ONLY as the app leaves the foreground —
    // NEVER while the user is actively using it. Toggling an activity-alias can
    // make a launcher briefly relocate the icon (and a few restart the app);
    // doing it on `paused` means any such reshuffle/restart happens off the
    // app's critical path (the app is already backgrounded), and the icon is
    // already correct the next time the user looks at the home screen. The
    // in-app UI itself flips language instantly (independent of this).
    if (state == AppLifecycleState.paused) {
      _applyAppIcon(ref.read(appIconVariantProvider));
    }
  }

  void _applyAppIcon(String variant) {
    // De-dup in Dart (the native side is also idempotent) so a no-op `paused`
    // never even crosses the method channel.
    if (variant == _appliedIconVariant) return;
    _appliedIconVariant = variant;
    unawaited(
      ref.read(nativeSolverProvider).setAppIcon(variant).catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    // null = follow the device locale (resolved to Vietnamese for unsupported
    // languages by [localeResolutionCallback]); a non-null value is the user's
    // explicit App-language override from Settings.
    final locale = ref.watch(localeProvider);

    // Keep the context-free accessor in sync so the data/network/on-device
    // layers (no BuildContext) produce error text in the active locale.
    AppL10n.current = ref.watch(appLocalizationsProvider);

    // NOTE: the launcher icon + name are NOT switched live here. Changing the App
    // language updates the in-app UI immediately (via `locale` above); the
    // launcher alias is reconciled when the app next goes to the background or
    // launches (see initState / didChangeAppLifecycleState), never mid-use.

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
