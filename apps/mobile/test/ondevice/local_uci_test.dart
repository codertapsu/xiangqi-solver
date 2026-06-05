import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/local/local_uci.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';

void main() {
  group('square ↔ coordinate', () {
    test('maps columns a..i to files 0..8 and rank digits straight through', () {
      expect(squareToPosition('a0'), const BoardPosition(file: 0, rank: 0));
      expect(squareToPosition('b2'), const BoardPosition(file: 1, rank: 2));
      expect(squareToPosition('i9'), const BoardPosition(file: 8, rank: 9));
    });

    test('positionToSquare is the inverse', () {
      expect(positionToSquare(const BoardPosition(file: 1, rank: 2)), 'b2');
      expect(positionToSquare(const BoardPosition(file: 8, rank: 9)), 'i9');
    });

    test('fileToColumn / columnToFile round-trip', () {
      for (var f = 0; f < 9; f++) {
        expect(columnToFile(fileToColumn(f)), f);
      }
    });
  });

  group('uciToMove / moveToUci', () {
    test('splits a 4-char UCI move into from/to', () {
      final move = uciToMove('b2e2');
      expect(move.from, const BoardPosition(file: 1, rank: 2));
      expect(move.to, const BoardPosition(file: 4, rank: 2));
    });

    test('moveToUci is the inverse', () {
      expect(
        moveToUci(const BoardPosition(file: 1, rank: 2), const BoardPosition(file: 4, rank: 2)),
        'b2e2',
      );
    });

    test('round-trips an arbitrary move', () {
      const uci = 'a0i9';
      final m = uciToMove(uci);
      expect(moveToUci(m.from, m.to), uci);
    });

    test('throws on a malformed move', () {
      expect(() => uciToMove('b2e'), throwsFormatException);
      expect(() => uciToMove('b2e2x'), throwsFormatException);
    });
  });
}
