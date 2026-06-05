import { parseVisionResponse } from './vision-response.schema';

/** Convenience: parse a board object (as the model would return it). */
function parse(obj: unknown) {
  return parseVisionResponse(JSON.stringify(obj));
}

const find = (
  pieces: { color: string; type: string; file: number; rank: number }[],
  color: string,
  type: string,
) => pieces.find((p) => p.color === color && p.type === type)!;

describe('parseVisionResponse — orientation normalization', () => {
  it('rotates a Black-perspective board (Red drawn at the top) to canonical coords', () => {
    const result = parse({
      boardDetected: true,
      redHomeAtTop: true,
      sideToMove: 'black',
      pieces: [
        { color: 'red', type: 'king', row: 0, col: 4 },
        { color: 'black', type: 'king', row: 9, col: 4 },
        { color: 'red', type: 'cannon', row: 2, col: 7 },
      ],
    });

    // Red general must land on its home rank 0; black on rank 9.
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
    expect(find(result.pieces, 'black', 'king')).toMatchObject({ file: 4, rank: 9 });
    // cannon row2/col7 -> rank 2, file 8-7 = 1.
    expect(find(result.pieces, 'red', 'cannon')).toMatchObject({ file: 1, rank: 2 });
  });

  it('maps a standard board (Red at the bottom) to the SAME canonical board', () => {
    const result = parse({
      boardDetected: true,
      sideToMove: 'red',
      pieces: [
        { color: 'red', type: 'king', row: 9, col: 4 },
        { color: 'black', type: 'king', row: 0, col: 4 },
        { color: 'red', type: 'cannon', row: 7, col: 1 },
      ],
    });

    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
    expect(find(result.pieces, 'black', 'king')).toMatchObject({ file: 4, rank: 9 });
    expect(find(result.pieces, 'red', 'cannon')).toMatchObject({ file: 1, rank: 2 });
  });

  it('derives orientation from the kings even when redHomeAtTop is wrong', () => {
    const result = parse({
      boardDetected: true,
      redHomeAtTop: false, // WRONG — the kings show Red is at the top
      sideToMove: 'black',
      pieces: [
        { color: 'red', type: 'king', row: 0, col: 4 },
        { color: 'black', type: 'king', row: 9, col: 4 },
      ],
    });
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ rank: 0 });
  });

  it('falls back to the redHomeAtTop flag when a king is missing', () => {
    const result = parse({
      boardDetected: true,
      redHomeAtTop: true,
      sideToMove: 'black',
      pieces: [{ color: 'red', type: 'cannon', row: 2, col: 7 }],
    });
    // With redHomeAtTop=true: rank = row = 2, file = 8 - 7 = 1.
    expect(result.pieces[0]).toMatchObject({ file: 1, rank: 2 });
  });

  it('accepts legacy canonical file/rank unchanged (backward compatible)', () => {
    const result = parse({
      boardDetected: true,
      sideToMove: 'red',
      pieces: [
        { color: 'red', type: 'cannon', file: 1, rank: 2 },
        { color: 'black', type: 'king', file: 4, rank: 9 },
      ],
    });
    expect(find(result.pieces, 'red', 'cannon')).toMatchObject({ file: 1, rank: 2 });
    expect(find(result.pieces, 'black', 'king')).toMatchObject({ file: 4, rank: 9 });
  });

  it('rejects a piece with neither row/col nor file/rank', () => {
    expect(() => parse({ boardDetected: true, pieces: [{ color: 'red', type: 'king' }] })).toThrow(
      /invalid board JSON/i,
    );
  });
});
