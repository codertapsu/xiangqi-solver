import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/core/constants/app_constants.dart';
import 'package:xiangqi_solver/core/network/api_result.dart';
import 'package:xiangqi_solver/core/network/dio_client.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_api.dart';
import 'package:xiangqi_solver/features/solver/data/analysis_repository.dart';
import 'package:xiangqi_solver/features/solver/presentation/pages/home_page.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import 'support/fake_native_solver.dart';
import 'support/hint_grant_test_override.dart';
import 'support/remote_config_test_override.dart';

/// A repository that reports a healthy backend with no network, so the home
/// page's startup mode-health probe resolves to `ready` (no dialog/snackbar).
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

  late SharedPreferences prefs;

  /// Home in a bare MaterialApp. [firstRun] leaves the welcome sheet unseen.
  Future<Widget> buildHome({
    Override? remoteConfig,
    FakeNativeSolver? native,
    bool firstRun = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (!firstRun) 'settings.onboardingSeen': true,
    });
    prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        analysisRepositoryProvider.overrideWithValue(_HealthyRepo()),
        remoteConfig ?? remoteConfigTestOverride,
        hintGrantOverride(),
        if (native != null) nativeSolverProvider.overrideWithValue(native),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(),
      ),
    );
  }

  testWidgets('Home leads with Solver Mode, then the screenshot action and privacy note', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHome());
    await tester.pump();

    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('Solver Mode'), findsOneWidget);
    expect(find.text('Start Solver Mode'), findsOneWidget);
    // One toggling action: no Stop while it isn't running.
    expect(find.text('Stop Solver Mode'), findsNothing);
    expect(find.text('Analyze a screenshot'), findsOneWidget);
    // The Backend card is hidden by default (a remote-config UI flag).
    expect(find.text('Test connection'), findsNothing);

    final privacy = find.textContaining('sent to OpenAI', findRichText: true);
    await tester.scrollUntilVisible(
      privacy,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(privacy, findsOneWidget);
  });

  testWidgets('Home lays out at 2x text on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(await buildHome(remoteConfig: remoteConfigUiVisibleTestOverride));
    await tester.pump();
    expect(MediaQuery.of(tester.element(find.byType(HomePage))).textScaler.scale(10), 20);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Backend URL field is seeded with the default URL', (tester) async {
    // The Backend card is gated behind a remote-config flag — reveal it here.
    await tester.pumpWidget(
      await buildHome(remoteConfig: remoteConfigUiVisibleTestOverride),
    );
    await tester.pump();

    final fieldFinder = find.widgetWithText(TextField, 'Backend URL');
    await tester.scrollUntilVisible(
      fieldFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, AppConstants.defaultBackendUrl);
  });

  testWidgets('iOS replaces Solver Mode with the share-in hero', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(await buildHome());
      await tester.pump();

      // Solver Mode (overlay + capture) is Android-only — hidden on iOS.
      expect(find.text('Solver Mode'), findsNothing);
      expect(find.text('Start Solver Mode'), findsNothing);
      expect(find.text('Analyze a board photo'), findsOneWidget);
      expect(find.text('Choose a photo'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android shows Solver Mode and not the share-in hero', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(await buildHome());
      await tester.pump();

      expect(find.text('Solver Mode'), findsOneWidget);
      expect(find.text('Analyze a board photo'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('first run shows the welcome sheet once, with the privacy disclosure', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHome(firstRun: true));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Xiangqi Strategist'), findsOneWidget);
    expect(find.text('Privacy & AI'), findsOneWidget);
    await tester.ensureVisible(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Xiangqi Strategist'), findsNothing);
    expect(prefs.getBool('settings.onboardingSeen'), isTrue);
  });

  testWidgets('Start explains the permissions, then resumes after the overlay grant', (
    tester,
  ) async {
    final native = FakeNativeSolver();
    await tester.pumpWidget(await buildHome(native: native));
    await tester.pump();

    // "Not now" backs out without touching any permission.
    await tester.tap(find.text('Start Solver Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Solver Mode needs two permissions'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(native.calls, isEmpty);

    // "Continue" sends the user to the overlay setting…
    await tester.tap(find.text('Start Solver Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(native.calls, ['requestOverlayPermission']);

    // …and coming back with it granted carries on to screen-capture consent
    // without a second tap on Start.
    native.overlayGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(native.calls, ['requestOverlayPermission', 'requestScreenCapturePermission']);
  });
}
