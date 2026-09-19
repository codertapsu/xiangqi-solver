import { Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ErrorLogService } from '../../logging/error-log.service';
import { ExtractBoardStateInput } from '../ai-provider.interface';
import { BOARD_EXTRACTION_PROMPT } from '../prompts/board-extraction.prompt';
import { LocalCodexVisionProvider } from './local-codex.provider';

const VALID_BOARD = JSON.stringify({
  boardDetected: true,
  grid: [
    '....k....',
    '.........',
    '.........',
    '.........',
    '.........',
    '.........',
    '.........',
    '.........',
    '.........',
    '....K....',
  ],
  redHomeAtTop: false,
  sideToMove: 'red',
  confidence: 0.95,
  warnings: [],
});

const input: ExtractBoardStateInput = {
  imageBuffer: Buffer.from([0x89, 0x50, 0x4e, 0x47]),
  mimeType: 'image/png',
  sideToMoveHint: 'red',
};

function configWith(ai: Record<string, unknown> = {}): ConfigService {
  return {
    get: (key: string) =>
      key === 'app.ai'
        ? {
            localCodexUrl: 'https://codertapsu.ngrok.app',
            localCodexToken: '',
            localCodexModel: '',
            localCodexReasoningEffort: '',
            localCodexTimeoutMs: 620_000,
            ...ai,
          }
        : undefined,
  } as unknown as ConfigService;
}

function successfulResponse(response: string = VALID_BOARD): Response {
  return {
    ok: true,
    status: 200,
    json: async () => ({
      thread_id: 'thread-1',
      turn_id: 'turn-1',
      status: 'completed',
      response,
      usage: null,
      thread_deleted: true,
    }),
  } as unknown as Response;
}

