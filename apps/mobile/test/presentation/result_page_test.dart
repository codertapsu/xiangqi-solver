import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiangqi_solver/app/theme/app_theme.dart';
import 'package:xiangqi_solver/core/errors/failure.dart';
import 'package:xiangqi_solver/features/history/data/history_repository.dart';
import 'package:xiangqi_solver/features/history/domain/history_entry.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';
import 'package:xiangqi_solver/features/solver/presentation/pages/result_page.dart';
import 'package:xiangqi_solver/features/solver/presentation/providers/solver_providers.dart';
import 'package:xiangqi_solver/features/solver/presentation/widgets/xiangqi_board.dart';
import 'package:xiangqi_solver/l10n/gen/app_localizations.dart';

import '../support/hint_grant_test_override.dart';
import '../support/remote_config_test_override.dart';
import '../support/sample_results.dart';

/// An [AnalysisNotifier] that starts in a given state.
class _Seeded extends AnalysisNotifier {
  _Seeded(super.ref, AnalysisStatus initial) {
    state = initial;
  }
}

void main() {
  late SharedPreferences prefs;

  Future<void> pump(
    WidgetTester tester, {
    AnalysisStatus status = const AnalysisIdle(),
    String? historyId,
    double textScale = 1,
    ThemeData? theme,
    List<HistoryEntry> history = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final repo = HistoryRepository(prefs);
    for (final e in history.reversed) {
      await repo.add(e);
    }
    // A narrow phone, where large text is most likely to overflow.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          remoteConfigTestOverride,
          hintGrantOverride(),
          analysisProvider.overrideWith((ref) => _Seeded(ref, status)),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ResultPage(historyId: historyId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the best move on the board with an evaluation', (tester) async {
    await pump(tester, status: AnalysisSuccess(openingResult()));

    expect(tester.takeException(), isNull);
    expect(find.text('Cannon 2 to 5'), findsWidgets);
    expect(find.text('Best'), findsOneWidget);
    expect(find.text('C2=5'), findsWidgets);
    expect(find.text('Depth 12'), findsOneWidget);
    expect(find.text('Even position'), findsOneWidget);
    final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    expect(board.move, BoardArrow(from: centralCannon.from, to: centralCannon.to));
    expect(board.flipped, isFalse);
  });

  testWidgets('tapping another top move previews it on the board', (tester) async {
    await pump(tester, status: AnalysisSuccess(openingResult()));

    final option = find.text('Horse 2 forward to 3');
    await tester.scrollUntilVisible(option, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(option);
    await tester.pumpAndSettle();

    expect(find.text('Option 2'), findsOneWidget);
    final board = tester.widget<XiangqiBoard>(find.byType(XiangqiBoard));
    expect(board.move, BoardArrow(from: horseAdvance.from, to: horseAdvance.to));
  });

  testWidgets('a Black solve is drawn from Black\'s side', (tester) async {
    await pump(tester, status: AnalysisSuccess(openingResult(side: SideToMove.black)));
    expect(tester.widget<XiangqiBoard>(find.byType(XiangqiBoard)).flipped, isTrue);
    expect(find.text('Black to move'), findsOneWidget);
  });

  testWidgets('out of hints offers more hints instead of a dead end', (tester) async {
    await pump(
      tester,
      status: const AnalysisError(UnknownFailure('You are out of hints.', code: 'NO_HINTS')),
    );
    expect(find.text("You're out of hints"), findsOneWidget);
    expect(find.text('Get more hints'), findsOneWidget);
    expect(find.text('Back to Home'), findsOneWidget);
  });

  testWidgets('reopens a saved analysis from history', (tester) async {
    final entry = HistoryEntry.fromResult(openingResult(id: 'saved-1'));
    await pump(tester, historyId: 'saved-1', history: [entry]);
    expect(find.text('Cannon 2 to 5'), findsWidgets);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
  });

  testWidgets('an unknown or pre-1.1 history entry explains itself', (tester) async {
    await pump(tester, historyId: 'missing');
    expect(find.text("This result can't be shown"), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('no overflow at 2x text on a narrow phone (dark: $dark)', (tester) async {
      await pump(
        tester,
        status: AnalysisSuccess(openingResult(warnings: const ['Low light may reduce accuracy.'])),
        textScale: 2,
        theme: dark ? AppTheme.dark : AppTheme.light,
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
