import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PikafishEngineService } from './pikafish-engine.service';
import { AppConfig } from '../../config/configuration';

/** Build a ConfigService stub returning the given engine config. */
function configWith(engine: Partial<AppConfig['engine']>): ConfigService {
  return {
    get: (key: string) => {
      if (key === 'app.engine') {
        return {
          provider: 'pikafish',
          pikafishBinaryPath: '',
          defaultDepth: 12,
          defaultMoveTimeMs: 1000,
          ...engine,
        };
      }
      return undefined;
    },
  } as unknown as ConfigService;
}

describe('PikafishEngineService', () => {
  it('throws a clear ServiceUnavailable error when the binary path is empty', async () => {
    const engine = new PikafishEngineService(configWith({ pikafishBinaryPath: '' }));
    await expect(
      engine.getBestMove({
        fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
        sideToMove: 'red',
        depth: 12,
        moveTimeMs: 1000,
      }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('throws when the configured binary file does not exist', async () => {
    const engine = new PikafishEngineService(
      configWith({ pikafishBinaryPath: '/nonexistent/path/to/pikafish-binary-xyz' }),
    );
    await expect(
      engine.getBestMove({
        fen: 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1',
        sideToMove: 'red',
        depth: 12,
        moveTimeMs: 1000,
      }),
    ).rejects.toThrow(/not found/i);
  });

  it('exposes a stable provider name', () => {
    const engine = new PikafishEngineService(configWith({}));
    expect(engine.name).toBe('pikafish');
  });
});
