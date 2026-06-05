import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/local/local_fen.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

/// Canonical 32-piece Xiangqi start position — mirrors the backend
/// `start-position.ts` (rank 0 = Red home, file 0 = Red far-left).
const _backRank = <PieceType>[
  PieceType.rook,
  PieceType.horse,
  PieceType.elephant,
  PieceType.advisor,
  PieceType.king,
  PieceType.advisor,
  PieceType.elephant,
  PieceType.horse,
  PieceType.rook,
];

List<BoardPiece> _startPosition() {
  final out = <BoardPiece>[];
  void add(PieceColor color, PieceType type, int file, int rank) =>
      out.add(BoardPiece(color: color, type: type, position: BoardPosition(file: file, rank: rank)));

  for (final color in [PieceColor.red, PieceColor.black]) {
    final backRankNo = color == PieceColor.red ? 0 : 9;
    final cannonRank = color == PieceColor.red ? 2 : 7;
    final pawnRank = color == PieceColor.red ? 3 : 6;
    for (var file = 0; file < 9; file++) {
      add(color, _backRank[file], file, backRankNo);
    }
    for (final file in [1, 7]) {
      add(color, PieceType.cannon, file, cannonRank);
    }
    for (final file in [0, 2, 4, 6, 8]) {
      add(color, PieceType.pawn, file, pawnRank);
    }
  }
  return out;
}

void main() {
  group('toFen', () {
    test('produces the canonical start-position FEN exactly (Red to move)', () {
      expect(
        toFen(_startPosition(), SideToMove.red),
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
      );
    });

    test('encodes Black to move with the same placement', () {
      final fen = toFen(_startPosition(), SideToMove.black);
      expect(fen.startsWith('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR'), isTrue);
      expect(fen.split(' ')[1], 'b');
    });

    test('defaults an unknown side to Red (w)', () {
      expect(toFen(_startPosition(), SideToMove.unknown).split(' ')[1], 'w');
    });

    test('collapses an empty board to all-9 ranks', () {
      expect(toFen(const [], SideToMove.red), '9/9/9/9/9/9/9/9/9/9 w - - 0 1');
    });
  });
}
