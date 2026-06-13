import { ConfigService } from '@nestjs/config';
import { AiService } from './ai.service';
import { ImagePreprocessService } from './image-preprocess.service';
import { MockVisionProvider } from './providers/mock-vision.provider';
import { GeminiVisionProvider } from './providers/gemini.provider';
import { OpenAiVisionProvider } from './providers/openai.provider';
import { ExtractBoardStateInput, ExtractBoardStateResult } from './ai-provider.interface';

function buildConfig(): ConfigService {
  return {
    get: (key: string) => (key === 'app.ai' ? { provider: 'mock' } : undefined),
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
