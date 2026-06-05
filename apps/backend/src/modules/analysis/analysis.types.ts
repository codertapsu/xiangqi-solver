import { BoardPosition, NormalizedPiece, SideToMove } from '../board/xiangqi.types';

/** Board section of the analysis result. */
export interface AnalysisBoard {
  sideToMove: SideToMove;
  fen: string;
  pieces: NormalizedPiece[];
  confidence: number;
}

/** Best-move section (null when the engine returns no move). */
export interface AnalysisBestMove {
  from: BoardPosition;
  to: BoardPosition;
  uci: string;
  /** Localized traditional notation, e.g. "Cannon 8 traverses to 5". */
  human: string;
  /** Universal WXF code, e.g. "C8=5". */
  notation: string;
  score: string;
  depth: number;
}

/** Provider status block (engine or vision). */
export interface ProviderStatus {
  provider: string;
  ok: boolean;
}

/**
 * Vision-only result from POST /api/analysis/extract: the recognized board with
 * NO engine analysis. Lets a client (e.g. a future on-device engine) get the
 * board state and compute the move locally.
 */
export interface ExtractionResult {
  extractionId: string;
  board: AnalysisBoard;
  warnings: string[];
  vision: ProviderStatus;
}

/** Full analysis result returned by both analysis endpoints. */
export interface AnalysisResult {
  analysisId: string;
  board: AnalysisBoard;
  bestMove: AnalysisBestMove | null;
  /** Ranked candidate moves when MultiPV > 1 (empty otherwise); index 0 = best. */
  candidates: AnalysisBestMove[];
  explanation: string;
  warnings: string[];
  engine: ProviderStatus;
  vision: ProviderStatus;
}
