/// Enumerations that mirror the shared API contract for Xiangqi analysis.
///
/// Each enum exposes a stable [wireValue] (the exact string used on the wire)
/// and a tolerant [fromWire] parser that falls back to a sensible default
/// rather than throwing, so a slightly-out-of-spec backend never crashes the
/// client.
library;

/// Which side moves next.
enum SideToMove {
  red('red'),
  black('black'),
  unknown('unknown');

  const SideToMove(this.wireValue);

  final String wireValue;

  static SideToMove fromWire(String? value) {
    return SideToMove.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => SideToMove.unknown,
    );
  }

  String get label => switch (this) {
    SideToMove.red => 'Red',
    SideToMove.black => 'Black',
    SideToMove.unknown => 'Unknown',
  };
}

/// Colour of a piece.
enum PieceColor {
  red('red'),
  black('black');

  const PieceColor(this.wireValue);

  final String wireValue;

  static PieceColor fromWire(String? value) {
    return PieceColor.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => PieceColor.red,
    );
  }
}

/// Type of a Xiangqi piece.
enum PieceType {
  king('king'),
  advisor('advisor'),
  elephant('elephant'),
  horse('horse'),
  rook('rook'),
  cannon('cannon'),
  pawn('pawn');

  const PieceType(this.wireValue);

  final String wireValue;

  static PieceType fromWire(String? value) {
    return PieceType.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => PieceType.pawn,
    );
  }

  String get label => switch (this) {
    PieceType.king => 'King',
    PieceType.advisor => 'Advisor',
    PieceType.elephant => 'Elephant',
    PieceType.horse => 'Horse',
    PieceType.rook => 'Rook',
    PieceType.cannon => 'Cannon',
    PieceType.pawn => 'Pawn',
  };
}

/// Vision (AI) provider used to read the board from an image.
enum AiProvider {
  gemini('gemini'),
  openai('openai'),
  mock('mock');

  const AiProvider(this.wireValue);

  final String wireValue;

  static AiProvider fromWire(String? value) {
    return AiProvider.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => AiProvider.mock,
    );
  }

  String get label => switch (this) {
    AiProvider.gemini => 'Gemini',
    AiProvider.openai => 'OpenAI',
    AiProvider.mock => 'Mock',
  };
}

/// Engine provider used to compute the best move.
enum EngineProvider {
  pikafish('pikafish'),
  mock('mock');

  const EngineProvider(this.wireValue);

  final String wireValue;

  static EngineProvider fromWire(String? value) {
    return EngineProvider.values.firstWhere(
      (e) => e.wireValue == value,
      orElse: () => EngineProvider.mock,
    );
  }

  String get label => switch (this) {
    EngineProvider.pikafish => 'Pikafish',
    EngineProvider.mock => 'Mock',
  };
}
