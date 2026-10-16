import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/app/router.dart';
import 'package:xiangqi_solver/core/network/api_result.dart';
import 'package:xiangqi_solver/core/network/dio_client.dart';
import 'package:xiangqi_solver/core/platform/native_solver_event.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_api.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_repository.dart';
import 'package:xiangqi_solver/features/solver/presentation/pages/home_page.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../support/fake_native_solver.dart';
import '../support/hint_grant_test_override.dart';
import '../support/remote_config_test_override.dart';

/// Reports a healthy backend with no network, so Home's startup mode-health
/// probe resolves to `ready` (no dialog/snackbar of its own).
class _HealthyRepo extends AnalysisRepository {
  _HealthyRepo() : super(AnalysisApi(DioClient()));

  @override
  Future<ApiResult<HealthStatus>> checkHealth() async => const ApiResult.success(
    HealthStatus(
      status: 'ok',
      timestamp: '',
      uptimeSeconds: 0,
      version: '1.0.0',
      latency: Duration.zero,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<Override>> overrides(FakeNativeSolver native) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      analysisRepositoryProvider.overrideWithValue(_HealthyRepo()),
      nativeSolverProvider.overrideWithValue(native),
      remoteConfigTestOverride,
      hintGrantOverride(),
    ];
  }

  // go_router >= 18 finds its default page type by looking for material_ui's
  // MaterialApp, which this framework-Material app doesn't have, so a plain
  // `builder:` route silently becomes a transition-less NoTransitionPage.
  testWidgets('routes and the error page are framework Material pages', (
    tester,
  ) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(FakeNativeSolver()),
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();

    final homeRoute = ModalRoute.of(tester.element(find.byType(HomePage)));
    expect(homeRoute, isA<MaterialRouteTransitionMixin<Object?>>());

    router.go('/no-such-route');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final notFound = find.text('Not found');
    expect(notFound, findsOneWidget);
    expect(
      ModalRoute.of(tester.element(notFound)),
      isA<MaterialRouteTransitionMixin<Object?>>(),
    );
  });

  // Riverpod 3 pauses a covered widget's `ref.watch` subscriptions (its
  // TickerMode is off while another route is on top). Home's `ref.listen` side
  // effects must NOT pause with them: an overlay capture failing while the user
  // has Settings open still has to surface now, not when Home reappears.
  testWidgets('Home reacts to solver-mode messages while another route covers it', (
    tester,
  ) async {
    final native = FakeNativeSolver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: await overrides(native),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(),
        ),
      ),
    );
    await tester.pump();

    // Cover Home with an opaque route, as Settings or Result would.
    unawaited(
      Navigator.of(tester.element(find.byType(HomePage))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covering route')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('covering route'), findsOneWidget);
    expect(find.byType(HomePage, skipOffstage: true), findsNothing);

    native.emit(const ScreenshotFailedEvent(reason: 'lens cap on', code: 'test'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Screenshot failed: lens cap on'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.text('covering route')),
    );
    // The message was consumed, not left pending for when Home reappears.
    expect(container.read(solverModeProvider).message, isNull);
  });
}
