import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/domain/analysis_result.dart';
import 'package:xiangqi_solver/features/solver/domain/best_move.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/board_state.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

void main() {
  const sample = AnalysisResult(
    analysisId: '11111111-1111-4111-8111-111111111111',
    board: BoardState(
      sideToMove: SideToMove.red,
      fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
      pieces: [
        BoardPiece(
          color: PieceColor.red,
          type: PieceType.king,
          position: BoardPosition(file: 4, rank: 0),
          confidence: 0.99,
        ),
        BoardPiece(
          color: PieceColor.black,
          type: PieceType.rook,
          position: BoardPosition(file: 0, rank: 9),
        ),
      ],
      confidence: 0.93,
    ),
    bestMove: BestMove(
      from: BoardPosition(file: 1, rank: 2),
      to: BoardPosition(file: 4, rank: 2),
      uci: 'b3e3',
      human: 'Cannon to center',
      score: '+0.42',
      depth: 14,
    ),
    explanation: 'Centralize the cannon for pressure.',
    warnings: ['Low light may reduce accuracy.'],
    engine: ProviderStatus(provider: 'pikafish', ok: true),
    vision: ProviderStatus(provider: 'mock', ok: true),
  );

  group('AnalysisResult', () {
    test('round-trips through JSON', () {
      final decoded = AnalysisResult.fromJson(sample.toJson());
      expect(decoded, sample);
    });

    test('parses a null bestMove', () {
      final json = sample.toJson()..['bestMove'] = null;
      final decoded = AnalysisResult.fromJson(json);
      expect(decoded.bestMove, isNull);
    });

    test('tolerates missing optional fields', () {
      final decoded = AnalysisResult.fromJson({
        'analysisId': 'abc',
        'board': {
          'sideToMove': 'black',
          'fen': '',
          'pieces': <dynamic>[],
          'confidence': 0,
        },
      });
      expect(decoded.analysisId, 'abc');
      expect(decoded.board.sideToMove, SideToMove.black);
      expect(decoded.bestMove, isNull);
      expect(decoded.warnings, isEmpty);
      expect(decoded.engine.ok, isFalse);
      expect(decoded.vision.ok, isFalse);
    });

    test('prettyBoardJson produces indented JSON', () {
      final pretty = sample.prettyBoardJson();
      expect(pretty, contains('\n'));
      expect(pretty, contains('"sideToMove": "red"'));
    });
  });

  group('BestMove', () {
    test('round-trips through JSON', () {
      final move = sample.bestMove!;
      expect(BestMove.fromJson(move.toJson()), move);
    });
  });

  group('BoardState', () {
    test('round-trips through JSON', () {
      final state = sample.board;
      expect(BoardState.fromJson(state.toJson()), state);
    });
  });
}
