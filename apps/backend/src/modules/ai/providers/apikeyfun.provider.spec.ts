import { ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApikeyFunVisionProvider } from './apikeyfun.provider';
import { ErrorLogService } from '../../logging/error-log.service';
import { ExtractBoardStateInput } from '../ai-provider.interface';

/** ConfigService stub exposing the apikeyfun key + model (+ tuning) under `app.ai`. */
function configWith(ai: Record<string, unknown> = {}): ConfigService {
  return {
    get: (k: string) =>
      k === 'app.ai' ? { apikeyfunApiKey: 'sk-test', apikeyfunModel: 'gpt-5.5', ...ai } : undefined,
  } as unknown as ConfigService;
}

const input: ExtractBoardStateInput = {
  imageBuffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]),
  mimeType: 'image/png',
  sideToMoveHint: 'red',
};

/** A valid board JSON the parser accepts, split across two content deltas. */
const BOARD_HEAD = '{"boardDetected":true,"sideToMove":"red",';
const BOARD_TAIL = '"pieces":[{"color":"red","type":"king","row":9,"col":4}]}';

const frame = (obj: unknown): string => `data: ${JSON.stringify(obj)}\n\n`;

/** A minimal streaming body: each string becomes one reader chunk (SSE bytes). */
function sseBody(chunks: string[]): { getReader: () => unknown } {
  const enc = new TextEncoder();
  const encoded = chunks.map((c) => enc.encode(c));
  let i = 0;
  return {
    getReader() {
      return {
        read: async () =>
          i < encoded.length
            ? { value: encoded[i++], done: false }
            : { value: undefined, done: true },
        releaseLock() {},
      };
    },
  };
}

const okStream = (chunks: string[]) => ({ ok: true, status: 200, body: sseBody(chunks) });

const boardStream = [
  frame({ choices: [{ delta: { content: BOARD_HEAD } }] }),
  frame({ choices: [{ delta: { content: BOARD_TAIL } }] }),
  frame({ choices: [{ delta: {}, finish_reason: 'stop' }] }),
  'data: [DONE]\n\n',
];

