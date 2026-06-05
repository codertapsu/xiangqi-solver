import { z } from 'zod';
import { ExtractBoardStateResult } from './ai-provider.interface';

/**
 * Zod schema validating the strict JSON returned by a vision model. Shared by
 * the Gemini and OpenAI providers so both parse identically.
 */
export const visionPieceSchema = z.object({
  color: z.enum(['red', 'black']),
  type: z.enum(['king', 'advisor', 'elephant', 'horse', 'rook', 'cannon', 'pawn']),
  file: z.number().int().min(0).max(8),
  rank: z.number().int().min(0).max(9),
  confidence: z.number().min(0).max(1).optional(),
});

export const visionResponseSchema = z.object({
  boardDetected: z.boolean(),
  sideToMove: z.enum(['red', 'black', 'unknown']).default('unknown'),
  confidence: z.number().min(0).max(1).default(0.5),
  pieces: z.array(visionPieceSchema).default([]),
  warnings: z.array(z.string()).default([]),
});

/**
 * Strip optional markdown code fences (```json ... ```) before JSON.parse,
 * since multimodal models often wrap JSON despite instructions.
 */
export function stripCodeFences(text: string): string {
  const trimmed = text.trim();
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return (fenceMatch ? fenceMatch[1] : trimmed).trim();
}

/** Parse + validate a raw model text response into a typed result. */
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
  return parsed.data;
}
