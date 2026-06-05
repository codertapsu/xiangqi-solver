import 'package:equatable/equatable.dart';

import 'solver_enums.dart';

/// A coordinate on the Xiangqi board.
///
/// `file` is the column 0..8 and `rank` is the row 0..9.
class BoardPosition extends Equatable {
  const BoardPosition({required this.file, required this.rank});

  final int file;
  final int rank;

  factory BoardPosition.fromJson(Map<String, dynamic> json) {
    return BoardPosition(
      file: (json['file'] as num).toInt(),
      rank: (json['rank'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {'file': file, 'rank': rank};

  @override
  List<Object?> get props => [file, rank];

  @override
  String toString() => '($file,$rank)';
}

/// A single piece used both as analysis input (POST /analysis/board) and as
/// part of an [AnalysisResult] board.
///
/// The request contract uses flat `file`/`rank`; the response contract nests
/// them under `position`. This model serializes flat via [toJson] (request
/// shape) and parses both shapes via [fromJson] so it round-trips against
/// either side of the contract.
class BoardPiece extends Equatable {
  const BoardPiece({
    required this.color,
    required this.type,
    required this.position,
    this.confidence,
  });

  final PieceColor color;
  final PieceType type;
  final BoardPosition position;

  /// Detection confidence in `0..1`, when provided by the vision provider.
  final double? confidence;

  int get file => position.file;
  int get rank => position.rank;

  factory BoardPiece.fromJson(Map<String, dynamic> json) {
    final BoardPosition position;
    if (json['position'] is Map) {
      position = BoardPosition.fromJson(
        (json['position'] as Map).cast<String, dynamic>(),
      );
    } else {
      position = BoardPosition(
        file: (json['file'] as num).toInt(),
        rank: (json['rank'] as num).toInt(),
      );
    }
    return BoardPiece(
      color: PieceColor.fromWire(json['color'] as String?),
      type: PieceType.fromWire(json['type'] as String?),
      position: position,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  /// Request shape: flat `file`/`rank` as required by POST /analysis/board.
  Map<String, dynamic> toJson() => {
    'color': color.wireValue,
    'type': type.wireValue,
    'file': position.file,
    'rank': position.rank,
    if (confidence != null) 'confidence': confidence,
  };

  /// Response shape: nested `position` as found inside an [AnalysisResult].
  Map<String, dynamic> toResultJson() => {
    'type': type.wireValue,
    'color': color.wireValue,
    'position': position.toJson(),
    if (confidence != null) 'confidence': confidence,
  };

  BoardPiece copyWith({
    PieceColor? color,
    PieceType? type,
    BoardPosition? position,
    double? confidence,
  }) {
    return BoardPiece(
      color: color ?? this.color,
      type: type ?? this.type,
      position: position ?? this.position,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  List<Object?> get props => [color, type, position, confidence];
}
