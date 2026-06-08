import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OpenAiVisionProvider } from './openai.provider';
import { ErrorLogService } from '../../logging/error-log.service';
import { ExtractBoardStateInput } from '../ai-provider.interface';

/** ConfigService stub exposing an OpenAI key + model under `app.ai`. */
function configWithKey(key = 'sk-test'): ConfigService {
  return {
    get: (k: string) =>
      k === 'app.ai' ? { openaiApiKey: key, openaiModel: 'gpt-5.4' } : undefined,
  } as unknown as ConfigService;
}

const input: ExtractBoardStateInput = {
  imageBuffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]),
  mimeType: 'image/png',
  sideToMoveHint: 'red',
};

/** A valid board JSON the parser accepts (one piece is enough for this test). */
const VALID_BOARD = JSON.stringify({
  boardDetected: true,
  sideToMove: 'red',
  pieces: [{ color: 'red', type: 'king', row: 9, col: 4 }],
});

describe('OpenAiVisionProvider error logging', () => {
  let logMock: jest.Mock;
  let errorLog: ErrorLogService;
  const realFetch = global.fetch;

  beforeEach(() => {
    logMock = jest.fn();
    errorLog = { log: logMock } as unknown as ErrorLogService;
  });

  afterEach(() => {
    global.fetch = realFetch;
  });

  it('logs an "openai" failure (with OpenAI code + image meta) when the API request fails', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      text: async () =>
        JSON.stringify({ error: { message: 'Invalid key', code: 'invalid_api_key' } }),
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey(), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );

    expect(logMock).toHaveBeenCalledWith(
      'openai',
      expect.objectContaining({
        provider: 'openai',
        model: 'gpt-5.4',
        imageBytes: input.imageBuffer.byteLength,
        mimeType: 'image/png',
        code: 'invalid_api_key',
      }),
    );
  });

  it('logs a "vision-invalid" failure (with a raw snippet) when the response cannot be parsed', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [{ message: { content: 'not json at all' } }] }),
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey(), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_INVALID_RESPONSE' }),
    });

    expect(logMock).toHaveBeenCalledWith(
      'vision-invalid',
      expect.objectContaining({
        provider: 'openai',
        model: 'gpt-5.4',
        rawResponseSnippet: expect.stringContaining('not json'),
      }),
    );
  });

  it('does NOT log when extraction succeeds', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [{ message: { content: VALID_BOARD } }] }),
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey(), errorLog);
    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(logMock).not.toHaveBeenCalled();
  });
});
