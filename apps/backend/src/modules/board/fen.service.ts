import { Injectable } from '@nestjs/common';
import {
  FILE_COUNT,
  MAX_RANK,
  NormalizedPiece,
  PIECE_TYPE_TO_FEN_LETTER,
  RANK_COUNT,
  SideToMove,
} from './xiangqi.types';

/**
 * Converts a normalized board into a standard (Pikafish) Xiangqi FEN.
 *
 * Placement is written rank 9 first (Black home, top) down to rank 0
 * (Red home, bottom), ranks joined by "/". Within a rank, files 0..8 go
 * left-to-right; consecutive empties collapse into a digit.
 *
 * Full FEN = "<placement> <side> - - 0 1" where side = "w" for Red to move,
 * else "b". When sideToMove is "unknown" we default to "w" (Red) and rely on
 * the normalizer to attach a warning.
 *
 * Orientation (file 0 = Red's far-left, rank 0 = Red home / written last) is
 * VERIFIED against the real Pikafish binary in
 * pikafish-real-binary.integration.spec.ts: the engine parses our start FEN as
 * the standard opening, Red/Black move from their own halves, and a forced
 * single-move position maps squares exactly. That suite self-skips unless a
 * real binary is configured (PIKAFISH_BINARY_PATH).
 */
@Injectable()
export class FenService {
  /** Build the placement field only (no side / counters). */
  toPlacement(pieces: NormalizedPiece[]): string {
    // grid[rank][file] -> FEN letter or undefined.
    const grid: (string | undefined)[][] = Array.from({ length: RANK_COUNT }, () =>
      Array.from({ length: FILE_COUNT }, () => undefined),
    );

    for (const piece of pieces) {
      const { file, rank } = piece.position;
      const letter = PIECE_TYPE_TO_FEN_LETTER[piece.type];
      const fen = piece.color === 'red' ? letter : letter.toLowerCase();
      grid[rank][file] = fen;
    }

    const rows: string[] = [];
    for (let rank = MAX_RANK; rank >= 0; rank--) {
      rows.push(this.encodeRank(grid[rank]));
    }
    return rows.join('/');
  }

  /** Build the full FEN string for the given board. */
  toFen(pieces: NormalizedPiece[], sideToMove: SideToMove): string {
    const placement = this.toPlacement(pieces);
    const side = sideToMove === 'black' ? 'b' : 'w';
    return `${placement} ${side} - - 0 1`;
  }

  /** Encode a single rank row, collapsing empty runs into digits. */
  private encodeRank(row: (string | undefined)[]): string {
    let out = '';
    let empty = 0;
    for (let file = 0; file < FILE_COUNT; file++) {
      const cell = row[file];
      if (cell === undefined) {
        empty++;
      } else {
        if (empty > 0) {
          out += String(empty);
          empty = 0;
        }
        out += cell;
      }
    }
    if (empty > 0) out += String(empty);
    return out;
  }
}
