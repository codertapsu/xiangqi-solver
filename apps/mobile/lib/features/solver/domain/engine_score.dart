import 'dart:math' as math;

/// How the position stands for the side to move, in words.
enum EvalVerdict { even, slightEdge, advantage, winning, slightlyWorse, worse, losing, mate, mated }

/// An engine evaluation parsed from the display string both engines produce:
/// `+0.27` / `-1.40` (pawns, from the side to move's point of view) or
/// `mate 3` / `mate -2`.
class EngineScore {
  const EngineScore._({this.pawns, this.mateIn});

  /// Centipawns as pawns (positive = good for the side to move).
  final double? pawns;

  /// Moves to mate (negative = the side to move gets mated).
  final int? mateIn;

  bool get isMate => mateIn != null;

  static final RegExp _mate = RegExp(r'^mate\s+(-?\d+)$', caseSensitive: false);

  /// Null when [raw] is empty or not a recognizable score.
  static EngineScore? tryParse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final mate = _mate.firstMatch(s);
    if (mate != null) {
      final n = int.tryParse(mate.group(1)!);
      return n == null ? null : EngineScore._(mateIn: n);
    }
    final pawns = double.tryParse(s);
    return pawns == null ? null : EngineScore._(pawns: pawns);
  }

  EvalVerdict get verdict {
    final m = mateIn;
    if (m != null) return m >= 0 ? EvalVerdict.mate : EvalVerdict.mated;
    final p = pawns ?? 0;
    final a = p.abs();
    if (a < 0.35) return EvalVerdict.even;
    if (p > 0) {
      if (a < 1.0) return EvalVerdict.slightEdge;
      if (a < 2.5) return EvalVerdict.advantage;
      return EvalVerdict.winning;
    }
    if (a < 1.0) return EvalVerdict.slightlyWorse;
    if (a < 2.5) return EvalVerdict.worse;
    return EvalVerdict.losing;
  }

  /// 0..1: how the side to move stands (0.5 = even), for a meter. A logistic
  /// curve: +1 pawn ≈ 0.65, +3 ≈ 0.86; mates pin to the ends.
  double get share {
    final m = mateIn;
    if (m != null) return m >= 0 ? 0.97 : 0.03;
    final p = pawns ?? 0;
    return (1 / (1 + math.exp(-0.6 * p))).clamp(0.03, 0.97);
  }

  /// "+0.27" style signed text (empty for mates).
  String get signedPawns {
    final p = pawns;
    if (p == null) return '';
    return '${p >= 0 ? '+' : '−'}${p.abs().toStringAsFixed(2)}';
  }
}
