import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/data/ondevice/local/local_notation.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

/// Mirrors the backend `move-notation.service.spec.ts` so the Dart port stays
/// faithful to the verified reference implementation.
BoardPiece _piece(PieceColor color, PieceType type, int file, int rank) =>
    BoardPiece(color: color, type: type, position: BoardPosition(file: file, rank: rank));

void main() {
  group('describeMove', () {
    test('central cannon (炮二平五) across languages', () {
      final pieces = [_piece(PieceColor.red, PieceType.cannon, 7, 2)]; // Red file 2
      const from = BoardPosition(file: 7, rank: 2);
      const to = BoardPosition(file: 4, rank: 2); // traverse to centre (file 5)

      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'en'),
        (human: 'Cannon 2 traverses to 5', wxf: 'C2=5'),
      );
      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'vi').human,
        'Pháo 2 bình 5',
      );
      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'zh').human,
        '炮二平五',
      );
    });

    test('horse advance (馬八進七) — value is the destination file', () {
      final pieces = [_piece(PieceColor.red, PieceType.horse, 1, 0)]; // Red file 8
      const from = BoardPosition(file: 1, rank: 0);
      const to = BoardPosition(file: 2, rank: 2);

      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'en'),
        (human: 'Horse 8 advances to 7', wxf: 'H8+7'),
      );
      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'zh').human,
        '傌八進七',
      );
    });

    test('vertical king advance (帥五進一) — value is a step count', () {
      final pieces = [_piece(PieceColor.red, PieceType.king, 4, 0)];
      const from = BoardPosition(file: 4, rank: 0);
      const to = BoardPosition(file: 4, rank: 1);

      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'en'),
        (human: 'King 5 advances 1', wxf: 'K5+1'),
      );
      expect(
        describeMove(from: from, to: to, pieces: pieces, language: 'zh').human,
        '帥五進一',
      );
    });

    test('rook retreat (steps)', () {
      final pieces = [_piece(PieceColor.red, PieceType.rook, 0, 3)];
      expect(
        describeMove(
          from: const BoardPosition(file: 0, rank: 3),
          to: const BoardPosition(file: 0, rank: 1),
          pieces: pieces,
          language: 'en',
        ),
        (human: 'Rook 9 retreats 2', wxf: 'R9-2'),
      );
    });

    test('disambiguates two pieces on the same file with front/rear', () {
      final pieces = [
        _piece(PieceColor.red, PieceType.rook, 0, 0),
        _piece(PieceColor.red, PieceType.rook, 0, 3),
      ];
      // Move the FRONT rook (higher rank, closer to the enemy) forward.
      expect(
        describeMove(
          from: const BoardPosition(file: 0, rank: 3),
          to: const BoardPosition(file: 0, rank: 5),
          pieces: pieces,
          language: 'en',
        ),
        (human: 'Front rook advances 2', wxf: '+R+2'),
      );
      expect(
        describeMove(
          from: const BoardPosition(file: 0, rank: 3),
          to: const BoardPosition(file: 0, rank: 5),
          pieces: pieces,
          language: 'zh',
        ).human,
        '前俥進二',
      );
      // Move the REAR rook.
      expect(
        describeMove(
          from: const BoardPosition(file: 0, rank: 0),
          to: const BoardPosition(file: 0, rank: 1),
          pieces: pieces,
          language: 'en',
        ),
        (human: 'Rear rook advances 1', wxf: '-R+1'),
      );
    });

    test('uses Arabic numerals for Black in Chinese notation', () {
      final pieces = [_piece(PieceColor.black, PieceType.cannon, 1, 7)]; // Black file 2
      final r = describeMove(
        from: const BoardPosition(file: 1, rank: 7),
        to: const BoardPosition(file: 4, rank: 7),
        pieces: pieces,
        language: 'zh',
      );
      expect(r.human, '砲2平5');
      expect(r.wxf, 'C2=5');
    });

    test('falls back to coordinates when the moving piece is unknown', () {
      final r = describeMove(
        from: const BoardPosition(file: 1, rank: 2),
        to: const BoardPosition(file: 4, rank: 2),
        pieces: const [],
        language: 'en',
      );
      expect(r.human, contains('→'));
    });
  });
}
