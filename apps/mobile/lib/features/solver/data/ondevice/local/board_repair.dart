import '../../../domain/board_piece.dart';
import '../../../domain/solver_enums.dart';

/// Best-effort repair of an imperfect (AI-extracted) board, mirroring the
/// backend `BoardValidatorService.repair`: drop out-of-range pieces, resolve
/// overlaps (keep the most confident), and cap per-type counts.
const Map<PieceType, int> _maxPerType = {
  PieceType.king: 1,
  PieceType.advisor: 2,
  PieceType.elephant: 2,
  PieceType.horse: 2,
  PieceType.rook: 2,
  PieceType.cannon: 2,
  PieceType.pawn: 5,
};

double _conf(BoardPiece p) => p.confidence ?? 0.5;

({List<BoardPiece> pieces, List<String> warnings}) repairBoard(List<BoardPiece> input) {
  final warnings = <String>[];

  final inRange = input
      .where((p) => p.file >= 0 && p.file <= 8 && p.rank >= 0 && p.rank <= 9)
      .toList();
  if (inRange.length != input.length) {
    warnings.add('Ignored ${input.length - inRange.length} out-of-range piece(s).');
  }

  // One piece per square (keep the more confident on a collision).
  final bySquare = <String, BoardPiece>{};
  var overlaps = 0;
  for (final p in inRange) {
    final key = '${p.file},${p.rank}';
    final existing = bySquare[key];
    if (existing == null) {
      bySquare[key] = p;
    } else {
      overlaps++;
      if (_conf(p) > _conf(existing)) bySquare[key] = p;
    }
  }
  if (overlaps > 0) {
    warnings.add('Resolved $overlaps overlapping piece(s) (kept the most confident).');
  }

  // Cap each side's per-type counts.
  final groups = <String, List<BoardPiece>>{};
  for (final p in bySquare.values) {
    groups.putIfAbsent('${p.color}:${p.type}', () => []).add(p);
  }
  final kept = <BoardPiece>[];
  var trimmed = 0;
  for (final group in groups.values) {
    final max = _maxPerType[group.first.type]!;
    if (group.length <= max) {
      kept.addAll(group);
    } else {
      final ranked = [...group]..sort((a, b) => _conf(b).compareTo(_conf(a)));
      kept.addAll(ranked.take(max));
      trimmed += group.length - max;
    }
  }
  if (trimmed > 0) {
    warnings.add('Ignored $trimmed piece(s) beyond the legal count for their type.');
  }

  return (pieces: kept, warnings: warnings);
}

/// True when both generals (kings) are present.
bool hasBothGenerals(List<BoardPiece> pieces) {
  final hasRed = pieces.any((p) => p.type == PieceType.king && p.color == PieceColor.red);
  final hasBlack = pieces.any((p) => p.type == PieceType.king && p.color == PieceColor.black);
  return hasRed && hasBlack;
}
