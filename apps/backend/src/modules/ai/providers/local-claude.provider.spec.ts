import { HttpException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ErrorLogService } from '../../logging/error-log.service';
import { ExtractBoardStateInput } from '../ai-provider.interface';
import { BOARD_EXTRACTION_PROMPT } from '../prompts/board-extraction.prompt';
import { LocalClaudeVisionProvider } from './local-claude.provider';

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

const BASE = 'http://127.0.0.1:5612';

function configWith(ai: Record<string, unknown> = {}): ConfigService {
  return {
    get: (key: string) =>
      key === 'app.ai'
        ? {
            localClaudeUrl: BASE,
            localClaudeToken: '',
            localClaudeModel: '',
            localClaudeEffort: '',
            localClaudeCwd: '',
            localClaudePermissionMode: 'default',
            localClaudeTimeoutMs: 180_000,
            ...ai,
          }
        : undefined,
  } as unknown as ConfigService;
}

/** A bridge response whose body is read with `text()`, as the provider does. */
function reply(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => (body === undefined ? '' : JSON.stringify(body)),
  } as unknown as Response;
}

const created = (threadId = 'thread-1') => reply(201, { thread_id: threadId, status: 'created' });

const ran = (text: string = VALID_BOARD, extra: Record<string, unknown> = {}) =>
  reply(200, {
    operation_id: 'op-1',
    thread_id: 'thread-1',
    turn_id: 'turn-1',
    status: 'completed',
    result: { result: text, is_error: false, subtype: 'success', ...extra },
  });

const closed = () => reply(200, { thread_id: 'thread-1', status: 'closed', purged: false });

interface Call {
  url: string;
  options: RequestInit;
}

/** Drive the three-call lifecycle with a queue of scripted responses. */
function scriptFetch(responses: (Response | Error)[]): Call[] {
  const calls: Call[] = [];
  let index = 0;
  global.fetch = jest.fn().mockImplementation((url: string, options: RequestInit) => {
    calls.push({ url, options });
    const next = responses[Math.min(index, responses.length - 1)];
    index += 1;
    return next instanceof Error ? Promise.reject(next) : Promise.resolve(next);
  }) as unknown as typeof fetch;
  return calls;
}

function codeOf(err: unknown): string | undefined {
  if (!(err instanceof HttpException)) return undefined;
  const body = err.getResponse();
  return body && typeof body === 'object'
    ? ((body as Record<string, unknown>).code as string)
    : undefined;
}

