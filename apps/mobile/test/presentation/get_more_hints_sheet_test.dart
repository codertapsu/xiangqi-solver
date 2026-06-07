import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/app/theme/app_theme.dart';
import 'package:xiangqi_solver/features/monetization/presentation/get_more_hints_sheet.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';

import '../support/hint_grant_test_override.dart';
import '../support/remote_config_test_override.dart';

void main() {
  // Regression: the sheet must open cleanly under the REAL app theme (which makes
  // FilledButton full-width via minimumSize: Size.fromHeight(48)), on a narrow
  // screen, at a large font scale — the exact combination that crashed it.
  Future<void> pumpSheet(WidgetTester tester, {double textScale = 1.0}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1032, 2200); // ~344 logical wide
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteConfigTestOverride,
          hintGrantOverride(),
        ],
        child: _Harness(textScale: textScale),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opens cleanly under the real theme (normal scale)', (tester) async {
    await pumpSheet(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(GetMoreHintsSheet), findsOneWidget);
    expect(find.text('Buy a hint pack'), findsOneWidget);
  });

  testWidgets('opens cleanly under the real theme (2.0 font scale)', (tester) async {
    await pumpSheet(tester, textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('Buy a hint pack'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({this.textScale = 1.0});
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light, // the real theme — full-width FilledButton, etc.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showGetMoreHintsSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}
