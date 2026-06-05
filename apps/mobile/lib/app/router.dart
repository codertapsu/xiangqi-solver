import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(child: Text('No route for ${state.uri}')),
    ),
  );
}
