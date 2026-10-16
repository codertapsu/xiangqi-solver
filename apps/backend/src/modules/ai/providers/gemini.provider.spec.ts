import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GeminiVisionProvider } from './gemini.provider';
import { BOARD_EXTRACTION_PROMPT } from '../prompts/board-extraction.prompt';
import { ErrorLogService } from '../../logging/error-log.service';
import { ExtractBoardStateInput } from '../ai-provider.interface';

/** ConfigService stub exposing a Gemini key + model (+ optional tuning) under `app.ai`. */
function configWithKey(ai: Record<string, unknown> = {}): ConfigService {
  return {
    get: (k: string) =>
      k === 'app.ai'
        ? { geminiApiKey: 'gemini-test-key', geminiModel: 'gemini-3.5-flash', ...ai }
        : undefined,
  } as unknown as ConfigService;
}

const input: ExtractBoardStateInput = {
  imageBuffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]),
  mimeType: 'image/png',
  sideToMoveHint: 'red',
};

/** A valid board JSON the parser accepts (one piece is enough for these tests). */
const VALID_BOARD = JSON.stringify({
  boardDetected: true,
  sideToMove: 'red',
  pieces: [{ color: 'red', type: 'king', row: 9, col: 4 }],
});

/** The head of a board JSON — what a response cut off at the cap looks like. */
const PARTIAL_BOARD = '{"boardDetected":true,"sideToMove":"red","pieces":[{"color":"red",';

/** A successful generateContent response carrying `text`. */
const ok = (text = VALID_BOARD, finishReason?: string) => ({
  ok: true,
  json: async () => ({
    candidates: [{ content: { parts: [{ text }] }, ...(finishReason ? { finishReason } : {}) }],
  }),
});

/** The client-facing body of a rejected extraction. */
async function failureBody(provider: GeminiVisionProvider): Promise<Record<string, unknown>> {
  const err = (await provider
    .extractBoardState(input)
    .catch((e: unknown) => e)) as ServiceUnavailableException;
  expect(err).toBeInstanceOf(ServiceUnavailableException);
  return err.getResponse() as Record<string, unknown>;
}

describe('GeminiVisionProvider', () => {
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

  it('parses a board and sends the static prompt as a systemInstruction', async () => {
    let captured: Record<string, unknown> = {};
    global.fetch = jest.fn().mockImplementation((_url: string, opts: { body: string }) => {
      captured = JSON.parse(opts.body) as Record<string, unknown>;
      return Promise.resolve(ok());
    }) as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey({ maxOutputTokens: 1536 }), errorLog);
    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(captured.systemInstruction).toEqual({ parts: [{ text: BOARD_EXTRACTION_PROMPT }] });
    expect((captured.generationConfig as Record<string, unknown>).maxOutputTokens).toBe(1536);
    expect(logMock).not.toHaveBeenCalled();
  });

  it('throws VISION_UNAVAILABLE when the key is missing', async () => {
    const provider = new GeminiVisionProvider(configWithKey({ geminiApiKey: '' }), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_UNAVAILABLE' }),
    });
  });

  // Regression: the truncation signal used to be read only INSIDE the empty-body
  // guard. A response that emitted PART of the JSON and then hit the cap is
  // non-empty, so it was returned as a success, failed in JSON.parse, and the
  // user was told "the screenshot may not clearly show a board" — sending them
  // to retake a perfectly good screenshot while the real cause was the cap.
  it('surfaces a partial-then-truncated response as VISION_OUTPUT_TRUNCATED, not VISION_INVALID_RESPONSE', async () => {
    const fetchMock = jest.fn().mockResolvedValue(ok(PARTIAL_BOARD, 'MAX_TOKENS'));
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(
      configWithKey({ maxOutputTokens: 1536, maxRetries: 2 }),
      errorLog,
    );
    const body = await failureBody(provider);

    expect(body.code).toBe('VISION_OUTPUT_TRUNCATED');
    expect(fetchMock).toHaveBeenCalledTimes(1); // deterministic — never retried
    // The point of the fix: the user is not sent to retake a good screenshot,
    // and is not handed the operator's env-var remedy either.
    expect(body.message).not.toMatch(/screenshot|VISION_MAX_OUTPUT_TOKENS/i);
    expect(logMock).toHaveBeenCalledWith(
      'gemini',
      expect.objectContaining({ remedy: expect.stringContaining('VISION_MAX_OUTPUT_TOKENS') }),
    );
  });

  it('surfaces a truncated EMPTY response as VISION_OUTPUT_TRUNCATED too', async () => {
    const fetchMock = jest.fn().mockResolvedValue(ok('', 'MAX_TOKENS'));
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey({ maxRetries: 2 }), errorLog);
    const body = await failureBody(provider);

    expect(body.code).toBe('VISION_OUTPUT_TRUNCATED');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('surfaces an ordinary empty response as VISION_EMPTY_RESPONSE, not retried', async () => {
    const fetchMock = jest.fn().mockResolvedValue(ok(''));
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey({ maxRetries: 2 }), errorLog);
    const body = await failureBody(provider);

    expect(body.code).toBe('VISION_EMPTY_RESPONSE');
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  // Regression: the raw vendor body used to ride along in `details`, and the
  // public code differed from the other providers'. Both reach the phone.
  it('keeps the vendor body OUT of the client-facing error and logs it instead', async () => {
    const vendorBody = JSON.stringify({
      error: { code: 403, message: 'API key not valid. Please pass a valid API key.' },
    });
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      status: 403,
      text: async () => vendorBody,
    }) as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey({ maxRetries: 2 }), errorLog);
    const body = await failureBody(provider);

    // Same vocabulary as OpenAI/apikeyfun: 401/403 -> VISION_UNAVAILABLE.
    expect(body).toEqual({
      code: 'VISION_UNAVAILABLE',
      message: 'Board reading is unavailable right now. Please try again later.',
    });
    expect(logMock).toHaveBeenCalledWith(
      'gemini',
      expect.objectContaining({
        provider: 'gemini',
        model: 'gemini-3.5-flash',
        code: 'VISION_UNAVAILABLE',
        httpStatus: 403,
        vendorCode: '403',
        vendorMessage: 'API key not valid. Please pass a valid API key.',
        vendorBody: expect.stringContaining('API key not valid'),
      }),
    );
  });

  it('retries a transient 5xx, then succeeds', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 503, text: async () => 'upstream down' })
      .mockResolvedValueOnce(ok());
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey({ maxRetries: 1 }), errorLog);
    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('logs a "vision-invalid" failure (with a raw snippet) when the response cannot be parsed', async () => {
    global.fetch = jest.fn().mockResolvedValue(ok('not json at all')) as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey(), errorLog);
    const body = await failureBody(provider);

    expect(body.code).toBe('VISION_INVALID_RESPONSE');
    expect(logMock).toHaveBeenCalledWith(
      'vision-invalid',
      expect.objectContaining({
        provider: 'gemini',
        rawResponseSnippet: expect.stringContaining('not json'),
      }),
    );
  });

  it('honors a per-call model override (used by the cascade)', async () => {
    let url = '';
    global.fetch = jest.fn().mockImplementation((requestUrl: string) => {
      url = requestUrl;
      return Promise.resolve(ok());
    }) as unknown as typeof fetch;

    const provider = new GeminiVisionProvider(configWithKey(), errorLog);
    await provider.extractBoardState({ ...input, modelOverride: 'gemini-3.5-pro' });

    expect(url).toContain('gemini-3.5-pro:generateContent');
  });
});
