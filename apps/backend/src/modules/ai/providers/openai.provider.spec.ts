import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OpenAiVisionProvider } from './openai.provider';
import { BOARD_EXTRACTION_PROMPT } from '../prompts/board-extraction.prompt';
import { ErrorLogService } from '../../logging/error-log.service';
import { ExtractBoardStateInput } from '../ai-provider.interface';

/** ConfigService stub exposing an OpenAI key + model (+ optional tuning) under `app.ai`. */
function configWithKey(ai: Record<string, unknown> = {}): ConfigService {
  return {
    get: (k: string) =>
      k === 'app.ai' ? { openaiApiKey: 'sk-test', openaiModel: 'gpt-5.4', ...ai } : undefined,
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

describe('OpenAiVisionProvider retry + request shape', () => {
  const realFetch = global.fetch;
  const errorLog = { log: jest.fn() } as unknown as ErrorLogService;
  afterEach(() => {
    global.fetch = realFetch;
  });

  const ok = () => ({
    ok: true,
    json: async () => ({ choices: [{ message: { content: VALID_BOARD } }] }),
  });

  it('retries a transient 5xx, then succeeds', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 503, text: async () => 'upstream down' })
      .mockResolvedValueOnce(ok());
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey({ maxRetries: 1 }), errorLog);
    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does NOT retry a 4xx (bad key)', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValue({ ok: false, status: 401, text: async () => 'bad key' });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey({ maxRetries: 3 }), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('sends the static prompt as a SYSTEM message and applies the output-token cap', async () => {
    let captured: Record<string, unknown> = {};
    global.fetch = jest.fn().mockImplementation((_url: string, opts: { body: string }) => {
      captured = JSON.parse(opts.body) as Record<string, unknown>;
      return Promise.resolve(ok());
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey({ maxOutputTokens: 1536 }), errorLog);
    await provider.extractBoardState(input);

    const messages = captured.messages as { role: string; content: unknown }[];
    expect(messages[0]).toEqual({ role: 'system', content: BOARD_EXTRACTION_PROMPT });
    expect(messages[1].role).toBe('user');
    expect(captured.max_completion_tokens).toBe(1536);
  });

  it('does NOT retry a truncated (finish_reason=length) empty response — surfaces a clear error', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [{ message: { content: '' }, finish_reason: 'length' }] }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(
      configWithKey({ maxOutputTokens: 1536, maxRetries: 2 }),
      errorLog,
    );
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_OUTPUT_TRUNCATED' }),
    });
    expect(fetchMock).toHaveBeenCalledTimes(1); // deterministic — never retried
  });

  it('does NOT retry an ordinary empty response either', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ choices: [{ message: { content: '' } }] }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey({ maxRetries: 2 }), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_EMPTY_RESPONSE' }),
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('honors a per-call model override (used by the cascade)', async () => {
    let captured: Record<string, unknown> = {};
    global.fetch = jest.fn().mockImplementation((_url: string, opts: { body: string }) => {
      captured = JSON.parse(opts.body) as Record<string, unknown>;
      return Promise.resolve(ok());
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey(), errorLog);
    await provider.extractBoardState({ ...input, modelOverride: 'gpt-5.4-strong' });

    expect(captured.model).toBe('gpt-5.4-strong');
  });
});
