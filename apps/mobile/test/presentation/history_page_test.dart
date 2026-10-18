import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/app/theme/app_theme.dart';
import 'package:xiangqi_solver/features/history/data/history_repository.dart';
import 'package:xiangqi_solver/features/history/domain/history_entry.dart';
import 'package:xiangqi_solver/features/history/presentation/history_page.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';
import 'package:xiangqi_solver/features/solver/presentation/widgets/xiangqi_board.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../support/hint_grant_test_override.dart';
import '../support/remote_config_test_override.dart';
import '../support/sample_results.dart';

void main() {
  late HistoryRepository repo;

  /// A 1.0-era entry: text only, no stored result.
  final legacy = HistoryEntry(
    analysisId: 'old-1',
    timestamp: DateTime(2026, 1, 2, 10, 0),
    aiProvider: 'openai',
    engineProvider: 'pikafish',
    bestMoveUci: 'b2e2',
    bestMoveHuman: null,
    confidence: 0.9,
    sideToMove: 'red',
  );

  Future<void> pump(WidgetTester tester, List<HistoryEntry> entries) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = HistoryRepository(prefs);
    for (final e in entries.reversed) {
      await repo.add(e);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteConfigTestOverride,
          hintGrantOverride(),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists analyses with a board preview; old entries as text', (tester) async {
    final fresh = HistoryEntry.fromResult(openingResult(id: 'new-1'));
    await pump(tester, [fresh, legacy]);

    expect(find.text('Cannon 2 to 5'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);
    expect(find.byType(XiangqiBoard), findsOneWidget);
    expect(find.text('b2e2'), findsOneWidget);
    expect(find.text('Saved by an older version — no board preview.'), findsOneWidget);
  });

  testWidgets('empty history explains what will appear', (tester) async {
    await pump(tester, const []);
    expect(find.text('No history yet'), findsOneWidget);
  });

  testWidgets('swipe deletes with undo; the delete commits when the snackbar goes', (
    tester,
  ) async {
    final fresh = HistoryEntry.fromResult(openingResult(id: 'new-1'));
    await pump(tester, [fresh]);

    await tester.drag(find.text('Cannon 2 to 5'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Cannon 2 to 5'), findsNothing);
    expect(find.text('Analysis deleted.'), findsOneWidget);

    // Undo puts it back and leaves storage untouched.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Cannon 2 to 5'), findsOneWidget);
    expect(repo.loadAll(), hasLength(1));

    // Without undo, the entry is removed once the snackbar times out.
    await tester.drag(find.text('Cannon 2 to 5'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(repo.loadAll(), isEmpty);
    expect(find.text('No history yet'), findsOneWidget);
  });

  testWidgets('clear all asks first, then empties the list', (tester) async {
    await pump(tester, [HistoryEntry.fromResult(openingResult(id: 'new-1')), legacy]);

    await tester.tap(find.byTooltip('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(repo.loadAll(), isEmpty);
    expect(find.text('No history yet'), findsOneWidget);
  });
}