describe('ApikeyFunVisionProvider (streaming, OpenAI-compatible)', () => {
  const realFetch = global.fetch;
  let logMock: jest.Mock;
  let errorLog: ErrorLogService;

  beforeEach(() => {
    logMock = jest.fn();
    errorLog = { log: logMock } as unknown as ErrorLogService;
  });
  afterEach(() => {
    global.fetch = realFetch;
  });

  it('accumulates SSE deltas into the board JSON, then parses it', async () => {
    let captured: Record<string, unknown> = {};
    let headers: Record<string, string> = {};
    global.fetch = jest
      .fn()
      .mockImplementation(
        (_url: string, opts: { body: string; headers: Record<string, string> }) => {
          captured = JSON.parse(opts.body) as Record<string, unknown>;
          headers = opts.headers;
          return Promise.resolve(okStream(boardStream));
        },
      ) as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith(), errorLog);
    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(result.pieces.some((p) => p.type === 'king' && p.color === 'red')).toBe(true);
    // Request shape: streaming, default model, system-message prompt, SSE Accept.
    expect(captured.stream).toBe(true);
    expect(captured.model).toBe('gpt-5.5');
    expect((captured.messages as { role: string }[])[0].role).toBe('system');
    expect(headers.Accept).toBe('text/event-stream');
    expect(headers.Authorization).toBe('Bearer sk-test');
    expect(logMock).not.toHaveBeenCalled();
  });

  it('reassembles a frame split across reader chunks', async () => {
    // Join the whole stream, then cut it at an arbitrary byte mid-frame.
    const whole = boardStream.join('');
    const cut = 40;
    global.fetch = jest
      .fn()
      .mockResolvedValue(
        okStream([whole.slice(0, cut), whole.slice(cut)]),
      ) as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith(), errorLog);
    const result = await provider.extractBoardState(input);
    expect(result.boardDetected).toBe(true);
  });

  it('flushes a final frame that arrives without a trailing blank line', async () => {
    // Whole board in ONE frame, no "\n\n" terminator and no [DONE] before close.
    const single = `data: ${JSON.stringify({
      choices: [{ delta: { content: BOARD_HEAD + BOARD_TAIL } }],
    })}`;
    global.fetch = jest.fn().mockResolvedValue(okStream([single])) as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith(), errorLog);
    const result = await provider.extractBoardState(input);
    expect(result.boardDetected).toBe(true);
  });

  it('retries a transient 5xx, then succeeds', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 503, text: async () => 'upstream down' })
      .mockResolvedValueOnce(okStream(boardStream));
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith({ maxRetries: 1 }), errorLog);
    const result = await provider.extractBoardState(input);
    expect(result.boardDetected).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does NOT retry a 4xx and logs the failure', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: false,
      status: 401,
      text: async () => JSON.stringify({ error: { message: 'bad key', code: 'invalid_api_key' } }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith({ maxRetries: 3 }), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(logMock).toHaveBeenCalledWith(
      'apikeyfun',
      expect.objectContaining({ provider: 'apikeyfun' }),
    );
  });

  it('surfaces a truncated (finish_reason=length, empty) stream as VISION_OUTPUT_TRUNCATED, not retried', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValue(
        okStream([
          frame({ choices: [{ delta: {}, finish_reason: 'length' }] }),
          'data: [DONE]\n\n',
        ]),
      );
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(
      configWith({ maxOutputTokens: 1536, maxRetries: 2 }),
      errorLog,
    );
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_OUTPUT_TRUNCATED' }),
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('surfaces a partial-then-truncated stream (finish_reason=length WITH content) as VISION_OUTPUT_TRUNCATED, not VISION_INVALID_RESPONSE', async () => {
    // The model streams part of the JSON, then hits the output-token cap. The
    // partial body is non-empty, so the truncation must be detected by
    // finish_reason (not by emptiness) — otherwise it parses as an unclear board.
    const fetchMock = jest
      .fn()
      .mockResolvedValue(
        okStream([
          frame({ choices: [{ delta: { content: BOARD_HEAD } }] }),
          frame({ choices: [{ delta: {}, finish_reason: 'length' }] }),
          'data: [DONE]\n\n',
        ]),
      );
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(
      configWith({ maxOutputTokens: 1536, maxRetries: 2 }),
      errorLog,
    );
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_OUTPUT_TRUNCATED' }),
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('retries a TRANSIENT in-band SSE error frame (HTTP 200 then data:{error}), then succeeds', async () => {
    // Aggregators relay a transient upstream failure in-band after a 200; it must
    // be retried like a non-200 5xx would be (the HTTP status alone can't see it).
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(
        okStream([
          frame({ error: { message: 'upstream is busy', code: 'rate_limit_exceeded' } }),
          'data: [DONE]\n\n',
        ]),
      )
      .mockResolvedValueOnce(okStream(boardStream));
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith({ maxRetries: 1 }), errorLog);
    const result = await provider.extractBoardState(input);
    expect(result.boardDetected).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does NOT retry a NON-transient in-band SSE error and logs the real upstream cause', async () => {
    // Fresh stream per call — the reader is stateful (consumed once).
    const fetchMock = jest
      .fn()
      .mockImplementation(() =>
        Promise.resolve(
          okStream([
            frame({ error: { message: 'context length exceeded', code: 'invalid_request_error' } }),
            'data: [DONE]\n\n',
          ]),
        ),
      );
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith({ maxRetries: 3 }), errorLog);
    // The real upstream reason survives into both the surfaced error and the log.
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_API_ERROR' }),
      message: expect.stringContaining('context length exceeded'),
    });
    expect(fetchMock).toHaveBeenCalledTimes(1); // non-transient → never retried
    expect(logMock).toHaveBeenCalledWith(
      'apikeyfun',
      expect.objectContaining({ message: expect.stringContaining('context length exceeded') }),
    );
  });

  it('throws VISION_UNAVAILABLE when the key is missing', async () => {
    const provider = new ApikeyFunVisionProvider(configWith({ apikeyfunApiKey: '' }), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_UNAVAILABLE' }),
    });
  });

  it('honors a per-call model override (used by the cascade)', async () => {
    let captured: Record<string, unknown> = {};
    global.fetch = jest.fn().mockImplementation((_url: string, opts: { body: string }) => {
      captured = JSON.parse(opts.body) as Record<string, unknown>;
      return Promise.resolve(okStream(boardStream));
    }) as unknown as typeof fetch;

    const provider = new ApikeyFunVisionProvider(configWith(), errorLog);
    await provider.extractBoardState({ ...input, modelOverride: 'gpt-5.5-pro' });
    expect(captured.model).toBe('gpt-5.5-pro');
  });
});
