import { BadRequestException } from '@nestjs/common';
import { BoardValidatorService } from './board-validator.service';
import { buildStartPosition } from './start-position';
import { BoardPiece } from './xiangqi.types';

const kings = (): BoardPiece[] => [
  { color: 'red', type: 'king', file: 4, rank: 0 },
  { color: 'black', type: 'king', file: 4, rank: 9 },
];

describe('BoardValidatorService', () => {
  let validator: BoardValidatorService;

  beforeEach(() => {
    validator = new BoardValidatorService();
  });

  it('accepts the standard start position with no errors', () => {
    const { errors } = validator.validate(buildStartPosition());
    expect(errors).toEqual([]);
  });

  it('rejects an empty board', () => {
    const { errors } = validator.validate([]);
    expect(errors.some((e) => /no pieces/i.test(e))).toBe(true);
  });

  it('flags out-of-range coordinates', () => {
    const pieces: BoardPiece[] = [
      ...kings(),
      { color: 'red', type: 'rook', file: 9, rank: 0 }, // file out of range
      { color: 'red', type: 'cannon', file: 0, rank: 10 }, // rank out of range
    ];
    const { errors } = validator.validate(pieces);
    expect(errors.some((e) => /out of range/i.test(e))).toBe(true);
    expect(errors.filter((e) => /out of range/i.test(e)).length).toBe(2);
  });

  it('flags duplicate squares', () => {
    const pieces: BoardPiece[] = [
      ...kings(),
      { color: 'red', type: 'rook', file: 1, rank: 1 },
      { color: 'red', type: 'cannon', file: 1, rank: 1 },
    ];
    const { errors } = validator.validate(pieces);
    expect(errors.some((e) => /duplicate square/i.test(e))).toBe(true);
  });

  it('flags a missing king', () => {
    const pieces: BoardPiece[] = [{ color: 'red', type: 'king', file: 4, rank: 0 }];
    const { errors } = validator.validate(pieces);
    expect(errors.some((e) => /missing black king/i.test(e))).toBe(true);
  });

  it('flags too many pieces (over 32 total)', () => {
    const tooMany: BoardPiece[] = [...kings()];
    for (let i = 0; i < 40; i++) {
      tooMany.push({ color: 'red', type: 'pawn', file: i % 9, rank: (i % 8) + 1 });
    }
    const { errors } = validator.validate(tooMany);
    expect(errors.some((e) => /too many pieces/i.test(e))).toBe(true);
  });

  it('flags too many pieces on a single side (over 16)', () => {
    const pieces: BoardPiece[] = [...kings()];
    // Add 16 more red pieces -> 17 red total.
    let added = 0;
    for (let rank = 1; rank <= 9 && added < 16; rank++) {
      for (let file = 0; file <= 8 && added < 16; file++) {
        pieces.push({ color: 'red', type: 'pawn', file, rank });
        added++;
      }
    }
    const { errors } = validator.validate(pieces);
    expect(errors.some((e) => /too many red pieces/i.test(e))).toBe(true);
  });

  it('warns (not errors) on multiple kings of one color', () => {
    const pieces: BoardPiece[] = [...kings(), { color: 'red', type: 'king', file: 3, rank: 0 }];
    const { errors, warnings } = validator.validate(pieces);
    expect(errors).toEqual([]);
    expect(warnings.some((w) => /2 Red kings/i.test(w))).toBe(true);
  });

  describe('validateOrThrow', () => {
    it('throws BadRequestException on hard errors', () => {
      expect(() => validator.validateOrThrow([])).toThrow(BadRequestException);
    });

    it('returns warnings (not throwing) when board is valid', () => {
      const warnings = validator.validateOrThrow(buildStartPosition());
      expect(Array.isArray(warnings)).toBe(true);
    });
  });

  describe('repair', () => {
    it('leaves a clean start position unchanged', () => {
      const start = buildStartPosition();
      const { pieces, warnings } = validator.repair(start);
      expect(pieces).toHaveLength(start.length);
      expect(warnings).toEqual([]);
    });

    it('resolves overlapping pieces, keeping the most confident', () => {
      const pieces: BoardPiece[] = [
        ...kings(),
        { color: 'red', type: 'rook', file: 0, rank: 0, confidence: 0.4 },
        { color: 'red', type: 'cannon', file: 0, rank: 0, confidence: 0.9 },
      ];
      const { pieces: repaired, warnings } = validator.repair(pieces);
      const atSquare = repaired.filter((p) => p.file === 0 && p.rank === 0);
      expect(atSquare).toHaveLength(1);
      expect(atSquare[0].type).toBe('cannon'); // higher confidence wins
      expect(warnings.some((w) => /overlapping/i.test(w))).toBe(true);
    });

    it('trims piece counts that exceed the per-type maximum', () => {
      const pieces: BoardPiece[] = [
        ...kings(),
        { color: 'red', type: 'cannon', file: 1, rank: 2, confidence: 0.9 },
        { color: 'red', type: 'cannon', file: 7, rank: 2, confidence: 0.8 },
        { color: 'red', type: 'cannon', file: 5, rank: 2, confidence: 0.2 }, // 3rd cannon
      ];
      const { pieces: repaired, warnings } = validator.repair(pieces);
      const cannons = repaired.filter((p) => p.color === 'red' && p.type === 'cannon');
      expect(cannons).toHaveLength(2);
      expect(cannons.find((c) => c.file === 5)).toBeUndefined(); // lowest-confidence dropped
      expect(warnings.some((w) => /beyond the legal count/i.test(w))).toBe(true);
    });

    it('drops out-of-range pieces', () => {
      const pieces: BoardPiece[] = [...kings(), { color: 'red', type: 'pawn', file: 99, rank: 3 }];
      const { pieces: repaired, warnings } = validator.repair(pieces);
      expect(repaired).toHaveLength(2);
      expect(warnings.some((w) => /out-of-range/i.test(w))).toBe(true);
    });
  });
});
