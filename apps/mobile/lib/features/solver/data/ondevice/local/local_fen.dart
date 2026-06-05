import '../../../domain/board_piece.dart';
import '../../../domain/solver_enums.dart';

/// Xiangqi FEN piece letters (uppercase = Red, lowercase = Black). Port of the
/// backend `fen.service.ts` — orientation verified against the real Pikafish
/// binary (see backend pikafish-real-binary.integration.spec.ts).
const Map<PieceType, String> _fenLetter = {
  PieceType.king: 'K',
  PieceType.advisor: 'A',
  PieceType.elephant: 'B',
  PieceType.horse: 'N',
  PieceType.rook: 'R',
  PieceType.cannon: 'C',
  PieceType.pawn: 'P',
};

/// Build a Pikafish/standard Xiangqi FEN from board pieces.
///
/// Placement is written rank 9 (Black home, top) down to rank 0 (Red home,
/// bottom); within a rank, file 0..8 left to right; empties collapsed to a
/// digit. Side = "w" for Red (or unknown), else "b".
String toFen(List<BoardPiece> pieces, SideToMove sideToMove) {
  final grid = List.generate(10, (_) => List<String?>.filled(9, null));
  for (final p in pieces) {
    if (p.file < 0 || p.file > 8 || p.rank < 0 || p.rank > 9) continue;
    final letter = _fenLetter[p.type]!;
    grid[p.rank][p.file] = p.color == PieceColor.black ? letter.toLowerCase() : letter;
  }

  final ranks = <String>[];
  for (var rank = 9; rank >= 0; rank--) {
    final buffer = StringBuffer();
    var empty = 0;
    for (var file = 0; file < 9; file++) {
      final cell = grid[rank][file];
      if (cell == null) {
        empty++;
      } else {
        if (empty > 0) {
          buffer.write(empty);
          empty = 0;
        }
        buffer.write(cell);
      }
    }
    if (empty > 0) buffer.write(empty);
    ranks.add(buffer.toString());
  }

  final side = sideToMove == SideToMove.black ? 'b' : 'w';
  return '${ranks.join('/')} $side - - 0 1';
}
