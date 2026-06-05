import { BoardPiece, PieceColor, PieceType } from './xiangqi.types';

/**
 * Deterministic standard 32-piece Xiangqi start position, expressed in the
 * shared file/rank coordinate system:
 *   rank 0 = Red home, rank 9 = Black home; file 0 = Red far-left.
 *
 * Used by the MockVisionProvider and validated against START_POSITION_FEN
 * in unit tests.
 */

const BACK_RANK: PieceType[] = [
  'rook',
  'horse',
  'elephant',
  'advisor',
  'king',
  'advisor',
  'elephant',
  'horse',
  'rook',
];

function backRank(color: PieceColor, rank: number): BoardPiece[] {
  return BACK_RANK.map((type, file) => ({ color, type, file, rank, confidence: 0.9 }));
}

function cannons(color: PieceColor, rank: number): BoardPiece[] {
  // Cannons sit on files 1 and 7 (FEN rank "1c5c1").
  return [1, 7].map((file) => ({ color, type: 'cannon' as const, file, rank, confidence: 0.9 }));
}

function pawns(color: PieceColor, rank: number): BoardPiece[] {
  return [0, 2, 4, 6, 8].map((file) => ({
    color,
    type: 'pawn' as const,
    file,
    rank,
    confidence: 0.9,
  }));
}

/** Build a fresh copy of the start position (never share mutable state). */
export function buildStartPosition(): BoardPiece[] {
  return [
    // Red (bottom): back rank 0, cannons rank 2, pawns rank 3.
    ...backRank('red', 0),
    ...cannons('red', 2),
    ...pawns('red', 3),
    // Black (top): back rank 9, cannons rank 7, pawns rank 6.
    ...backRank('black', 9),
    ...cannons('black', 7),
    ...pawns('black', 6),
  ];
}
