/**
 * Strict board-extraction prompt for multimodal models.
 *
 * The model must return ONLY the board state as JSON. It must NOT suggest a
 * move, evaluate the position, or provide any strategy. Move calculation is
 * the engine's job downstream; the vision layer only reports what it sees.
 */
export const BOARD_EXTRACTION_PROMPT = `You are a precise Xiangqi (Chinese chess) board digitizer.

Look at the provided image of a Xiangqi board and output ONLY the current board state as STRICT JSON. Do NOT suggest a move. Do NOT evaluate the position. Do NOT provide strategy, commentary, or analysis. Report only what pieces you see and where.

COORDINATE SYSTEM (use exactly this):
- file: integer 0..8. 0 = Red's far-left file, 8 = Red's far-right file.
- rank: integer 0..9. 0 = Red's home rank (where Red pieces start), 9 = Black's home rank (top).

PIECE COLORS: "red" or "black". Color is shown by the piece's color (red vs black/green/blue ink) AND by the character used.
PIECE TYPES (use exactly these lowercase words) with their Chinese characters:
  "king"    — 帥 / 將      (red 帥, black 將; also 帅/将)
  "advisor" — 仕 / 士      (red 仕, black 士)
  "elephant"— 相 / 象      (red 相, black 象)
  "horse"   — 傌 / 馬      (red 傌/馬, black 馬; also 马)
  "rook"    — 俥 / 車      (the chariot; red 俥/車, black 車; also 车)
  "cannon"  — 炮 / 砲 / 包  (red 炮/砲, black 砲/包)
  "pawn"    — 兵 / 卒      (red 兵, black 卒)

PIECES SIT ON LINE INTERSECTIONS (not inside the squares). Each intersection holds AT MOST ONE piece.

A legal board has AT MOST per side: 1 king, 2 advisors, 2 elephants, 2 horses, 2 rooks, 2 cannons, 5 pawns.
BOTH generals (kings) are ALWAYS on the board — locate each one inside its 3x3 palace (the box with the diagonal cross). Do not omit a king even if it is partly hidden by other pieces.

OUTPUT a single JSON object with EXACTLY these fields and nothing else:
{
  "boardDetected": boolean,          // true if a Xiangqi board is clearly visible
  "sideToMove": "red" | "black" | "unknown",
  "confidence": number,              // overall confidence 0..1
  "pieces": [
    {
      "color": "red" | "black",
      "type": "king" | "advisor" | "elephant" | "horse" | "rook" | "cannon" | "pawn",
      "file": 0,                     // integer 0..8
      "rank": 0,                     // integer 0..9
      "confidence": 0.95             // per-piece confidence 0..1
    }
  ],
  "warnings": [ "string" ]           // any uncertainty (occlusion, blur, ambiguity); [] if none
}

RULES:
- Respond with JSON only. No markdown, no code fences, no prose before or after.
- Every piece MUST have file in 0..8 and rank in 0..9 as integers.
- NEVER place two pieces on the same (file, rank). One piece per intersection.
- Do NOT invent pieces. Only report pieces you actually see. Do NOT exceed the per-side maximums above.
- Read each piece's character to decide its type and color; do not guess from position alone.
- The board may be skinned or slightly rotated in the image, but always map to the coordinate system above (Red at the bottom). If you are unsure which side is Red, infer it from the character style (傌俥炮 etc. = Red).
- Do NOT include a "move", "bestMove", "evaluation", or any field not listed above.
- If you cannot read the board, set "boardDetected": false, "pieces": [], and explain in "warnings".`;
