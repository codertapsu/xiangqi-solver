import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/app/theme/app_theme.dart';
import 'package:xiangqi_solver/features/solver/presentation/widgets/xiangqi_board.dart';

import '../support/sample_results.dart';

void main() {
  Future<void> pumpBoard(
    WidgetTester tester, {
    required double width,
    bool flipped = false,
    bool coordinates = true,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: XiangqiBoard(
                pieces: openingPieces,
                move: BoardArrow(from: centralCannon.from, to: centralCannon.to),
                candidates: [BoardArrow(from: horseAdvance.from, to: horseAdvance.to)],
                flipped: flipped,
                showCoordinates: coordinates,
                semanticsLabel: 'Board, red to move',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps the board proportions and announces itself', (tester) async {
    await pumpBoard(tester, width: 360);
    final size = tester.getSize(find.byType(XiangqiBoard));
    expect(size.width, 360);
    expect(size.width / size.height, closeTo(XiangqiBoard.aspectRatio(), 1e-6));
    expect(find.bySemanticsLabel('Board, red to move'), findsOneWidget);
  });

  testWidgets('paints at thumbnail and tablet sizes, both themes, both sides', (tester) async {
    for (final width in [64.0, 84.0, 360.0, 720.0]) {
      for (final flipped in [false, true]) {
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          await pumpBoard(
            tester,
            width: width,
            flipped: flipped,
            coordinates: width > 100,
            theme: theme,
          );
          expect(tester.takeException(), isNull, reason: 'width $width flipped $flipped');
        }
      }
    }
  });
}
