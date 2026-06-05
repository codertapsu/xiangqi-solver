import { MockEngineService } from './mock-engine.service';
import { EngineBestMoveInput } from './engine.interface';

const baseInput = (overrides: Partial<EngineBestMoveInput> = {}): EngineBestMoveInput => ({
  fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
  sideToMove: 'red',
  depth: 12,
  moveTimeMs: 1000,
  ...overrides,
});

describe('MockEngineService', () => {
  let engine: MockEngineService;

  beforeEach(() => {
    engine = new MockEngineService();
  });

  it('returns the deterministic Red move b2e2', async () => {
    const result = await engine.getBestMove(baseInput({ sideToMove: 'red' }));
    expect(result.uci).toBe('b2e2');
    expect(result.from).toEqual({ file: 1, rank: 2 });
    expect(result.to).toEqual({ file: 4, rank: 2 });
    expect(result.score).toBe('+0.30');
  });

  it('returns the deterministic Black move b7e7', async () => {
    const result = await engine.getBestMove(baseInput({ sideToMove: 'black' }));
    expect(result.uci).toBe('b7e7');
    expect(result.from).toEqual({ file: 1, rank: 7 });
    expect(result.to).toEqual({ file: 4, rank: 7 });
  });

  it('defaults to the Red move when side is unknown', async () => {
    const result = await engine.getBestMove(baseInput({ sideToMove: 'unknown' }));
    expect(result.uci).toBe('b2e2');
  });

  it('echoes the requested depth', async () => {
    const result = await engine.getBestMove(baseInput({ depth: 20 }));
    expect(result.depth).toBe(20);
  });

  it('is fully deterministic across repeated calls', async () => {
    const a = await engine.getBestMove(baseInput());
    const b = await engine.getBestMove(baseInput());
    expect(a).toEqual(b);
  });

  it('exposes a stable provider name', () => {
    expect(engine.name).toBe('mock');
  });
});
