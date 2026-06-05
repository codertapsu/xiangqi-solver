import { Injectable } from '@nestjs/common';
import { BoardPiece, NormalizedBoard, NormalizedPiece, SideToMove } from './xiangqi.types';

/**
 * Normalizes a validated board into a deterministic, ordered structure ready
 * for FEN conversion and serialization. Pure logic, no I/O.
 *
 * Responsibilities:
 *  - Deterministic ordering (rank desc, then file asc) so output is stable.
 *  - Project flat {file,rank} into nested { position: { file, rank } }.
 *  - Aggregate an overall confidence (mean of per-piece confidences).
 *  - Carry forward warnings (e.g. from the validator) plus its own.
 */
@Injectable()
export class BoardNormalizerService {
  normalize(
    pieces: BoardPiece[],
    sideToMove: SideToMove,
    incomingWarnings: string[] = [],
  ): NormalizedBoard {
    const warnings = [...incomingWarnings];

    // Stable ordering: top of board (Black home, rank 9) first, then by file.
    const sorted = [...pieces].sort((a, b) => {
      if (b.rank !== a.rank) return b.rank - a.rank;
      return a.file - b.file;
    });

    const normalizedPieces: NormalizedPiece[] = sorted.map((p) => ({
      type: p.type,
      color: p.color,
      position: { file: p.file, rank: p.rank },
      ...(typeof p.confidence === 'number' ? { confidence: p.confidence } : {}),
    }));

    const confidence = this.aggregateConfidence(pieces);

    if (sideToMove === 'unknown') {
      warnings.push('Side to move is unknown; defaulting engine analysis to Red to move.');
    }

    return {
      sideToMove,
      pieces: normalizedPieces,
      confidence,
      warnings,
    };
  }

  /** Mean of available per-piece confidences; 1 when none are provided. */
  private aggregateConfidence(pieces: BoardPiece[]): number {
    const values = pieces
      .map((p) => p.confidence)
      .filter((c): c is number => typeof c === 'number');
    if (values.length === 0) return 1;
    const mean = values.reduce((sum, c) => sum + c, 0) / values.length;
    return Math.round(mean * 1000) / 1000;
  }
}
