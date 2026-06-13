import { z } from 'zod';
import { ExtractBoardStateResult } from './ai-provider.interface';
import { BoardPiece, PieceColor, PieceType } from '../board/xiangqi.types';

/**
 * Zod schema validating the strict JSON returned by a vision model. Shared by
 * the Gemini and OpenAI providers so both parse identically.
 *
 * The model reports the board as a compact 10x9 `grid` (image orientation,
 * first row = top of image) plus a `redHomeAtTop` flag; [parseVisionResponse]
 * expands the grid to pieces and rotates to canonical engine coordinates
 * (`file`/`rank`, rank 0 = Red home) deterministically. The grid is the
 * authoritative output (one char per intersection — duplicates are impossible
 * and completion stays ~4x smaller than a per-piece JSON array, which is the
 * dominant share of vision latency). Older outputs are still accepted: a
 * `pieces` array of image-space `row`/`col` entries, or legacy canonical
 * `file`/`rank` entries.
 */
export const visionPieceSchema = z
  .object({
    color: z.enum(['red', 'black']),
    type: z.enum(['king', 'advisor', 'elephant', 'horse', 'rook', 'cannon', 'pawn']),
    // Preferred: image-relative grid position.
    row: z.number().int().min(0).max(9).optional(),
    col: z.number().int().min(0).max(8).optional(),
    // Legacy: already-canonical coordinates (accepted as a fallback).
    file: z.number().int().min(0).max(8).optional(),
    rank: z.number().int().min(0).max(9).optional(),
    confidence: z.number().min(0).max(1).optional(),
  })
  .refine(
    (p) =>
      (p.row !== undefined && p.col !== undefined) ||
      (p.file !== undefined && p.rank !== undefined),
    { message: 'piece must have row+col (preferred) or file+rank' },
  );

export const visionResponseSchema = z.object({
  boardDetected: z.boolean(),
  // nullish: a model answering "grid": null must degrade like a missing grid,
  // not 400 the whole response.
  grid: z.array(z.string()).nullish(),
  redHomeAtTop: z.boolean().optional(),
  sideToMove: z.enum(['red', 'black', 'unknown']).default('unknown'),
  confidence: z.number().min(0).max(1).default(0.5),
  pieces: z.array(visionPieceSchema).default([]),
  warnings: z.array(z.string()).default([]),
});

type VisionResponse = z.infer<typeof visionResponseSchema>;

/** Image-space piece (row 0 = top of image) before canonical rotation. */
interface ImagePiece {
  color: PieceColor;
  type: PieceType;
  row: number;
  col: number;
  confidence?: number;
}

/** Grid letter -> piece type (case carries the color). */
const LETTER_TO_TYPE: Record<string, PieceType> = {
  k: 'king',
  a: 'advisor',
  e: 'elephant',
  h: 'horse',
  r: 'rook',
  c: 'cannon',
  p: 'pawn',
  // Tolerated aliases some models emit despite the prompt (chess-style FEN):
  // n(knight)=horse, b(bishop)=elephant.
  n: 'horse',
  b: 'elephant',
};

/**
 * Strip optional markdown code fences (```json ... ```) before JSON.parse,
 * since multimodal models often wrap JSON despite instructions.
 */
export function stripCodeFences(text: string): string {
  const trimmed = text.trim();
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return (fenceMatch ? fenceMatch[1] : trimmed).trim();
}

/** Expand FEN-style digit runs ("2p2c3" -> "..p..c...") some models emit. */
function expandDigitRuns(line: string): string {
  return line.replace(/[1-9]/g, (d) => '.'.repeat(Number(d)));
}

/**
 * Expand a 10x9 grid into image-space pieces. Returns null when the grid is
 * absent or malformed (wrong row count/length, unknown letters) so the caller
 * can fall back to the legacy `pieces` array. Per-piece confidence inherits
 * the model's overall confidence — the grid has no per-cell signal.
 */
