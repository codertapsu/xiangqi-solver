import 'package:equatable/equatable.dart';

import 'board_piece.dart';

/// The engine's recommended move.
///
/// Mirrors the contract's `bestMove`: a from/to coordinate pair plus UCI/human
/// notations, an evaluation [score], and the search [depth] reached.
class BestMove extends Equatable {
  const BestMove({
    required this.from,
    required this.to,
    required this.uci,
    required this.human,
    required this.score,
    required this.depth,
    this.notation = '',
  });

  final BoardPosition from;
  final BoardPosition to;
  final String uci;

  /// Localized traditional notation, e.g. "Cannon 8 traverses to 5".
  final String human;

  /// Universal WXF code, e.g. "C8=5".
  final String notation;
  final String score;
  final int depth;

  factory BestMove.fromJson(Map<String, dynamic> json) {
    return BestMove(
      from: BoardPosition.fromJson((json['from'] as Map).cast<String, dynamic>()),
      to: BoardPosition.fromJson((json['to'] as Map).cast<String, dynamic>()),
      uci: json['uci'] as String? ?? '',
      human: json['human'] as String? ?? '',
      notation: json['notation'] as String? ?? '',
      score: json['score'] as String? ?? '',
      depth: (json['depth'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'from': from.toJson(),
    'to': to.toJson(),
    'uci': uci,
    'human': human,
    'notation': notation,
    'score': score,
    'depth': depth,
  };

  @override
  List<Object?> get props => [from, to, uci, human, notation, score, depth];
}
