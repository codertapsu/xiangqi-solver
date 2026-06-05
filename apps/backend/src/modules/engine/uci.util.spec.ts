import {
  columnToFile,
  fileToColumn,
  moveToHuman,
  moveToUci,
  positionToHuman,
  squareToPosition,
  uciToMove,
} from './uci.util';

describe('uci.util', () => {
  it('maps file indices to column letters a..i', () => {
    expect(fileToColumn(0)).toBe('a');
    expect(fileToColumn(1)).toBe('b');
    expect(fileToColumn(4)).toBe('e');
    expect(fileToColumn(8)).toBe('i');
  });

  it('maps column letters back to file indices', () => {
    expect(columnToFile('a')).toBe(0);
    expect(columnToFile('i')).toBe(8);
  });

  it('builds the example UCI move b2b7', () => {
    expect(moveToUci({ file: 1, rank: 2 }, { file: 1, rank: 7 })).toBe('b2b7');
  });

  it('round-trips a UCI move', () => {
    const move = uciToMove('b2b7');
    expect(move.from).toEqual({ file: 1, rank: 2 });
    expect(move.to).toEqual({ file: 1, rank: 7 });
  });

  it('parses a single UCI square', () => {
    expect(squareToPosition('e4')).toEqual({ file: 4, rank: 4 });
  });

  it('produces human labels UPPER(col)+(rank+1)', () => {
    expect(positionToHuman({ file: 1, rank: 2 })).toBe('B3');
    expect(positionToHuman({ file: 1, rank: 7 })).toBe('B8');
  });

  it('produces the example human move text "B3 to B8"', () => {
    expect(moveToHuman({ file: 1, rank: 2 }, { file: 1, rank: 7 })).toBe('B3 to B8');
  });

  it('throws on out-of-range file', () => {
    expect(() => fileToColumn(9)).toThrow();
  });

  it('throws on malformed UCI move', () => {
    expect(() => uciToMove('zz99')).toThrow();
    expect(() => uciToMove('b2b')).toThrow();
  });
});
