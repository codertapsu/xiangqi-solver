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

/** The head of a board JSON — what a completion cut off at the cap looks like. */
const PARTIAL_BOARD = '{"boardDetected":true,"sideToMove":"red","pieces":[{"color":"red",';

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
        // Our stable code, plus OpenAI's own reason on the diagnostic channel.
        code: 'VISION_UNAVAILABLE',
        httpStatus: 401,
        vendorCode: 'invalid_api_key',
        vendorMessage: 'Invalid key',
        vendorBody: expect.stringContaining('invalid_api_key'),
      }),
    );
  });

  // Regression: OpenAI's 401 text embeds the partially masked key it was given
  // plus a platform.openai.com billing URL, and the whole body reaches the phone
  // (AnalysisService rethrows -> AllExceptionsFilter copies message/details ->
  // the app renders it). The client channel must carry neither.
  it('keeps the vendor message, code and raw body OUT of the client-facing error', async () => {
    const vendorMessage =
      'Incorrect API key provided: sk-proj-6Xa*********7bQd. You can find your API key at ' +
      'https://platform.openai.com/account/api-keys.';
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      text: async () =>
        JSON.stringify({ error: { message: vendorMessage, code: 'invalid_api_key' } }),
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey(), errorLog);
    const err = (await provider
      .extractBoardState(input)
      .catch((e: unknown) => e)) as ServiceUnavailableException;
    const body = err.getResponse() as Record<string, unknown>;

    expect(body.code).toBe('VISION_UNAVAILABLE');
    expect(body.message).toBe('Board reading is unavailable right now. Please try again later.');
    expect(body).not.toHaveProperty('details');
    expect(JSON.stringify(body)).not.toMatch(/sk-proj|platform\.openai\.com|invalid_api_key/);
  });

  it('uses the stable VISION_API_ERROR code for a non-auth vendor failure', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 400,
      text: async () =>
        JSON.stringify({ error: { message: 'bad image', code: 'image_parse_error' } }),
    }) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey(), errorLog);
    const err = (await provider
      .extractBoardState(input)
      .catch((e: unknown) => e)) as ServiceUnavailableException;
    const body = err.getResponse() as Record<string, unknown>;

    expect(body.code).toBe('VISION_API_ERROR');
    // A rejected IMAGE is the one upstream failure the user can act on, so the
    // fixed message gains our own hint — never the vendor's wording.
    expect(body.message).toContain('The screenshot may be too small');
    expect(body.message).not.toContain('bad image');
    expect(logMock).toHaveBeenCalledWith(
      'openai',
      expect.objectContaining({ vendorCode: 'image_parse_error', vendorMessage: 'bad image' }),
    );
  });

  it('keeps a transport error message out of the client channel and in the log', async () => {
    global.fetch = jest
      .fn()
      .mockRejectedValue(
        new Error('getaddrinfo ENOTFOUND api.openai.com'),
      ) as unknown as typeof fetch;

    const provider = new OpenAiVisionProvider(configWithKey({ maxRetries: 0 }), errorLog);
    const err = (await provider
      .extractBoardState(input)
      .catch((e: unknown) => e)) as ServiceUnavailableException;
    const body = err.getResponse() as Record<string, unknown>;

    expect(body).toEqual({
      code: 'VISION_API_ERROR',
      message: 'Board reading failed. Please try again in a moment.',
    });
    // Node hides the real reason in `cause`, so the log keeps the walked chain.
    expect(logMock).toHaveBeenCalledWith(
      'openai',
      expect.objectContaining({
        cause: expect.objectContaining({ message: 'getaddrinfo ENOTFOUND api.openai.com' }),
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

  // Regression: the truncation signal used to be read only INSIDE the empty-body
  // guard. A completion that emitted PART of the JSON and then hit the cap is
  // non-empty, so it was returned as a success, failed in JSON.parse, and the
  // user was told "the screenshot may not clearly show a board" — sending them
  // to retake a perfectly good screenshot while the real cause was the cap.
  it('surfaces a partial-then-truncated completion as VISION_OUTPUT_TRUNCATED, not VISION_INVALID_RESPONSE', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        choices: [{ message: { content: PARTIAL_BOARD }, finish_reason: 'length' }],
      }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const errorLogMock = jest.fn();
    const provider = new OpenAiVisionProvider(
      configWithKey({ maxOutputTokens: 1536, maxRetries: 2 }),
      { log: errorLogMock } as unknown as ErrorLogService,
    );
    const err = (await provider
      .extractBoardState(input)
      .catch((e: unknown) => e)) as ServiceUnavailableException;
    const body = err.getResponse() as Record<string, unknown>;

    expect(body.code).toBe('VISION_OUTPUT_TRUNCATED');
    expect(fetchMock).toHaveBeenCalledTimes(1); // deterministic — never retried
    // The user must not be told to retake a screenshot that was never the
    // problem, nor handed the operator's env-var remedy — that goes to the log.
    expect(body.message).not.toMatch(/screenshot|VISION_MAX_OUTPUT_TOKENS/i);
    expect(errorLogMock).toHaveBeenCalledWith(
      'openai',
      expect.objectContaining({ remedy: expect.stringContaining('VISION_MAX_OUTPUT_TOKENS') }),
    );
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
