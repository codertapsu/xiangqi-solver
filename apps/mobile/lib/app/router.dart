import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../features/admin/presentation/admin_config_page.dart';
import '../features/admin/presentation/admin_grants_page.dart';
import '../features/admin/presentation/admin_installs_page.dart';
import '../features/admin/presentation/admin_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/solver/presentation/pages/home_page.dart';
import '../features/solver/presentation/pages/result_page.dart';

/// Named routes for the app.
abstract final class AppRoutes {
  static const String home = '/';
  static const String result = '/result';
  static const String settings = '/settings';
  static const String history = '/history';
  static const String admin = '/admin';
  static const String adminConfig = '/admin/config';
  static const String adminGrants = '/admin/grants';
  static const String adminInstalls = '/admin/installs';
}

/// Builds the application's [GoRouter].
///
/// Kept as a factory (not a top-level singleton) so tests can build a fresh
/// router and so it composes cleanly with [ProviderScope].
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: AppRoutes.result,
        name: 'result',
        builder: (context, state) => const ResultPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.history,
        name: 'history',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          return HistoryPage(selectedId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.admin,
        name: 'admin',
        builder: (context, state) => const AdminPage(),
      ),
      GoRoute(
        path: AppRoutes.adminConfig,
        name: 'adminConfig',
        builder: (context, state) => const AdminConfigPage(),
      ),
      GoRoute(
        path: AppRoutes.adminGrants,
        name: 'adminGrants',
        builder: (context, state) => const AdminGrantsPage(),
      ),
      GoRoute(
        path: AppRoutes.adminInstalls,
        name: 'adminInstalls',
        builder: (context, state) => const AdminInstallsPage(),
      ),
    ],
    errorBuilder: (context, state) {
      final l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.routeNotFound)),
        body: Center(child: Text(l10n.routeNoRoute(state.uri.toString()))),
      );
    },
  );
}
