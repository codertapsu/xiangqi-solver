import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/app/theme/app_theme.dart';
import 'package:xiangqi_solver/features/settings/presentation/settings_page.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../support/fake_native_solver.dart';
import '../support/hint_grant_test_override.dart';
import '../support/remote_config_test_override.dart';

void main() {
  late SharedPreferences prefs;

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          nativeSolverProvider.overrideWithValue(FakeNativeSolver()),
          remoteConfigUiVisibleTestOverride,
          hintGrantOverride(),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );

  testWidgets('theme choice is saved', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(prefs.getString('settings.themeMode'), 'dark');
  });

  testWidgets('side picker sets the side the engine solves for', (tester) async {
    await pump(tester);
    await scrollTo(tester, find.text('Black'));
    await tester.tap(find.text('Black'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
    expect(container.read(settingsProvider).mySide, SideToMove.black);
  });

  testWidgets('every group renders without overflow at 2x text', (tester) async {
    await pump(tester, textScale: 2);
    for (final group in ['Game', 'Appearance', 'Privacy', 'Advanced', 'About']) {
      await scrollTo(tester, find.text(group));
      expect(tester.takeException(), isNull, reason: group);
    }
    await scrollTo(tester, find.text('Version'));
    expect(tester.takeException(), isNull);
  });
}
