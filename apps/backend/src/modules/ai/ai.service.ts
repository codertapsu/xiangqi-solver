import { createHash } from 'node:crypto';
import { BadRequestException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import { LruCache } from '../../common/utils/lru-cache';
import {
  AiVisionProvider,
  ExtractBoardStateInput,
  ExtractBoardStateResult,
} from './ai-provider.interface';
import { ImagePreprocessService } from './image-preprocess.service';
import { MockVisionProvider } from './providers/mock-vision.provider';
import { GeminiVisionProvider } from './providers/gemini.provider';
import { OpenAiVisionProvider } from './providers/openai.provider';
import { ApikeyFunVisionProvider } from './providers/apikeyfun.provider';

export type AiProviderName = 'gemini' | 'openai' | 'apikeyfun' | 'mock';

/** Identical re-captures are common (retry taps, mode fallbacks re-reading the
 *  same screenshot) — memoizing the extraction skips a multi-second LLM call. */
const VISION_CACHE_ENTRIES = 100;

/**
 * Facade that selects the active AI vision provider by name and exposes a
 * single extractBoardState entry point. Defaults to the configured
 * AI_PROVIDER when no explicit provider is requested.
 *
 * Cross-cutting solve-latency work happens here, once, for every provider:
 * - the upload is downscaled/recompressed to the provider's own pixel budget
 *   (ImagePreprocessService) before being base64'd, and
 * - results are memoized by (provider, side hint, image hash) in a small LRU.
 */
@Injectable()
export class AiService {
  private readonly cache = new LruCache<ExtractBoardStateResult>(VISION_CACHE_ENTRIES);
  /** Single-flight: concurrent identical extractions share ONE provider call. */
  private readonly inFlight = new Map<string, Promise<ExtractBoardStateResult>>();

  constructor(
    private readonly config: ConfigService,
    private readonly preprocess: ImagePreprocessService,
    private readonly mockProvider: MockVisionProvider,
    private readonly geminiProvider: GeminiVisionProvider,
    private readonly openaiProvider: OpenAiVisionProvider,
    private readonly apikeyfunProvider: ApikeyFunVisionProvider,
  ) {}

  /** Resolve the configured default provider name. */
  get defaultProvider(): AiProviderName {
    return this.config.get<AppConfig['ai']>('app.ai')?.provider ?? 'mock';
  }

  /**
   * The provider that WILL run for a request, after applying enforcement: when
   * AI_PROVIDER_ENFORCE is set the client's choice is ignored and the
   * configured default wins. Used for both selection and the response envelope
   * (so vision.provider reflects what actually ran).
   */
  effectiveProviderName(provider?: AiProviderName): AiProviderName {
    const enforce = this.config.get<AppConfig['ai']>('app.ai')?.providerEnforce ?? false;
    return (enforce ? undefined : provider) ?? this.defaultProvider;
  }

  /** Pick a vision provider implementation by name. */
  resolve(provider?: AiProviderName): AiVisionProvider {
    const name = this.effectiveProviderName(provider);
    switch (name) {
      case 'mock':
        return this.mockProvider;
      case 'gemini':
        return this.geminiProvider;
      case 'openai':
        return this.openaiProvider;
      case 'apikeyfun':
        return this.apikeyfunProvider;
      default:
        throw new BadRequestException({
          message: `Unknown AI provider "${String(name)}". Use "gemini", "openai", "apikeyfun", or "mock".`,
          code: 'UNKNOWN_AI_PROVIDER',
        });
    }
  }

  /** Run board extraction against the selected provider. */
  async extractBoardState(
    input: ExtractBoardStateInput,
    provider?: AiProviderName,
  ): Promise<ExtractBoardStateResult> {
    const impl = this.resolve(provider);

    // Key on the ORIGINAL upload bytes so a cache hit skips both the LLM call
    // and the (sharp) preprocessing work entirely.
    const hash = createHash('sha256').update(input.imageBuffer).digest('hex');
    const key = `${impl.name}|${input.sideToMoveHint ?? 'unknown'}|${hash}`;

    const hit = this.cache.get(key);
    // Clone: downstream repair/normalize steps reorder piece arrays in place.
    if (hit) return structuredClone(hit);

    // Coalesce concurrent identical requests (app double-fire, two devices on
    // the same board) onto ONE provider call.
    const existing = this.inFlight.get(key);
    if (existing) return structuredClone(await existing);

    const work = this.compute(impl, input, key);
    this.inFlight.set(key, work);
    try {
      return structuredClone(await work);
    } finally {
      this.inFlight.delete(key);
    }
  }

  /** Preprocess → extract (+ optional cascade) → memoize. */
  private async compute(
    impl: AiVisionProvider,
    input: ExtractBoardStateInput,
    cacheKey: string,
  ): Promise<ExtractBoardStateResult> {
    const { buffer, mimeType } = await this.preprocess.normalizeForVision(
      input.imageBuffer,
      input.mimeType,
    );
    const baseInput: ExtractBoardStateInput = {
      imageBuffer: buffer,
      mimeType,
      sideToMoveHint: input.sideToMoveHint,
    };

    let result = await impl.extractBoardState(baseInput);
    result = await this.maybeCascade(impl, baseInput, result);

    // Memoize only USABLE extractions (board found, both generals present).
    // Vision is nondeterministic, so a "no board" / garbled read must stay
    // retryable — the UI explicitly tells the user to try again, and pinning
    // the failure for byte-identical retries (history re-solve, re-share)
    // would make that advice a lie. Mirrors the engine cache, which never
    // memoizes failures.
    if (this.isUsable(result)) {
      this.cache.set(cacheKey, structuredClone(result));
    }
    return result;
  }

  /**
   * Accuracy cascade (config-gated, default off): when the primary read is
   * unusable (no board / a general missing) or below the confidence floor,
   * re-run ONCE on a stronger model and keep it if it's better. Costs a second
   * call only on ambiguous boards; a failure of the second call keeps the first.
   */
  private async maybeCascade(
    impl: AiVisionProvider,
    baseInput: ExtractBoardStateInput,
    primary: ExtractBoardStateResult,
  ): Promise<ExtractBoardStateResult> {
    const cascade = this.config.get<AppConfig['ai']>('app.ai')?.cascade;
    if (
      !cascade?.enabled ||
      !cascade.model ||
      impl.name === 'mock' ||
      !this.isWeak(primary, cascade.minConfidence)
    ) {
      return primary;
    }
    try {
      const strong = await impl.extractBoardState({ ...baseInput, modelOverride: cascade.model });
      const better =
        this.isUsable(strong) &&
        (!this.isUsable(primary) || strong.confidence >= primary.confidence);
      return better ? strong : primary;
    } catch {
      // Cascade is best-effort: keep the primary read on any failure.
      return primary;
    }
  }

  private isWeak(result: ExtractBoardStateResult, minConfidence: number): boolean {
    return !this.isUsable(result) || result.confidence < minConfidence;
  }

  private isUsable(result: ExtractBoardStateResult): boolean {
    return result.boardDetected && this.hasBothGenerals(result);
  }

  private hasBothGenerals(result: ExtractBoardStateResult): boolean {
    return (['red', 'black'] as const).every((color) =>
      result.pieces.some((p) => p.type === 'king' && p.color === color),
    );
  }
}