describe('LocalCodexVisionProvider', () => {
  const realFetch = global.fetch;
  let logMock: jest.Mock;
  let errorLog: ErrorLogService;
  let loggerErrorSpy: jest.SpyInstance;
  let loggerLogSpy: jest.SpyInstance;
  let loggerWarnSpy: jest.SpyInstance;

  beforeEach(() => {
    logMock = jest.fn();
    errorLog = { log: logMock } as unknown as ErrorLogService;
    loggerErrorSpy = jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    loggerLogSpy = jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    loggerWarnSpy = jest.spyOn(Logger.prototype, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    global.fetch = realFetch;
    loggerErrorSpy.mockRestore();
    loggerLogSpy.mockRestore();
    loggerWarnSpy.mockRestore();
  });

  it('sends a one-time JSON image chat and parses the completed response', async () => {
    let requestedUrl = '';
    let requestedOptions: RequestInit | undefined;
    global.fetch = jest.fn().mockImplementation((url: string, options: RequestInit) => {
      requestedUrl = url;
      requestedOptions = options;
      return Promise.resolve(successfulResponse());
    }) as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(configWith(), errorLog);
    const result = await provider.extractBoardState(input);

    expect(provider.name).toBe('local-codex');
    expect(result.boardDetected).toBe(true);
    expect(result.pieces).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ color: 'red', type: 'king' }),
        expect.objectContaining({ color: 'black', type: 'king' }),
      ]),
    );
    expect(requestedUrl).toBe('https://codertapsu.ngrok.app/chat');

    const body = JSON.parse(requestedOptions?.body as string) as Record<string, unknown>;
    expect(body).toMatchObject({
      delete_after_response: true,
      image_data_url: `data:image/png;base64,${input.imageBuffer.toString('base64')}`,
    });
    expect(body.message).toBe(
      `${BOARD_EXTRACTION_PROMPT}\n\nHINT: The user indicated it is red's turn to move.`,
    );
    expect(body).not.toHaveProperty('thread_id');
    expect(body).not.toHaveProperty('model');
    expect(body).not.toHaveProperty('config');
    expect(requestedOptions?.headers).toEqual({ 'Content-Type': 'application/json' });
    expect(logMock).not.toHaveBeenCalled();
  });

  it('sends configured auth/effort and gives the per-call model override priority', async () => {
    let requestedOptions: RequestInit | undefined;
    global.fetch = jest.fn().mockImplementation((_url: string, options: RequestInit) => {
      requestedOptions = options;
      return Promise.resolve(successfulResponse());
    }) as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(
      configWith({
        localCodexToken: 'bridge-secret',
        localCodexModel: 'configured-model',
        localCodexReasoningEffort: 'ultra',
      }),
      errorLog,
    );
    await provider.extractBoardState({ ...input, modelOverride: 'cascade-model' });

    const body = JSON.parse(requestedOptions?.body as string) as Record<string, unknown>;
    expect(body.model).toBe('cascade-model');
    expect(body.config).toEqual({ model_reasoning_effort: 'ultra' });
    expect(requestedOptions?.headers).toEqual({
      'Content-Type': 'application/json',
      Authorization: 'Bearer bridge-secret',
    });
  });

  it('uses a completed answer retained by cleanup_failed and does not retry', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => ({
        error: {
          code: 'cleanup_failed',
          message: 'Conversation deletion failed.',
          thread_id: 'thread-left-behind',
          thread_deleted: false,
          result: {
            thread_id: 'thread-left-behind',
            turn_id: 'turn-1',
            status: 'completed',
            response: VALID_BOARD,
            usage: null,
          },
        },
      }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(configWith(), errorLog);
    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(result.warnings).toEqual([
      'Local Codex read the board, but deleting its one-time conversation could not be confirmed.',
    ]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(logMock).toHaveBeenCalledWith(
      'local-codex',
      expect.objectContaining({
        bridgeCode: 'cleanup_failed',
        threadId: 'thread-left-behind',
      }),
    );
  });

  it('rejects an unconfirmed normal cleanup so AiService can fall back', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ status: 'completed', response: VALID_BOARD, usage: null }),
    }) as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(configWith(), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_API_ERROR' }),
    });
    expect(logMock).toHaveBeenCalledWith(
      'local-codex',
      expect.objectContaining({ message: expect.stringContaining('deletion') }),
    );
  });

  it('maps bridge errors without retrying the non-idempotent chat', async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: false,
      status: 503,
      json: async () => ({
        error: { code: 'runtime_unavailable', message: 'Restart the bridge.' },
      }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(configWith(), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(logMock).toHaveBeenCalledWith(
      'local-codex',
      expect.objectContaining({ bridgeCode: 'runtime_unavailable', status: 503 }),
    );
  });

  it('logs invalid model output with a bounded snippet', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue(successfulResponse('not board JSON')) as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(configWith(), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_INVALID_RESPONSE' }),
    });
    expect(logMock).toHaveBeenCalledWith(
      'vision-invalid',
      expect.objectContaining({ rawResponseSnippet: 'not board JSON' }),
    );
  });

  it('logs the nested Node fetch cause without exposing credentials or image data', async () => {
    const cause = Object.assign(new Error('Connect Timeout Error'), {
      code: 'UND_ERR_CONNECT_TIMEOUT',
      errno: -60,
      syscall: 'connect',
      hostname: 'codertapsu.ngrok.app',
      address: '203.0.113.10',
      port: 5611,
    });
    const fetchError = Object.assign(new TypeError('fetch failed'), { cause });
    global.fetch = jest.fn().mockRejectedValue(fetchError) as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(
      configWith({ localCodexToken: 'bridge-secret' }),
      errorLog,
    );
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_API_ERROR' }),
    });

    expect(logMock).toHaveBeenCalledWith(
      'local-codex',
      expect.objectContaining({
        endpoint: 'https://codertapsu.ngrok.app/chat',
        networkError: expect.objectContaining({
          name: 'TypeError',
          message: 'fetch failed',
          cause: expect.objectContaining({
            name: 'Error',
            message: 'Connect Timeout Error',
            code: 'UND_ERR_CONNECT_TIMEOUT',
            errno: -60,
            syscall: 'connect',
            hostname: 'codertapsu.ngrok.app',
            address: '203.0.113.10',
            port: 5611,
          }),
        }),
      }),
    );
    expect(loggerErrorSpy).toHaveBeenCalledWith(expect.stringContaining('UND_ERR_CONNECT_TIMEOUT'));

    const diagnostics = JSON.stringify({
      fileLog: logMock.mock.calls,
      consoleLog: loggerLogSpy.mock.calls,
      consoleError: loggerErrorSpy.mock.calls,
    });
    expect(diagnostics).not.toContain('bridge-secret');
    expect(diagnostics).not.toContain(input.imageBuffer.toString('base64'));
    expect(diagnostics).not.toContain('image_data_url');
  });

  it('maps an abort to VISION_TIMEOUT and makes only one request', async () => {
    const fetchMock = jest.fn().mockImplementation(
      (_url: string, options: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          options.signal?.addEventListener('abort', () => {
            reject(Object.assign(new Error('aborted'), { name: 'AbortError' }));
          });
        }),
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    const provider = new LocalCodexVisionProvider(configWith({ localCodexTimeoutMs: 5 }), errorLog);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'VISION_TIMEOUT' }),
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
