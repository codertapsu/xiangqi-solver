import '../../../domain/board_piece.dart';

/// UCI square ↔ coordinate helpers (port of the backend `uci.util.ts`).
/// Columns a..i map to file 0..8; the rank digit is the rank 0..9.
const String _columns = 'abcdefghi';

String fileToColumn(int file) => _columns[file];

int columnToFile(String column) => _columns.indexOf(column);

BoardPosition squareToPosition(String square) => BoardPosition(
  file: columnToFile(square[0]),
  rank: int.parse(square.substring(1)),
);

String positionToSquare(BoardPosition pos) =>
    '${fileToColumn(pos.file)}${pos.rank}';

({BoardPosition from, BoardPosition to}) uciToMove(String uci) {
  if (uci.length != 4) {
    throw FormatException('Invalid UCI move "$uci"; expected 4 chars like "b2b7".');
  }
  return (
    from: squareToPosition(uci.substring(0, 2)),
    to: squareToPosition(uci.substring(2, 4)),
  );
}

String moveToUci(BoardPosition from, BoardPosition to) =>
    '${positionToSquare(from)}${positionToSquare(to)}';
