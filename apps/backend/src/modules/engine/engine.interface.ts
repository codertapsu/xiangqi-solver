import { BoardPosition, SideToMove } from '../board/xiangqi.types';

/** Input to an engine's best-move query. */
export interface EngineBestMoveInput {
  fen: string;
  sideToMove: SideToMove;
  depth: number;
  moveTimeMs: number;
  /** Search worker threads (Pikafish "Threads"). */
  threads?: number;
  /** Transposition table size in MB (Pikafish "Hash"). */
  hashMb?: number;
  /** Latency budget subtracted from movetime (Pikafish "Move Overhead", ms). */
  moveOverheadMs?: number;
  /** Number of principal variations to report (Pikafish "MultiPV"). */
  multiPv?: number;
}

/** One ranked line from a MultiPV search. */
export interface EngineMoveLine {
  uci: string;
  from: BoardPosition;
  to: BoardPosition;
  score: string;
  depth: number;
}

/** Result of a best-move query. */
export interface EngineBestMoveResult {
  uci: string;
  from: BoardPosition;
  to: BoardPosition;
  score: string;
  depth: number;
  ponder?: string;
  /** Ranked candidate lines (only when MultiPV > 1); index 0 is the best move. */
  multipv?: EngineMoveLine[];
  raw?: string;
}

/** Pluggable Xiangqi engine contract (mock or real Pikafish). */
export interface XiangqiEngine {
  /** Human-readable provider name surfaced in AnalysisResult.engine.provider. */
  readonly name: string;
  getBestMove(input: EngineBestMoveInput): Promise<EngineBestMoveResult>;
}

/** DI token for the active engine implementation. */
export const ENGINE_TOKEN = Symbol('XIANGQI_ENGINE');
