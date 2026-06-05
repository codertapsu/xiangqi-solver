import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import { EngineBestMoveInput, EngineBestMoveResult, XiangqiEngine } from './engine.interface';
import { MockEngineService } from './mock-engine.service';
import { PikafishEngineService } from './pikafish-engine.service';

export type EngineProviderName = 'pikafish' | 'mock';

/**
 * Facade that selects the active engine implementation by name and exposes a
 * single getBestMove entry point. Defaults to the configured ENGINE_PROVIDER
 * when no explicit provider is requested.
 */
@Injectable()
export class EngineService {
  constructor(
    private readonly config: ConfigService,
    private readonly mockEngine: MockEngineService,
    private readonly pikafishEngine: PikafishEngineService,
  ) {}

  /** Resolve the configured default provider name. */
  get defaultProvider(): EngineProviderName {
    return this.config.get<AppConfig['engine']>('app.engine')?.provider ?? 'mock';
  }

  /** Pick an engine implementation by name. */
  resolve(provider?: EngineProviderName): XiangqiEngine {
    const name = provider ?? this.defaultProvider;
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

  /** Run a best-move query against the selected engine. */
  getBestMove(
    input: EngineBestMoveInput,
    provider?: EngineProviderName,
  ): Promise<EngineBestMoveResult> {
    return this.resolve(provider).getBestMove(input);
  }
}
