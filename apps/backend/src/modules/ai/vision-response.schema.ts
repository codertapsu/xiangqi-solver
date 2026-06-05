import { z } from 'zod';
import { ExtractBoardStateResult } from './ai-provider.interface';
import { BoardPiece } from '../board/xiangqi.types';

/**
 * Zod schema validating the strict JSON returned by a vision model. Shared by
 * the Gemini and OpenAI providers so both parse identically.
 *
 * The model reports each piece by IMAGE position (`row`/`col`, 0 = top/left)
 * plus a `redHomeAtTop` flag; [parseVisionResponse] rotates that to canonical
 * engine coordinates (`file`/`rank`, rank 0 = Red home) deterministically. Old
 * `file`/`rank` output is still accepted (treated as already-canonical) so the
 * change is backward compatible.
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
  redHomeAtTop: z.boolean().optional(),
  sideToMove: z.enum(['red', 'black', 'unknown']).default('unknown'),
  confidence: z.number().min(0).max(1).default(0.5),
  pieces: z.array(visionPieceSchema).default([]),
  warnings: z.array(z.string()).default([]),
});

type VisionResponse = z.infer<typeof visionResponseSchema>;
type VisionPiece = z.infer<typeof visionPieceSchema>;

/**
 * Strip optional markdown code fences (```json ... ```) before JSON.parse,
 * since multimodal models often wrap JSON despite instructions.
 */
export function stripCodeFences(text: string): string {
  const trimmed = text.trim();
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return (fenceMatch ? fenceMatch[1] : trimmed).trim();
}

/**
 * Decide whether the RED army is at the TOP of the image. The kings are a hard
 * invariant (each sits in its own palace on its home half), so when both are
 * present we derive orientation from them and ignore a possibly-wrong model
 * flag. Otherwise fall back to the model's `redHomeAtTop`, else `false`.
 */
function resolveRedHomeAtTop(data: VisionResponse): boolean {
  const visual = data.pieces.filter((p) => p.row !== undefined && p.col !== undefined);
  const redKing = visual.find((p) => p.color === 'red' && p.type === 'king');
  const blackKing = visual.find((p) => p.color === 'black' && p.type === 'king');
  if (redKing && blackKing) return (redKing.row as number) < (blackKing.row as number);
  return data.redHomeAtTop ?? false;
}

/** Rotate one image-space piece to canonical engine coordinates. */
function toCanonical(piece: VisionPiece, redHomeAtTop: boolean): { file: number; rank: number } {
  if (piece.row !== undefined && piece.col !== undefined) {
    return redHomeAtTop
      ? { rank: piece.row, file: 8 - piece.col }
      : { rank: 9 - piece.row, file: piece.col };
  }
  // Legacy already-canonical coordinates.
  return { file: piece.file as number, rank: piece.rank as number };
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

  const redHomeAtTop = resolveRedHomeAtTop(parsed.data);
  const pieces: BoardPiece[] = parsed.data.pieces.map((p) => {
    const { file, rank } = toCanonical(p, redHomeAtTop);
    return { color: p.color, type: p.type, file, rank, confidence: p.confidence };
  });

  return {
    boardDetected: parsed.data.boardDetected,
    sideToMove: parsed.data.sideToMove,
    confidence: parsed.data.confidence,
    pieces,
    warnings: parsed.data.warnings,
  };
}
