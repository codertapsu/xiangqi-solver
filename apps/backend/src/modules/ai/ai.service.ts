import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import {
  AiVisionProvider,
  ExtractBoardStateInput,
  ExtractBoardStateResult,
} from './ai-provider.interface';
import { MockVisionProvider } from './providers/mock-vision.provider';
import { GeminiVisionProvider } from './providers/gemini.provider';
import { OpenAiVisionProvider } from './providers/openai.provider';

export type AiProviderName = 'gemini' | 'openai' | 'mock';

/**
 * Facade that selects the active AI vision provider by name and exposes a
 * single extractBoardState entry point. Defaults to the configured
 * AI_PROVIDER when no explicit provider is requested.
 */
@Injectable()
export class AiService {
  constructor(
    private readonly config: ConfigService,
    private readonly mockProvider: MockVisionProvider,
    private readonly geminiProvider: GeminiVisionProvider,
    private readonly openaiProvider: OpenAiVisionProvider,
  ) {}

  /** Resolve the configured default provider name. */
  get defaultProvider(): AiProviderName {
    return this.config.get<AppConfig['ai']>('app.ai')?.provider ?? 'mock';
  }

  /** Pick a vision provider implementation by name. */
  resolve(provider?: AiProviderName): AiVisionProvider {
    const name = provider ?? this.defaultProvider;
    switch (name) {
      case 'mock':
        return this.mockProvider;
      case 'gemini':
        return this.geminiProvider;
      case 'openai':
        return this.openaiProvider;
      default:
        throw new BadRequestException({
          message: `Unknown AI provider "${String(name)}". Use "gemini", "openai", or "mock".`,
          code: 'UNKNOWN_AI_PROVIDER',
        });
    }
  }

  /** Run board extraction against the selected provider. */
  extractBoardState(
    input: ExtractBoardStateInput,
    provider?: AiProviderName,
  ): Promise<ExtractBoardStateResult> {
    return this.resolve(provider).extractBoardState(input);
  }
}
