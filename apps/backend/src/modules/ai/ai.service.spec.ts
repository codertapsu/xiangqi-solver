import { ConfigService } from '@nestjs/config';
import { AiService } from './ai.service';
import { ImagePreprocessService } from './image-preprocess.service';
import { MockVisionProvider } from './providers/mock-vision.provider';
import { GeminiVisionProvider } from './providers/gemini.provider';
import { OpenAiVisionProvider } from './providers/openai.provider';
import { ExtractBoardStateInput, ExtractBoardStateResult } from './ai-provider.interface';

function buildConfig(ai: Record<string, unknown> = { provider: 'mock' }): ConfigService {
  return {
    get: (key: string) => (key === 'app.ai' ? ai : undefined),
  } as unknown as ConfigService;
}

const identityPreprocess = {
  normalizeForVision: async (buffer: Buffer, mimeType: string) => ({ buffer, mimeType }),
} as unknown as ImagePreprocessService;

/** Mock provider stand-in that counts real extractions. */
class CountingProvider {
  readonly name = 'mock';
  calls = 0;

  async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    this.calls++;
    // Both generals present: only USABLE extractions are memoized.
    return {
      boardDetected: true,
      sideToMove: input.sideToMoveHint ?? 'unknown',
      confidence: 0.9,
      pieces: [
        { color: 'red', type: 'king', file: 4, rank: 0 },
        { color: 'black', type: 'king', file: 4, rank: 9 },
      ],
      warnings: [],
    };
  }
}

describe('AiService extraction cache', () => {
  let counting: CountingProvider;
  let service: AiService;

  beforeEach(() => {
    const config = buildConfig();
    counting = new CountingProvider();
    service = new AiService(
      config,
      identityPreprocess,
      counting as unknown as MockVisionProvider,
      {} as GeminiVisionProvider,
      {} as OpenAiVisionProvider,
    );
  });

  const image = Buffer.from('fake-png-bytes');

  it('memoizes identical (image, hint) extractions', async () => {
    const input: ExtractBoardStateInput = {
      imageBuffer: image,
      mimeType: 'image/png',
      sideToMoveHint: 'red',
    };
    const first = await service.extractBoardState(input);
    const second = await service.extractBoardState(input);
    expect(counting.calls).toBe(1);
    expect(second).toEqual(first);
    // Cached results are cloned: downstream board repair mutates piece arrays.
    second.pieces.pop();
    const third = await service.extractBoardState(input);
    expect(third.pieces).toHaveLength(2);
  });

  it('does NOT memoize unusable extractions (no board / missing generals)', async () => {
    const failing = {
      name: 'mock',
      calls: 0,
      async extractBoardState(): Promise<ExtractBoardStateResult> {
        this.calls++;
        return {
          boardDetected: false,
          sideToMove: 'unknown',
          confidence: 0,
          pieces: [],
          warnings: ['no board visible'],
        };
      },
    };
    const svc = new AiService(
      buildConfig(),
      identityPreprocess,
      failing as unknown as MockVisionProvider,
      {} as GeminiVisionProvider,
      {} as OpenAiVisionProvider,
    );
    const input: ExtractBoardStateInput = { imageBuffer: image, mimeType: 'image/png' };
    await svc.extractBoardState(input);
    await svc.extractBoardState(input);
    // Vision is nondeterministic: a retry of the same bytes must re-query.
    expect(failing.calls).toBe(2);
  });

  it('different image bytes or hints are different cache entries', async () => {
    await service.extractBoardState({ imageBuffer: image, mimeType: 'image/png' });
    await service.extractBoardState({
      imageBuffer: image,
      mimeType: 'image/png',
      sideToMoveHint: 'black',
    });
    await service.extractBoardState({
      imageBuffer: Buffer.from('other-bytes'),
      mimeType: 'image/png',
    });
    expect(counting.calls).toBe(3);
  });
});

