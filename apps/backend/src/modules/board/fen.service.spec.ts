import { FenService } from './fen.service';
import { BoardNormalizerService } from './board-normalizer.service';
import { buildStartPosition } from './start-position';
import { START_POSITION_FEN } from './xiangqi.types';

describe('FenService', () => {
  let fen: FenService;
  let normalizer: BoardNormalizerService;

  beforeEach(() => {
    fen = new FenService();
    normalizer = new BoardNormalizerService();
  });

  it('produces the canonical start-position FEN exactly (Red to move)', () => {
    const board = normalizer.normalize(buildStartPosition(), 'red');
    expect(fen.toFen(board.pieces, 'red')).toBe(START_POSITION_FEN);
  });

  it('uses "w" for Red to move and "b" for Black to move', () => {
    const board = normalizer.normalize(buildStartPosition(), 'black');
    const result = fen.toFen(board.pieces, 'black');
    expect(result.split(' ')[1]).toBe('b');
    expect(result.startsWith('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR')).toBe(
      true,
    );
  });

  it('defaults unknown side to "w" (Red)', () => {
    const board = normalizer.normalize(buildStartPosition(), 'unknown');
    expect(fen.toFen(board.pieces, 'unknown').split(' ')[1]).toBe('w');
  });

  it('collapses empty files into digits and orders ranks 9..0', () => {
    // A single Red king on file 4, rank 0 (Red home center).
    const board = normalizer.normalize([{ color: 'red', type: 'king', file: 4, rank: 0 }], 'red');
    const placement = fen.toFen(board.pieces, 'red').split(' ')[0];
    // 9 empty ranks of "9", then the king rank "4K4".
    expect(placement).toBe('9/9/9/9/9/9/9/9/9/4K4');
  });

  it('writes Red as uppercase and Black as lowercase letters', () => {
    const board = normalizer.normalize(
      [
        { color: 'red', type: 'rook', file: 0, rank: 0 },
        { color: 'black', type: 'rook', file: 8, rank: 9 },
      ],
      'red',
    );
    const placement = fen.toFen(board.pieces, 'red').split(' ')[0];
    // rank 9 first: black rook on file 8 -> "8r"; rank 0 last: red rook file 0 -> "R8".
    expect(placement.startsWith('8r/')).toBe(true);
    expect(placement.endsWith('/R8')).toBe(true);
  });
});
