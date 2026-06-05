import 'package:flutter_test/flutter_test.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

void main() {
  group('BoardPosition', () {
    test('round-trips through JSON', () {
      const position = BoardPosition(file: 4, rank: 9);
      final decoded = BoardPosition.fromJson(position.toJson());
      expect(decoded, position);
    });

    test('coerces numeric (double) coordinates to int', () {
      final decoded = BoardPosition.fromJson({'file': 3.0, 'rank': 7.0});
      expect(decoded, const BoardPosition(file: 3, rank: 7));
    });
  });

  group('BoardPiece', () {
    const piece = BoardPiece(
      color: PieceColor.black,
      type: PieceType.cannon,
      position: BoardPosition(file: 1, rank: 2),
      confidence: 0.87,
    );

    test('toJson uses the flat request shape (file/rank)', () {
      final json = piece.toJson();
      expect(json['color'], 'black');
      expect(json['type'], 'cannon');
      expect(json['file'], 1);
      expect(json['rank'], 2);
      expect(json['confidence'], 0.87);
      expect(json.containsKey('position'), isFalse);
    });

    test('toResultJson uses the nested response shape (position)', () {
      final json = piece.toResultJson();
      expect(json['position'], {'file': 1, 'rank': 2});
      expect(json.containsKey('file'), isFalse);
    });

    test('round-trips from the flat request shape', () {
      final decoded = BoardPiece.fromJson(piece.toJson());
      expect(decoded, piece);
    });

    test('round-trips from the nested response shape', () {
      final decoded = BoardPiece.fromJson(piece.toResultJson());
      expect(decoded, piece);
    });

    test('omits confidence when null', () {
      const noConfidence = BoardPiece(
        color: PieceColor.red,
        type: PieceType.king,
        position: BoardPosition(file: 4, rank: 0),
      );
      expect(noConfidence.toJson().containsKey('confidence'), isFalse);
      final decoded = BoardPiece.fromJson(noConfidence.toJson());
      expect(decoded, noConfidence);
    });

    test('unknown enum values fall back without throwing', () {
      final decoded = BoardPiece.fromJson({
        'color': 'green',
        'type': 'dragon',
        'file': 0,
        'rank': 0,
      });
      expect(decoded.color, PieceColor.red);
      expect(decoded.type, PieceType.pawn);
    });
  });
}
