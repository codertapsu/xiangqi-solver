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

describe('parseVisionResponse — grid-first output (compact prompt)', () => {
  const START_GRID = [
    'rheakaehr',
    '.........',
    '.c.....c.',
    'p.p.p.p.p',
    '.........',
    '.........',
    'P.P.P.P.P',
    '.C.....C.',
    '.........',
    'RHEAKAEHR',
  ];

  it('expands a full 10x9 grid into canonical pieces (Red at the bottom)', () => {
    const result = parse({
      boardDetected: true,
      grid: START_GRID,
      redHomeAtTop: false,
      sideToMove: 'red',
      confidence: 0.97,
    });

    expect(result.pieces).toHaveLength(32);
    // Red back rank was the BOTTOM image row -> canonical rank 0.
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
    expect(find(result.pieces, 'black', 'king')).toMatchObject({ file: 4, rank: 9 });
    // Red cannon at image row 7 col 1 -> rank 2, file 1.
    expect(find(result.pieces, 'red', 'cannon')).toMatchObject({ file: 1, rank: 2 });
    // Per-piece confidence inherits the model's overall confidence.
    expect(result.pieces.every((p) => p.confidence === 0.97)).toBe(true);
  });

  it('rotates a grid with Red drawn at the top (Black perspective)', () => {
    const flipped = [...START_GRID].reverse();
    const result = parse({
      boardDetected: true,
      grid: flipped,
      redHomeAtTop: true,
      sideToMove: 'black',
      confidence: 0.9,
    });

    expect(result.pieces).toHaveLength(32);
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
    expect(find(result.pieces, 'black', 'king')).toMatchObject({ file: 4, rank: 9 });
  });

  it('derives orientation from the kings in the grid even when redHomeAtTop lies', () => {
    const flipped = [...START_GRID].reverse(); // Red actually at the top
    const result = parse({
      boardDetected: true,
      grid: flipped,
      redHomeAtTop: false, // wrong flag — kings must win
      sideToMove: 'red',
      confidence: 0.9,
    });
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
  });

  it('tolerates chess-style letter aliases (n=horse, b=elephant)', () => {
    const result = parse({
      boardDetected: true,
      grid: [
        'rnbakabnr',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        '.........',
        'RNBAKABNR',
      ],
      redHomeAtTop: false,
      sideToMove: 'red',
      confidence: 0.8,
    });
    expect(result.pieces.filter((p) => p.type === 'horse')).toHaveLength(4);
    expect(result.pieces.filter((p) => p.type === 'elephant')).toHaveLength(4);
  });

  it('prefers the grid over a stale pieces array when both are present', () => {
    const result = parse({
      boardDetected: true,
      grid: START_GRID,
      redHomeAtTop: false,
      sideToMove: 'red',
      confidence: 0.9,
      pieces: [{ color: 'red', type: 'king', row: 0, col: 0 }], // contradicts grid
    });
    expect(result.pieces).toHaveLength(32);
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
  });

  it('rejects a malformed grid with no pieces fallback', () => {
    expect(() =>
      parse({
        boardDetected: true,
        grid: ['too', 'short'],
        sideToMove: 'red',
        confidence: 0.9,
      }),
    ).toThrow(/malformed board grid/i);
  });

  it('falls back to the legacy pieces array when the grid has unknown letters', () => {
    const result = parse({
      boardDetected: true,
      grid: ['x........', ...START_GRID.slice(1)],
      sideToMove: 'red',
      confidence: 0.9,
      pieces: [
        { color: 'red', type: 'king', row: 9, col: 4 },
        { color: 'black', type: 'king', row: 0, col: 4 },
      ],
    });
    expect(result.pieces).toHaveLength(2);
    expect(find(result.pieces, 'red', 'king')).toMatchObject({ file: 4, rank: 0 });
  });

  it('an empty grid with boardDetected=false yields no pieces', () => {
    const result = parse({
      boardDetected: false,
      grid: [],
      sideToMove: 'unknown',
      confidence: 0,
      warnings: ['no board visible'],
    });
    expect(result.boardDetected).toBe(false);
    expect(result.pieces).toHaveLength(0);
  });
});