function piecesFromGrid(
  grid: string[] | null | undefined,
  confidence: number,
): ImagePiece[] | null {
  if (!grid || grid.length !== 10) return null;
  const pieces: ImagePiece[] = [];
  for (let row = 0; row < 10; row++) {
    const line = expandDigitRuns(grid[row].trim());
    if (line.length !== 9) return null;
    for (let col = 0; col < 9; col++) {
      const ch = line[col];
      if (ch === '.' || ch === '-' || ch === ' ') continue;
      const type = LETTER_TO_TYPE[ch.toLowerCase()];
      if (!type) return null;
      pieces.push({
        color: ch === ch.toUpperCase() ? 'red' : 'black',
        type,
        row,
        col,
        confidence,
      });
    }
  }
  return pieces;
}

/** Legacy path: the model emitted a per-piece array instead of (or with) a grid. */
function piecesFromArray(data: VisionResponse): {
  imagePieces: ImagePiece[];
  canonical: BoardPiece[];
} {
  const imagePieces: ImagePiece[] = [];
  const canonical: BoardPiece[] = [];
  for (const p of data.pieces) {
    if (p.row !== undefined && p.col !== undefined) {
      imagePieces.push({
        color: p.color,
        type: p.type,
        row: p.row,
        col: p.col,
        confidence: p.confidence,
      });
    } else {
      // Already-canonical coordinates pass through without rotation.
      canonical.push({
        color: p.color,
        type: p.type,
        file: p.file as number,
        rank: p.rank as number,
        confidence: p.confidence,
      });
    }
  }
  return { imagePieces, canonical };
}

/**
 * Decide whether the RED army is at the TOP of the image. The kings are a hard
 * invariant (each sits in its own palace on its home half), so when both are
 * present we derive orientation from them and ignore a possibly-wrong model
 * flag. Otherwise fall back to the model's `redHomeAtTop`, else `false`.
 */
function resolveRedHomeAtTop(imagePieces: ImagePiece[], modelFlag: boolean | undefined): boolean {
  const redKing = imagePieces.find((p) => p.color === 'red' && p.type === 'king');
  const blackKing = imagePieces.find((p) => p.color === 'black' && p.type === 'king');
  if (redKing && blackKing) return redKing.row < blackKing.row;
  return modelFlag ?? false;
}

/** Rotate one image-space piece to canonical engine coordinates. */
function toCanonical(piece: ImagePiece, redHomeAtTop: boolean): BoardPiece {
  const { file, rank } = redHomeAtTop
    ? { rank: piece.row, file: 8 - piece.col }
    : { rank: 9 - piece.row, file: piece.col };
  return { color: piece.color, type: piece.type, file, rank, confidence: piece.confidence };
}

/** Parse + validate a raw model text response into a typed, canonical result. */
export function parseVisionResponse(rawText: string): ExtractBoardStateResult {
  const cleaned = stripCodeFences(rawText);
  let json: unknown;
  try {
    json = JSON.parse(cleaned);
  } catch {
    throw new Error('Vision provider returned non-JSON output.');
  }
  const parsed = visionResponseSchema.safeParse(json);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`)
      .join('; ');
    throw new Error(`Vision provider returned invalid board JSON: ${issues}`);
  }
  const data = parsed.data;

  // Preferred: expand the authoritative grid. Fallback: the legacy pieces array.
  const warnings = [...data.warnings];
  let imagePieces = piecesFromGrid(data.grid, data.confidence);
  let canonicalPassthrough: BoardPiece[] = [];
  if (imagePieces === null) {
    if (data.grid != null && data.grid.length > 0 && data.pieces.length === 0) {
      throw new Error(
        'Vision provider returned a malformed board grid (expected 10 rows of 9 cells).',
      );
    }
    const legacy = piecesFromArray(data);
    imagePieces = legacy.imagePieces;
    canonicalPassthrough = legacy.canonical;
  }

  const redHomeAtTop = resolveRedHomeAtTop(imagePieces, data.redHomeAtTop);
  const pieces: BoardPiece[] = [
    ...imagePieces.map((p) => toCanonical(p, redHomeAtTop)),
    ...canonicalPassthrough,
  ];

  return {
    boardDetected: data.boardDetected,
    sideToMove: data.sideToMove,
    confidence: data.confidence,
    pieces,
    warnings,
  };
}
