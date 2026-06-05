import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/core/constants/app_constants.dart';
import 'package:xiangqi_solver/features/solver/presentation/pages/home_page.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Widget> buildHome() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: HomePage()),
    );
  }

  testWidgets('Home renders core controls and privacy banner', (tester) async {
    await tester.pumpWidget(await buildHome());
    await tester.pump();

    // App title.
    expect(find.text(AppConstants.appName), findsOneWidget);

    // Key sections / actions are present near the top.
    expect(find.text('Solver Mode'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Test Backend Connection'), findsOneWidget);

    // Privacy banner.
    expect(find.text('Privacy & AI use'), findsOneWidget);

    // The mock-test button lives at the bottom of the scroll view.
    final mockTestButton = find.text('Pick image & analyze (mock test)');
    await tester.scrollUntilVisible(
      mockTestButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(mockTestButton, findsOneWidget);
  });

  testWidgets('Backend URL field is seeded with the default URL', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHome());
    await tester.pump();

    // Find the labelled field, then assert its controller holds the default.
    final fieldFinder = find.widgetWithText(TextField, 'Backend URL');
    expect(fieldFinder, findsOneWidget);
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, AppConstants.defaultBackendUrl);
  });

  testWidgets('Stop button is disabled while solver mode is not running', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHome());
    await tester.pump();

    final stopButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Stop'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(stopButton.onPressed, isNull);
  });
}
