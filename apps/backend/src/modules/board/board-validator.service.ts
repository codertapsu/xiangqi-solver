import { BadRequestException, Injectable } from '@nestjs/common';
import {
  BoardPiece,
  MAX_FILE,
  MAX_RANK,
  MIN_FILE,
  MIN_RANK,
  PieceColor,
  PieceType,
} from './xiangqi.types';

/** Maximum number of each piece type a single side may legally have. */
const MAX_PER_TYPE: Record<PieceType, number> = {
  king: 1,
  advisor: 2,
  elephant: 2,
  horse: 2,
  rook: 2,
  cannon: 2,
  pawn: 5,
};

/** Treat missing confidence as a neutral 0.5 when ranking pieces to keep. */
const conf = (p: BoardPiece): number => (typeof p.confidence === 'number' ? p.confidence : 0.5);

export interface RepairOutcome {
  pieces: BoardPiece[];
  warnings: string[];
}

export interface ValidationOutcome {
  /** Hard errors that make the board unusable (throws on validateOrThrow). */
  errors: string[];
  /** Soft issues that do not block analysis but are surfaced to the user. */
  warnings: string[];
}

/** Max pieces per side in a legal Xiangqi position. */
const MAX_PIECES_PER_SIDE = 16;
const MAX_TOTAL_PIECES = 32;

/**
 * Validates a raw list of board pieces against Xiangqi rules. Pure logic,
 * no I/O. Distinguishes hard errors (out-of-range, duplicate square, missing
 * king, too many pieces) from soft warnings (e.g. multiple kings per side).
 */
@Injectable()
export class BoardValidatorService {
  /** Collect every issue without throwing. */
  validate(pieces: BoardPiece[]): ValidationOutcome {
    const errors: string[] = [];
    const warnings: string[] = [];

    if (!Array.isArray(pieces) || pieces.length === 0) {
      errors.push('Board has no pieces.');
      return { errors, warnings };
    }

    if (pieces.length > MAX_TOTAL_PIECES) {
      errors.push(
        `Too many pieces: ${pieces.length} (a Xiangqi board has at most ${MAX_TOTAL_PIECES}).`,
      );
    }

    this.checkRanges(pieces, errors);
    this.checkDuplicateSquares(pieces, errors);
    this.checkKings(pieces, errors, warnings);
    this.checkPerSideCounts(pieces, errors);

    return { errors, warnings };
  }

  /**
   * Best-effort repair for IMPERFECT (AI-extracted) boards: rather than
   * rejecting the whole analysis when a vision model mis-reads a busy board,
   * fix what we safely can and report each correction as a warning.
   *
   *  1. Drop pieces with out-of-range coordinates.
   *  2. Resolve two pieces on the same point — keep the more confident one.
   *  3. Trim piece counts that exceed the legal maximum per type — keep the
   *     most confident, drop the rest.
   *
   * The result is always a board with at most one piece per square and legal
   * per-type counts. It may still be missing a general; the caller decides
   * whether that is analyzable.
   */
  repair(pieces: BoardPiece[]): RepairOutcome {
    const warnings: string[] = [];
    if (!Array.isArray(pieces) || pieces.length === 0) {
      return { pieces: [], warnings };
    }

    // 1. Drop out-of-range pieces.
    const inRange = pieces.filter(
      (p) =>
        Number.isInteger(p.file) &&
        p.file >= MIN_FILE &&
        p.file <= MAX_FILE &&
        Number.isInteger(p.rank) &&
        p.rank >= MIN_RANK &&
        p.rank <= MAX_RANK,
    );
    if (inRange.length !== pieces.length) {
      warnings.push(
        `Ignored ${pieces.length - inRange.length} piece(s) with out-of-range coordinates.`,
      );
    }

    // 2. One piece per square — keep the most confident on a collision.
    const bySquare = new Map<string, BoardPiece>();
    let overlaps = 0;
    for (const p of inRange) {
      const key = `${p.file},${p.rank}`;
      const existing = bySquare.get(key);
      if (!existing) {
        bySquare.set(key, p);
      } else {
        overlaps++;
        if (conf(p) > conf(existing)) bySquare.set(key, p);
      }
    }
    if (overlaps > 0) {
      warnings.push(
        `Resolved ${overlaps} overlapping piece(s) on the same point (kept the most confident).`,
      );
    }

    // 3. Cap each side's per-type counts.
    const groups = new Map<string, BoardPiece[]>();
    for (const p of bySquare.values()) {
      const key = `${p.color}:${p.type}`;
      const group = groups.get(key);
      if (group) group.push(p);
      else groups.set(key, [p]);
    }
    const kept: BoardPiece[] = [];
    let trimmed = 0;
    for (const group of groups.values()) {
      const max = MAX_PER_TYPE[group[0].type];
      if (group.length <= max) {
        kept.push(...group);
      } else {
        const ranked = [...group].sort((a, b) => conf(b) - conf(a));
        kept.push(...ranked.slice(0, max));
        trimmed += group.length - max;
      }
    }
    if (trimmed > 0) {
      warnings.push(
        `Ignored ${trimmed} piece(s) beyond the legal count for their type (kept the most confident).`,
      );
    }

    return { pieces: kept, warnings };
  }

