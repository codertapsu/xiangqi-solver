import { ConfigService } from '@nestjs/config';
import { EngineService } from './engine.service';
import { MockEngineService } from './mock-engine.service';
import { PikafishEngineService } from './pikafish-engine.service';
import { EngineBestMoveInput, EngineBestMoveResult } from './engine.interface';

const FEN = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1';

function buildConfig(engine: Record<string, unknown> = { provider: 'pikafish' }): ConfigService {
  return {
    get: (key: string) => (key === 'app.engine' ? engine : undefined),
  } as unknown as ConfigService;
}

/** Pikafish stand-in that counts real searches. */
class CountingEngine {
  readonly name = 'pikafish';
  calls = 0;

  async getBestMove(input: EngineBestMoveInput): Promise<EngineBestMoveResult> {
    this.calls++;
    return {
      uci: 'b2e2',
      from: { file: 1, rank: 2 },
      to: { file: 4, rank: 2 },
      score: '+0.42',
      depth: input.depth,
      raw: 'bestmove b2e2',
    };
  }
}

describe('EngineService result cache', () => {
  let counting: CountingEngine;
  let service: EngineService;

  beforeEach(() => {
    counting = new CountingEngine();
    service = new EngineService(
      buildConfig(),
      new MockEngineService(),
      counting as unknown as PikafishEngineService,
    );
  });

  const input: EngineBestMoveInput = {
    fen: FEN,
    sideToMove: 'red',
    depth: 12,
    moveTimeMs: 1000,
  };

  it('memoizes identical position+limits queries', async () => {
    const first = await service.getBestMove(input);
    const second = await service.getBestMove(input);
    expect(counting.calls).toBe(1);
    expect(second).toEqual(first);
    // Cached results are cloned: mutating one response must not poison the next.
    second.score = 'tampered';
    const third = await service.getBestMove(input);
    expect(third.score).toBe('+0.42');
  });

  it('different search limits are different cache entries', async () => {
    await service.getBestMove(input);
    await service.getBestMove({ ...input, depth: 14 });
    await service.getBestMove({ ...input, multiPv: 3 });
    expect(counting.calls).toBe(3);
  });

  it('failures are not cached', async () => {
    const failing = {
      name: 'pikafish',
      calls: 0,
      async getBestMove(): Promise<EngineBestMoveResult> {
        this.calls++;
        throw new Error('engine down');
      },
    };
    const svc = new EngineService(
      buildConfig(),
      new MockEngineService(),
      failing as unknown as PikafishEngineService,
    );
    await expect(svc.getBestMove(input)).rejects.toThrow('engine down');
    await expect(svc.getBestMove(input)).rejects.toThrow('engine down');
    expect(failing.calls).toBe(2);
  });
});

describe('EngineService provider enforcement', () => {
  const pikafishStub = {
    name: 'pikafish',
    async getBestMove() {
      return {} as EngineBestMoveResult;
    },
  } as unknown as PikafishEngineService;

  it('honors the client engineProvider when enforce is off', () => {
    const svc = new EngineService(
      buildConfig({ provider: 'pikafish', providerEnforce: false }),
      new MockEngineService(),
      pikafishStub,
    );
    expect(svc.effectiveProviderName('mock')).toBe('mock');
    expect(svc.resolve('mock').name).toBe('mock');
  });

  it('ignores the client engineProvider and uses the default when enforce is on', () => {
    const svc = new EngineService(
      buildConfig({ provider: 'pikafish', providerEnforce: true }),
      new MockEngineService(),
      pikafishStub,
    );
    expect(svc.effectiveProviderName('mock')).toBe('pikafish');
    expect(svc.resolve('mock').name).toBe('pikafish');
  });
});
