import { BoardNormalizerService } from './board-normalizer.service';
import { BoardPiece } from './xiangqi.types';

describe('BoardNormalizerService', () => {
  let normalizer: BoardNormalizerService;

  beforeEach(() => {
    normalizer = new BoardNormalizerService();
  });

  it('sorts pieces by rank descending then file ascending', () => {
    const pieces: BoardPiece[] = [
      { color: 'red', type: 'rook', file: 5, rank: 0 },
      { color: 'black', type: 'rook', file: 1, rank: 9 },
      { color: 'red', type: 'cannon', file: 1, rank: 0 },
      { color: 'black', type: 'cannon', file: 0, rank: 9 },
    ];
    const board = normalizer.normalize(pieces, 'red');
    const order = board.pieces.map((p) => `${p.position.rank}:${p.position.file}`);
    expect(order).toEqual(['9:0', '9:1', '0:1', '0:5']);
  });

  it('projects flat file/rank into nested position', () => {
    const board = normalizer.normalize(
      [{ color: 'red', type: 'king', file: 4, rank: 0, confidence: 0.8 }],
      'red',
    );
    expect(board.pieces[0]).toEqual({
      type: 'king',
      color: 'red',
      position: { file: 4, rank: 0 },
      confidence: 0.8,
    });
  });

  it('aggregates confidence as the mean of provided values', () => {
    const board = normalizer.normalize(
      [
        { color: 'red', type: 'king', file: 4, rank: 0, confidence: 0.8 },
        { color: 'black', type: 'king', file: 4, rank: 9, confidence: 0.6 },
      ],
      'red',
    );
    expect(board.confidence).toBeCloseTo(0.7, 5);
  });

  it('defaults confidence to 1 when no per-piece confidence is given', () => {
    const board = normalizer.normalize([{ color: 'red', type: 'king', file: 4, rank: 0 }], 'red');
    expect(board.confidence).toBe(1);
  });

  it('adds a warning when side to move is unknown', () => {
    const board = normalizer.normalize(
      [{ color: 'red', type: 'king', file: 4, rank: 0 }],
      'unknown',
    );
    expect(board.warnings.some((w) => /side to move is unknown/i.test(w))).toBe(true);
  });

  it('carries forward incoming warnings', () => {
    const board = normalizer.normalize([{ color: 'red', type: 'king', file: 4, rank: 0 }], 'red', [
      'from validator',
    ]);
    expect(board.warnings).toContain('from validator');
  });

  it('does not mutate the input array', () => {
    const pieces: BoardPiece[] = [
      { color: 'red', type: 'rook', file: 5, rank: 0 },
      { color: 'black', type: 'rook', file: 1, rank: 9 },
    ];
    const snapshot = JSON.stringify(pieces);
    normalizer.normalize(pieces, 'red');
    expect(JSON.stringify(pieces)).toBe(snapshot);
  });
});
