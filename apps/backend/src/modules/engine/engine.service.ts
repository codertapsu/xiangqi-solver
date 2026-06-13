import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import { LruCache } from '../../common/utils/lru-cache';
import { EngineBestMoveInput, EngineBestMoveResult, XiangqiEngine } from './engine.interface';
import { MockEngineService } from './mock-engine.service';
import { PikafishEngineService } from './pikafish-engine.service';

export type EngineProviderName = 'pikafish' | 'mock';

/** Positions repeat (openings, retry taps, vision-cache hits): memoizing the
 *  deterministic search result makes those solves instant. */
const ENGINE_CACHE_ENTRIES = 500;

/**
 * Facade that selects the active engine implementation by name and exposes a
 * single getBestMove entry point. Defaults to the configured ENGINE_PROVIDER
 * when no explicit provider is requested. Successful results are memoized by
 * (provider, FEN, search limits) in a small LRU.
 */
@Injectable()
export class EngineService {
  private readonly cache = new LruCache<EngineBestMoveResult>(ENGINE_CACHE_ENTRIES);

  constructor(
    private readonly config: ConfigService,
    private readonly mockEngine: MockEngineService,
    private readonly pikafishEngine: PikafishEngineService,
  ) {}

  /** Resolve the configured default provider name. */
  get defaultProvider(): EngineProviderName {
    return this.config.get<AppConfig['engine']>('app.engine')?.provider ?? 'mock';
  }

  /**
   * The engine that WILL run after applying enforcement: when
   * ENGINE_PROVIDER_ENFORCE is set the client's choice is ignored and the
   * configured default wins. Used for selection and the response envelope.
   */
  effectiveProviderName(provider?: EngineProviderName): EngineProviderName {
    const enforce = this.config.get<AppConfig['engine']>('app.engine')?.providerEnforce ?? false;
    return (enforce ? undefined : provider) ?? this.defaultProvider;
  }

  /** Pick an engine implementation by name. */
  resolve(provider?: EngineProviderName): XiangqiEngine {
    const name = this.effectiveProviderName(provider);
    switch (name) {
      case 'mock':
        return this.mockEngine;
      case 'pikafish':
        return this.pikafishEngine;
      default:
        throw new BadRequestException({
          message: `Unknown engine provider "${String(name)}". Use "pikafish" or "mock".`,
          code: 'UNKNOWN_ENGINE_PROVIDER',
        });
    }
  }

  /** Run a best-move query against the selected engine (memoized). */
  async getBestMove(
    input: EngineBestMoveInput,
    provider?: EngineProviderName,
  ): Promise<EngineBestMoveResult> {
    const engine = this.resolve(provider);
    const key = [
      engine.name,
      input.fen,
      input.depth,
      input.moveTimeMs,
      input.threads ?? '',
      input.hashMb ?? '',
      input.multiPv ?? '',
    ].join('|');
    const hit = this.cache.get(key);
    if (hit) return structuredClone(hit);

    const result: EngineBestMoveResult = { ...(await engine.getBestMove(input)) };
    // The raw UCI transcript is debug-only (nothing downstream reads it) and
    // can reach hundreds of KB per long search — never hold it in the cache
    // or return it from the facade.
    delete result.raw;
    this.cache.set(key, structuredClone(result));
    return result;
  }
}
