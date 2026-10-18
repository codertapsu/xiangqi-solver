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
  static const String historyEntryPattern = '/history/:id';

  /// One saved analysis, reopened on the Result screen.
  static String historyEntry(String id) => '/history/${Uri.encodeComponent(id)}';
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
        pageBuilder: (context, state) => _page(state, const HomePage()),
      ),
      GoRoute(
        path: AppRoutes.result,
        name: 'result',
        pageBuilder: (context, state) => _page(state, const ResultPage()),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) => _page(state, const SettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.history,
        name: 'history',
        pageBuilder: (context, state) {
          final id = state.uri.queryParameters['id'];
          return _page(state, HistoryPage(selectedId: id));
        },
      ),
      GoRoute(
        path: AppRoutes.historyEntryPattern,
        name: 'historyEntry',
        pageBuilder: (context, state) =>
            _page(state, ResultPage(historyId: state.pathParameters['id'])),
      ),
      GoRoute(
        path: AppRoutes.admin,
        name: 'admin',
        pageBuilder: (context, state) => _page(state, const AdminPage()),
      ),
      GoRoute(
        path: AppRoutes.adminConfig,
        name: 'adminConfig',
        pageBuilder: (context, state) => _page(state, const AdminConfigPage()),
      ),
      GoRoute(
        path: AppRoutes.adminGrants,
        name: 'adminGrants',
        pageBuilder: (context, state) => _page(state, const AdminGrantsPage()),
      ),
      GoRoute(
        path: AppRoutes.adminInstalls,
        name: 'adminInstalls',
        pageBuilder: (context, state) => _page(state, const AdminInstallsPage()),
      ),
    ],
    errorPageBuilder: (context, state) {
      final l10n = AppLocalizations.of(context);
      return _page(
        state,
        Scaffold(
          appBar: AppBar(title: Text(l10n.routeNotFound)),
          body: Center(child: Text(l10n.routeNoRoute(state.uri.toString()))),
        ),
      );
    },
  );
}

/// Wraps a screen in a framework [MaterialPage].
///
/// go_router >= 18 picks its default page type by looking for `material_ui`'s
/// `MaterialApp` above the router. This app is built on the framework's
/// `package:flutter/material.dart`, whose `MaterialApp` is a different class,
/// so that lookup fails and a plain `builder:` route falls back to a
/// `NoTransitionPage` — no Material slide/zoom and no predictive-back
/// animation. Building the page here keeps them. The arguments mirror what
/// go_router passes to its own Material page builder.
///
/// Drop this once the app migrates to `package:material_ui` (then go_router's
/// detection succeeds and plain `builder:` routes get Material pages again).
Page<void> _page(GoRouterState state, Widget child) => MaterialPage<void>(
  key: state.pageKey,
  name: state.name ?? state.path,
  arguments: <String, String>{...state.pathParameters, ...state.uri.queryParameters},
  restorationId: state.pageKey.value,
  child: child,
);
