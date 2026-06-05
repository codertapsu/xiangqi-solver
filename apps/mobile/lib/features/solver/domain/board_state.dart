import 'package:equatable/equatable.dart';

import 'board_piece.dart';
import 'solver_enums.dart';

/// The board portion of an [AnalysisResult].
///
/// Mirrors the contract's `board` object: side to move, a FEN string, the list
/// of detected pieces, and an overall detection confidence in `0..1`.
class BoardState extends Equatable {
  const BoardState({
    required this.sideToMove,
    required this.fen,
    required this.pieces,
    required this.confidence,
  });

  final SideToMove sideToMove;
  final String fen;
  final List<BoardPiece> pieces;
  final double confidence;

  factory BoardState.fromJson(Map<String, dynamic> json) {
    final rawPieces = (json['pieces'] as List<dynamic>? ?? const []);
    return BoardState(
      sideToMove: SideToMove.fromWire(json['sideToMove'] as String?),
      fen: json['fen'] as String? ?? '',
      pieces: rawPieces
          .map((e) => BoardPiece.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'sideToMove': sideToMove.wireValue,
    'fen': fen,
    'pieces': pieces.map((p) => p.toResultJson()).toList(growable: false),
    'confidence': confidence,
  };

  @override
  List<Object?> get props => [sideToMove, fen, pieces, confidence];
}
