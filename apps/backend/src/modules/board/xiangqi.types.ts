/**
 * Core Xiangqi (Chinese chess) domain types and coordinate spec.
 *
 * Coordinate system (shared contract):
 *  - file: int 0..8   (0 = Red far-left file, 8 = Red far-right file)
 *  - rank: int 0..9   (0 = Red home rank, 9 = Black home rank)
 */

export type PieceColor = 'red' | 'black';

export type PieceType = 'king' | 'advisor' | 'elephant' | 'horse' | 'rook' | 'cannon' | 'pawn';

export type SideToMove = 'red' | 'black' | 'unknown';

/** Board geometry constants. */
export const FILE_COUNT = 9; // files 0..8
export const RANK_COUNT = 10; // ranks 0..9
export const MIN_FILE = 0;
export const MAX_FILE = 8;
export const MIN_RANK = 0;
export const MAX_RANK = 9;

export interface BoardPosition {
  file: number; // 0..8
  rank: number; // 0..9
}

/** A piece as accepted on input (file/rank flattened). */
export interface BoardPiece {
  color: PieceColor;
  type: PieceType;
  file: number; // 0..8
  rank: number; // 0..9
  confidence?: number;
}

/** A piece as emitted in AnalysisResult (nested position). */
export interface NormalizedPiece {
  type: PieceType;
  color: PieceColor;
  position: BoardPosition;
  confidence?: number;
}

/** Normalized, validated board ready for FEN conversion. */
export interface NormalizedBoard {
  sideToMove: SideToMove;
  pieces: NormalizedPiece[];
  confidence: number;
  warnings: string[];
}

/**
 * FEN piece letters (Pikafish / standard Xiangqi):
 *   King=K Advisor=A Elephant=B Horse=N Rook=R Cannon=C Pawn=P
 * Uppercase = Red, lowercase = Black.
 */
export const PIECE_TYPE_TO_FEN_LETTER: Record<PieceType, string> = {
  king: 'K',
  advisor: 'A',
  elephant: 'B',
  horse: 'N',
  rook: 'R',
  cannon: 'C',
  pawn: 'P',
};

export const FEN_LETTER_TO_PIECE_TYPE: Record<string, PieceType> = {
  K: 'king',
  A: 'advisor',
  B: 'elephant',
  N: 'horse',
  R: 'rook',
  C: 'cannon',
  P: 'pawn',
};

/** Canonical start position FEN (asserted exactly in unit tests). */
export const START_POSITION_FEN =
  'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';