describe('LocalClaudeVisionProvider', () => {
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

  it('implements the shared vision-provider contract', () => {
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);
    expect(provider.name).toBe('local-claude');
    expect(typeof provider.extractBoardState).toBe('function');
  });

  it('creates a conversation, runs one turn with the image, then closes it', async () => {
    const calls = scriptFetch([created(), ran(), closed()]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const result = await provider.extractBoardState(input);

    expect(result.boardDetected).toBe(true);
    expect(result.sideToMove).toBe('red');
    expect(result.warnings).toEqual([]);
    expect(calls).toHaveLength(3);

    // 1. A conversation of its own — never POST /chat, which would re-point the
    //    bridge's current conversation out from under whoever is using it.
    expect(calls[0].url).toBe(`${BASE}/threads`);
    expect(calls[0].options.method).toBe('POST');
    const create = JSON.parse(String(calls[0].options.body)) as Record<string, unknown>;
    expect(create.permission_mode).toBe('default');
    expect(create.setting_sources).toEqual([]);
    expect(create.disallowed_tools).toEqual(expect.arrayContaining(['Bash', 'Edit', 'Write']));
    // Blank config values are omitted so the bridge's own defaults apply.
    expect(create).not.toHaveProperty('model');
    expect(create).not.toHaveProperty('effort');
    expect(create).not.toHaveProperty('cwd');

    // 2. The turn carries the image and the prompt, with the side hint appended.
    expect(calls[1].url).toBe(`${BASE}/threads/thread-1/run`);
    const run = JSON.parse(String(calls[1].options.body)) as {
      input: { type: string; url?: string; text?: string }[];
    };
    expect(run.input[0].type).toBe('image');
    expect(run.input[0].url).toBe(`data:image/png;base64,${input.imageBuffer.toString('base64')}`);
    expect(run.input[1].text).toContain(BOARD_EXTRACTION_PROMPT);
    expect(run.input[1].text).toContain("it is red's turn to move");

    // 3. Cleanup.
    expect(calls[2].url).toBe(`${BASE}/threads/thread-1`);
    expect(calls[2].options.method).toBe('DELETE');
    expect(logMock).not.toHaveBeenCalled();
  });

  it('omits the side hint when none is given', async () => {
    const calls = scriptFetch([created(), ran(), closed()]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    await provider.extractBoardState({ ...input, sideToMoveHint: undefined });

    const run = JSON.parse(String(calls[1].options.body)) as { input: { text?: string }[] };
    expect(run.input[1].text).toBe(BOARD_EXTRACTION_PROMPT);
  });

  it('passes the configured model, effort and cwd, and prefers a cascade override', async () => {
    const calls = scriptFetch([created(), ran(), closed()]);
    const provider = new LocalClaudeVisionProvider(
      configWith({
        localClaudeModel: 'sonnet',
        localClaudeEffort: 'high',
        localClaudeCwd: '/srv/boards',
        localClaudePermissionMode: 'plan',
      }),
      errorLog,
    );

    await provider.extractBoardState({ ...input, modelOverride: 'opus' });

    const create = JSON.parse(String(calls[0].options.body)) as Record<string, unknown>;
    expect(create.model).toBe('opus');
    expect(create.effort).toBe('high');
    expect(create.cwd).toBe('/srv/boards');
    expect(create.permission_mode).toBe('plan');
  });

  it('sends a bearer token only when one is configured', async () => {
    let calls = scriptFetch([created(), ran(), closed()]);
    await new LocalClaudeVisionProvider(configWith(), errorLog).extractBoardState(input);
    for (const call of calls) {
      const headers = (call.options.headers ?? {}) as Record<string, string>;
      expect(headers.Authorization).toBeUndefined();
    }

    calls = scriptFetch([created(), ran(), closed()]);
    await new LocalClaudeVisionProvider(
      configWith({ localClaudeToken: 'secret-token' }),
      errorLog,
    ).extractBoardState(input);
    for (const call of calls) {
      const headers = (call.options.headers ?? {}) as Record<string, string>;
      expect(headers.Authorization).toBe('Bearer secret-token');
    }
  });

  it('reports a bridge that has not been started as unavailable, not as a model failure', async () => {
    scriptFetch([
      reply(503, {
        error: { code: 'bridge_not_started', message: 'The Claude bridge has not been started.' },
      }),
    ]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    await expect(provider.extractBoardState(input)).rejects.toThrow(/bridge_not_started/);
    await expect(provider.extractBoardState(input)).rejects.toMatchObject({});
    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_UNAVAILABLE');
  });

  it('reports a signed-out Claude as unavailable', async () => {
    scriptFetch([
      created(),
      reply(401, {
        error: { code: 'claude_login_required', message: 'Not logged in · Please run /login' },
      }),
      closed(),
    ]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_UNAVAILABLE');
    expect(logMock).toHaveBeenCalledWith(
      'local-claude',
      expect.objectContaining({ bridgeCode: 'claude_login_required' }),
    );
  });

  it('closes the conversation even when the turn fails', async () => {
    const calls = scriptFetch([
      created(),
      reply(502, { error: { code: 'claude_error', message: 'the model fell over' } }),
      closed(),
    ]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_API_ERROR');
    // A failed turn must not leak a conversation on the bridge.
    expect(calls).toHaveLength(3);
    expect(calls[2].options.method).toBe('DELETE');
  });

  it('treats a completed-but-errored turn as a failure rather than board text', async () => {
    scriptFetch([
      created(),
      ran('Not logged in · Please run /login', { is_error: true }),
      closed(),
    ]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_API_ERROR');
    expect(err).toEqual(expect.objectContaining({ message: expect.any(String) }));
  });

  it('rejects a turn that never reached a completed state', async () => {
    scriptFetch([created(), reply(200, { status: 'running', result: null }), closed()]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_API_ERROR');
  });

  it('rejects an empty answer', async () => {
    scriptFetch([created(), ran('   '), closed()]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_EMPTY_RESPONSE');
  });

  it('reports a truncated answer as truncation, not as an unreadable screenshot', async () => {
    // Non-empty but cut off mid-JSON. Calling this "the screenshot may not
    // clearly show a board" would send the user to retake a perfectly good one.
    scriptFetch([
      created(),
      ran('{"boardDetected": true, "grid": ["....k...', { stop_reason: 'max_tokens' }),
      closed(),
    ]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_OUTPUT_TRUNCATED');
    expect(logMock).toHaveBeenCalledWith(
      'local-claude',
      expect.objectContaining({ stopReason: 'max_tokens' }),
    );
  });

  it('rejects an answer that is not a board, and logs a bounded snippet', async () => {
    scriptFetch([created(), ran('I am afraid I cannot see a board here.'), closed()]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_INVALID_RESPONSE');
    expect(logMock).toHaveBeenCalledWith(
      'vision-invalid',
      expect.objectContaining({
        rawResponseSnippet: expect.stringContaining('cannot see a board'),
      }),
    );
  });

  it('keeps a good board when cleanup fails, and says so', async () => {
    scriptFetch([created(), ran(), reply(500, { error: { code: 'internal_error' } })]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const result = await provider.extractBoardState(input);

    // The board was read; a lingering conversation is untidy, not wrong, and is
    // not worth discarding the answer the user is waiting for.
    expect(result.boardDetected).toBe(true);
    expect(result.warnings).toEqual([expect.stringContaining('could not be confirmed')]);
    expect(loggerWarnSpy).toHaveBeenCalled();
  });

  it('surfaces a transport failure as a timeout when the deadline fired', async () => {
    const abort = new Error('This operation was aborted');
    abort.name = 'AbortError';
    scriptFetch([abort]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_TIMEOUT');
    expect(logMock).toHaveBeenCalledWith(
      'local-claude',
      expect.objectContaining({ timedOut: true }),
    );
  });

  it('describes an unreachable bridge without losing the underlying cause', async () => {
    const cause = Object.assign(new Error('connect ECONNREFUSED 127.0.0.1:5612'), {
      code: 'ECONNREFUSED',
      port: 5612,
    });
    scriptFetch([Object.assign(new Error('fetch failed'), { cause })]);
    const provider = new LocalClaudeVisionProvider(configWith(), errorLog);

    const err = await provider.extractBoardState(input).catch((e: unknown) => e);
    expect(codeOf(err)).toBe('VISION_API_ERROR');
    // "fetch failed" alone is useless; the real reason lives on `cause`.
    const [, fields] = logMock.mock.calls[0] as [string, Record<string, unknown>];
    expect(JSON.stringify(fields.networkError)).toContain('ECONNREFUSED');
  });

  it('never logs the bearer token or the image bytes', async () => {
    scriptFetch([
      created(),
      reply(502, { error: { code: 'claude_error', message: 'nope' } }),
      closed(),
    ]);
    const provider = new LocalClaudeVisionProvider(
      configWith({ localClaudeToken: 'super-secret' }),
      errorLog,
    );

    await provider.extractBoardState(input).catch(() => undefined);

    const logged = JSON.stringify(logMock.mock.calls);
    expect(logged).not.toContain('super-secret');
    expect(logged).not.toContain(input.imageBuffer.toString('base64'));
    // The size is useful and safe; the bytes are not.
    expect(logMock).toHaveBeenCalledWith(
      'local-claude',
      expect.objectContaining({ imageBytes: input.imageBuffer.byteLength }),
    );
  });
});