  /** Validate and throw a 400 BadRequest on any hard error. */
  validateOrThrow(pieces: BoardPiece[]): string[] {
    const { errors, warnings } = this.validate(pieces);
    if (errors.length > 0) {
      throw new BadRequestException({
        message: 'Invalid board state',
        code: 'INVALID_BOARD',
        details: errors,
      });
    }
    return warnings;
  }

  private checkRanges(pieces: BoardPiece[], errors: string[]): void {
    pieces.forEach((p, i) => {
      const fileOk = Number.isInteger(p.file) && p.file >= MIN_FILE && p.file <= MAX_FILE;
      const rankOk = Number.isInteger(p.rank) && p.rank >= MIN_RANK && p.rank <= MAX_RANK;
      if (!fileOk || !rankOk) {
        errors.push(
          `Piece ${i} (${p.color} ${p.type}) is out of range at file=${p.file}, rank=${p.rank}. ` +
            `Expected file ${MIN_FILE}..${MAX_FILE}, rank ${MIN_RANK}..${MAX_RANK}.`,
        );
      }
    });
  }

  private checkDuplicateSquares(pieces: BoardPiece[], errors: string[]): void {
    const seen = new Map<string, number>();
    pieces.forEach((p, i) => {
      const key = `${p.file},${p.rank}`;
      const prev = seen.get(key);
      if (prev !== undefined) {
        errors.push(
          `Duplicate square at file=${p.file}, rank=${p.rank}: pieces ${prev} and ${i} overlap.`,
        );
      } else {
        seen.set(key, i);
      }
    });
  }

  private checkKings(pieces: BoardPiece[], errors: string[], warnings: string[]): void {
    const redKings = pieces.filter((p) => p.type === 'king' && p.color === 'red').length;
    const blackKings = pieces.filter((p) => p.type === 'king' && p.color === 'black').length;

    if (redKings === 0) {
      errors.push('Missing Red king (general).');
    } else if (redKings > 1) {
      warnings.push(`Found ${redKings} Red kings; a legal board has exactly one.`);
    }

    if (blackKings === 0) {
      errors.push('Missing Black king (general).');
    } else if (blackKings > 1) {
      warnings.push(`Found ${blackKings} Black kings; a legal board has exactly one.`);
    }
  }

  private checkPerSideCounts(pieces: BoardPiece[], errors: string[]): void {
    const count = (color: PieceColor): number => pieces.filter((p) => p.color === color).length;
    (['red', 'black'] as PieceColor[]).forEach((color) => {
      const n = count(color);
      if (n > MAX_PIECES_PER_SIDE) {
        errors.push(`Too many ${color} pieces: ${n} (at most ${MAX_PIECES_PER_SIDE} per side).`);
      }
    });
  }
}
