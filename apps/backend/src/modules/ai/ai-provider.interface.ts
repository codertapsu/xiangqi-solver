import { BoardPiece, SideToMove } from '../board/xiangqi.types';

/** Input to the vision board-extraction step. */
export interface ExtractBoardStateInput {
  imageBuffer: Buffer;
  mimeType: string;
  sideToMoveHint?: SideToMove;
}

/** Structured board state extracted from an image (never a move). */
export interface ExtractBoardStateResult {
  boardDetected: boolean;
  sideToMove: SideToMove;
  confidence: number;
  pieces: BoardPiece[];
  warnings: string[];
}

/** Pluggable AI vision provider contract (mock / Gemini / OpenAI). */
export interface AiVisionProvider {
  /** Human-readable provider name surfaced in AnalysisResult.vision.provider. */
  readonly name: string;
  extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult>;
}