describe('AiService provider enforcement', () => {
  const allProviders = (calls: { name: string }[]) => ({
    mock: {
      name: 'mock',
      extractBoardState: async () => {
        calls.push({ name: 'mock' });
        return base();
      },
    },
    gemini: {
      name: 'gemini',
      extractBoardState: async () => {
        calls.push({ name: 'gemini' });
        return base();
      },
    },
    openai: {
      name: 'openai',
      extractBoardState: async () => {
        calls.push({ name: 'openai' });
        return base();
      },
    },
  });
  const base = (): ExtractBoardStateResult => ({
    boardDetected: true,
    sideToMove: 'red',
    confidence: 0.9,
    pieces: [
      { color: 'red', type: 'king', file: 4, rank: 0 },
      { color: 'black', type: 'king', file: 4, rank: 9 },
    ],
    warnings: [],
  });

  function svc(ai: Record<string, unknown>, calls: { name: string }[]): AiService {
    const p = allProviders(calls);
    return new AiService(
      buildConfig(ai),
      identityPreprocess,
      p.mock as unknown as MockVisionProvider,
      p.gemini as unknown as GeminiVisionProvider,
      p.openai as unknown as OpenAiVisionProvider,
    );
  }

  const img = Buffer.from('img');

  it('honors the client provider when enforce is off (default)', async () => {
    const calls: { name: string }[] = [];
    const service = svc({ provider: 'gemini', providerEnforce: false }, calls);
    await service.extractBoardState({ imageBuffer: img, mimeType: 'image/png' }, 'openai');
    expect(calls).toEqual([{ name: 'openai' }]);
    expect(service.effectiveProviderName('openai')).toBe('openai');
  });

  it('ignores the client provider and uses the configured default when enforce is on', async () => {
    const calls: { name: string }[] = [];
    const service = svc({ provider: 'gemini', providerEnforce: true }, calls);
    // Old app sends provider=openai; the server must still use gemini.
    await service.extractBoardState({ imageBuffer: img, mimeType: 'image/png' }, 'openai');
    expect(calls).toEqual([{ name: 'gemini' }]);
    expect(service.effectiveProviderName('openai')).toBe('gemini');
  });
});

describe('AiService single-flight coalescing', () => {
  it('collapses concurrent identical extractions onto ONE provider call', async () => {
    const counting = new CountingProvider();
    const service = new AiService(
      buildConfig(),
      identityPreprocess,
      counting as unknown as MockVisionProvider,
      {} as GeminiVisionProvider,
      {} as OpenAiVisionProvider,
    );
    const input: ExtractBoardStateInput = {
      imageBuffer: Buffer.from('same-bytes'),
      mimeType: 'image/png',
      sideToMoveHint: 'red',
    };
    const [a, b] = await Promise.all([
      service.extractBoardState(input),
      service.extractBoardState(input),
    ]);
    expect(counting.calls).toBe(1);
    expect(a).toEqual(b);
    // Cloned per caller: mutating one must not affect the other or the cache.
    a.pieces.pop();
    expect(b.pieces).toHaveLength(2);
  });
});

describe('AiService accuracy cascade', () => {
  const weak = (): ExtractBoardStateResult => ({
    boardDetected: true, // a board, but missing the black general -> unusable
    sideToMove: 'red',
    confidence: 0.4,
    pieces: [{ color: 'red', type: 'king', file: 4, rank: 0 }],
    warnings: [],
  });
  const strong = (): ExtractBoardStateResult => ({
    boardDetected: true,
    sideToMove: 'red',
    confidence: 0.95,
    pieces: [
      { color: 'red', type: 'king', file: 4, rank: 0 },
      { color: 'black', type: 'king', file: 4, rank: 9 },
    ],
    warnings: [],
  });

  /** Provider that reads "weak" on its base model and "strong" on the override. */
  function cascadeProvider() {
    return {
      name: 'openai',
      calls: 0,
      models: [] as (string | undefined)[],
      async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
        this.calls++;
        this.models.push(input.modelOverride);
        return input.modelOverride ? strong() : weak();
      },
    };
  }

  function build(ai: Record<string, unknown>, provider: ReturnType<typeof cascadeProvider>) {
    return new AiService(
      buildConfig({ provider: 'openai', ...ai }),
      identityPreprocess,
      {} as MockVisionProvider,
      {} as GeminiVisionProvider,
      provider as unknown as OpenAiVisionProvider,
    );
  }
  const img: ExtractBoardStateInput = { imageBuffer: Buffer.from('x'), mimeType: 'image/png' };

  it('re-reads a weak board on the stronger model when enabled', async () => {
    const provider = cascadeProvider();
    const service = build(
      { cascade: { enabled: true, model: 'gpt-strong', minConfidence: 0 } },
      provider,
    );
    const result = await service.extractBoardState(img);
    expect(result.pieces).toHaveLength(2); // the strong, usable read won
    expect(provider.calls).toBe(2);
    expect(provider.models).toEqual([undefined, 'gpt-strong']);
  });

  it('does NOT cascade when disabled (default) — returns the weak read as-is', async () => {
    const provider = cascadeProvider();
    const service = build(
      { cascade: { enabled: false, model: 'gpt-strong', minConfidence: 0 } },
      provider,
    );
    const result = await service.extractBoardState(img);
    expect(result.pieces).toHaveLength(1);
    expect(provider.calls).toBe(1);
  });

  it('keeps the primary read when the cascade call fails', async () => {
    const provider = {
      name: 'openai',
      calls: 0,
      async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
        this.calls++;
        if (input.modelOverride) throw new Error('strong model unavailable');
        return weak();
      },
    };
    const service = build(
      { cascade: { enabled: true, model: 'gpt-strong', minConfidence: 0 } },
      provider as unknown as ReturnType<typeof cascadeProvider>,
    );
    const result = await service.extractBoardState(img);
    expect(result.pieces).toHaveLength(1); // fell back to the primary
    expect(provider.calls).toBe(2);
  });
});
