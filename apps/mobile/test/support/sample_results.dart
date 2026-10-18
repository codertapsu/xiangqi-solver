import 'package:xiangqi_solver/features/solver/domain/analysis_result.dart';
import 'package:xiangqi_solver/features/solver/domain/best_move.dart';
import 'package:xiangqi_solver/features/solver/domain/board_piece.dart';
import 'package:xiangqi_solver/features/solver/domain/board_state.dart';
import 'package:xiangqi_solver/features/solver/domain/solver_enums.dart';

BoardPiece _p(PieceColor c, PieceType t, int file, int rank) =>
    BoardPiece(color: c, type: t, position: BoardPosition(file: file, rank: rank));

/// The standard opening position (rank 0 = Red's home row).
final List<BoardPiece> openingPieces = [
  for (final (color, home, cannons, pawns) in [
    (PieceColor.red, 0, 2, 3),
    (PieceColor.black, 9, 7, 6),
  ]) ...[
    _p(color, PieceType.rook, 0, home),
    _p(color, PieceType.horse, 1, home),
    _p(color, PieceType.elephant, 2, home),
    _p(color, PieceType.advisor, 3, home),
    _p(color, PieceType.king, 4, home),
    _p(color, PieceType.advisor, 5, home),
    _p(color, PieceType.elephant, 6, home),
    _p(color, PieceType.horse, 7, home),
    _p(color, PieceType.rook, 8, home),
    _p(color, PieceType.cannon, 1, cannons),
    _p(color, PieceType.cannon, 7, cannons),
    for (final f in [0, 2, 4, 6, 8]) _p(color, PieceType.pawn, f, pawns),
  ],
];

const BestMove centralCannon = BestMove(
  from: BoardPosition(file: 7, rank: 2),
  to: BoardPosition(file: 4, rank: 2),
  uci: 'h2e2',
  human: 'Cannon 2 to 5',
  notation: 'C2=5',
  score: '+0.27',
  depth: 12,
);

const BestMove horseAdvance = BestMove(
  from: BoardPosition(file: 7, rank: 0),
  to: BoardPosition(file: 6, rank: 2),
  uci: 'h0g2',
  human: 'Horse 2 forward to 3',
  notation: 'H2+3',
  score: '+0.21',
  depth: 12,
);

/// A finished analysis of the opening, with two candidate moves.
AnalysisResult openingResult({
  String id = 'a1',
  SideToMove side = SideToMove.red,
  List<String> warnings = const [],
}) => AnalysisResult(
  analysisId: id,
  board: BoardState(
    sideToMove: side,
    fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w',
    pieces: openingPieces,
    confidence: 0.96,
  ),
  bestMove: centralCannon,
  candidates: const [centralCannon, horseAdvance],
  explanation: '',
  warnings: warnings,
  engine: const ProviderStatus(provider: 'pikafish', ok: true),
  vision: const ProviderStatus(provider: 'openai', ok: true),
);
