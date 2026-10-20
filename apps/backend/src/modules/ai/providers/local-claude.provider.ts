import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../../config/configuration';
import {
  AiVisionProvider,
  ExtractBoardStateInput,
  ExtractBoardStateResult,
} from '../ai-provider.interface';
import { BOARD_EXTRACTION_PROMPT } from '../prompts/board-extraction.prompt';
import { parseVisionResponse } from '../vision-response.schema';
import { ErrorLogFields, ErrorLogService } from '../../logging/error-log.service';
import { describeFetchError } from './fetch-error.util';

const DEFAULT_BASE_URL = 'http://127.0.0.1:5612';
/**
 * A board read is a single vision turn, not a coding task, so it should take
 * seconds. The bridge's own deadline is far longer; failing here well before
 * that is what lets AiService fall back to the cloud provider while the user is
 * still waiting, instead of holding the request open for ten minutes.
 */
const DEFAULT_TIMEOUT_MS = 180_000;
/** Closing the conversation is quick; it must never dominate the request. */
const CLEANUP_TIMEOUT_MS = 15_000;

const CLEANUP_WARNING =
  'Local Claude read the board, but closing its one-time conversation could not be confirmed.';

/**
 * Tools the extraction has no use for.
 *
 * Belt and braces: the prompt asks for JSON about an image and needs nothing
 * from the filesystem or the network. Denying them up front means a stray tool
 * call cannot park the turn on an approval prompt that no human is watching for.
 * An unrecognised name is simply ignored by the runtime, and a tool outside this
 * list still cannot hang the request indefinitely — the timeout below bounds it.
 */
const DISALLOWED_TOOLS = [
  'Bash',
  'Edit',
  'Write',
  'NotebookEdit',
  'Read',
  'Glob',
  'Grep',
  'WebFetch',
  'WebSearch',
  'Task',
  'TodoWrite',
];

/** `POST /threads` on the bridge. */
interface ThreadCreated {
  thread_id?: unknown;
}

/** `POST /threads/{id}/run` on the bridge. */
interface TurnRun {
  status?: unknown;
  result?: {
    result?: unknown;
    is_error?: unknown;
    subtype?: unknown;
    stop_reason?: unknown;
  };
}

interface BridgeErrorEnvelope {
  error?: {
    code?: unknown;
    message?: unknown;
    field?: unknown;
  };
}

/**
 * Vision provider backed by the Mother Claude HTTP bridge.
 *
 * Each extraction owns a conversation for its whole life: create one, run a
 * single turn carrying the prompt and the normalized board image, then close it.
 * The explicit lifecycle is deliberate — the bridge also offers a one-call
 * `POST /chat`, but that endpoint re-points the bridge's *current* conversation,
 * so using it here would silently hijack whichever conversation the operator was
 * having. `POST /threads` has no such side effect.
 *
 * The call is intentionally not retried. Running a turn is a model mutation, and
 * a connection failure can leave that turn running even when this process never
 * saw its response; a retry would pay for it twice. AiService owns the fallback
 * to the normal cloud provider.
 *
 * Mutually exclusive with {@link LocalCodexVisionProvider} — see
 * `AI_LOCAL_VISION_PROVIDER`, which selects at most one of them.
 */
@Injectable()
export class LocalClaudeVisionProvider implements AiVisionProvider {
  readonly name = 'local-claude';
  private readonly logger = new Logger(LocalClaudeVisionProvider.name);

  constructor(
    private readonly config: ConfigService,
    private readonly errorLog: ErrorLogService,
  ) {}

  async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    const ai = this.config.get<AppConfig['ai']>('app.ai');
    const baseUrl = (ai?.localClaudeUrl?.trim() || DEFAULT_BASE_URL).replace(/\/+$/, '');
    const token = ai?.localClaudeToken?.trim() || '';
    const model = input.modelOverride?.trim() || ai?.localClaudeModel?.trim() || '';
    const effort = ai?.localClaudeEffort?.trim() || '';
    const cwd = ai?.localClaudeCwd?.trim() || '';
    const permissionMode = ai?.localClaudePermissionMode?.trim() || 'default';
    const timeoutMs = Math.min(
      ai?.localClaudeTimeoutMs ?? DEFAULT_TIMEOUT_MS,
      input.timeoutMs ?? Number.POSITIVE_INFINITY,
    );
    const startedAt = Date.now();

    const context = {
      baseUrl,
      model: model || 'bridge-default',
      effort: effort || 'bridge-default',
      permissionMode,
      timeoutMs,
      imageBytes: input.imageBuffer.byteLength,
      mimeType: input.mimeType,
      bearerTokenConfigured: Boolean(token),
    };
    this.logger.log(`Local Claude request started: ${JSON.stringify(context)}`);

    const threadId = await this.createThread(
      { baseUrl, token, model, effort, cwd, permissionMode, timeoutMs },
      input,
      startedAt,
    );

    let raw: string;
    try {
      raw = await this.runTurn({ baseUrl, token, threadId, timeoutMs }, input, model, startedAt);
    } catch (err) {
      // Never leave a conversation behind because the turn failed.
      await this.closeThread(baseUrl, token, threadId);
      throw err;
    }

    const closed = await this.closeThread(baseUrl, token, threadId);
    const result = this.parseOutput(raw, input, model, baseUrl);

    this.logger.log(
      `Local Claude request completed: ${JSON.stringify({
        baseUrl,
        threadId,
        elapsedMs: Date.now() - startedAt,
        threadClosed: closed,
      })}`,
    );

    // Closing is cleanup, not correctness: the board was read successfully, so
    // surface the leak as a warning rather than discarding a good extraction and
    // paying for a second one.
    return closed ? result : { ...result, warnings: [...result.warnings, CLEANUP_WARNING] };
  }

  /** `POST /threads` — one conversation, owned by this extraction alone. */
  private async createThread(
    options: {
      baseUrl: string;
      token: string;
      model: string;
      effort: string;
      cwd: string;
      permissionMode: string;
      timeoutMs: number;
    },
    input: ExtractBoardStateInput,
    startedAt: number,
  ): Promise<string> {
    const endpoint = `${options.baseUrl}/threads`;
    const body = {
      ...(options.cwd ? { cwd: options.cwd } : {}),
      ...(options.model ? { model: options.model } : {}),
      ...(options.effort ? { effort: options.effort } : {}),
      permission_mode: options.permissionMode,
      disallowed_tools: DISALLOWED_TOOLS,
      // Read the board, nothing else: do not load CLAUDE.md, hooks or MCP
      // servers from the working directory into a one-shot vision turn.
      setting_sources: [],
      title: 'Xiangqi board extraction',
    };

    const { payload, response } = await this.send(
      endpoint,
      { method: 'POST', body, token: options.token, timeoutMs: options.timeoutMs },
      input,
      options.model,
      startedAt,
    );

    if (!response.ok) {
      throw this.bridgeFailure(
        'create the conversation',
        response.status,
        payload,
        input,
        options.model,
        endpoint,
        startedAt,
      );
    }

    const threadId = (payload as ThreadCreated | undefined)?.thread_id;
    if (typeof threadId !== 'string' || !threadId.trim()) {
      const failure = new ServiceUnavailableException({
        message: 'Local Claude did not return a conversation id.',
        code: 'VISION_API_ERROR',
      });
      this.logFailure('local-claude', input, options.model, failure, {
        endpoint,
        status: response.status,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }
    return threadId;
  }

  /** `POST /threads/{id}/run` — one blocking turn, returning its final text. */
  private async runTurn(
    options: { baseUrl: string; token: string; threadId: string; timeoutMs: number },
    input: ExtractBoardStateInput,
    model: string,
    startedAt: number,
  ): Promise<string> {
    const endpoint = `${options.baseUrl}/threads/${encodeURIComponent(options.threadId)}/run`;
    const hint = this.hintText(input.sideToMoveHint);
    const dataUrl = `data:${input.mimeType};base64,${input.imageBuffer.toString('base64')}`;
    const body = {
      input: [
        { type: 'image', url: dataUrl },
        {
          type: 'text',
          text: hint ? `${BOARD_EXTRACTION_PROMPT}\n\n${hint}` : BOARD_EXTRACTION_PROMPT,
        },
      ],
    };

    const { payload, response } = await this.send(
      endpoint,
      { method: 'POST', body, token: options.token, timeoutMs: options.timeoutMs },
      input,
      model,
      startedAt,
    );

    if (!response.ok) {
      throw this.bridgeFailure(
        'run the turn',
        response.status,
        payload,
        input,
        model,
        endpoint,
        startedAt,
      );
    }

    const run = payload !== null && typeof payload === 'object' ? (payload as TurnRun) : undefined;
    if (run?.status !== 'completed') {
      const failure = new ServiceUnavailableException({
        message: 'Local Claude did not return a completed turn.',
        code: 'VISION_API_ERROR',
      });
      this.logFailure('local-claude', input, model, failure, {
        endpoint,
        status: response.status,
        turnStatus: run?.status,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }

    // A turn can finish "completed" while the runtime itself reports trouble —
    // an unusable account is delivered as ordinary turn output, not as an HTTP
    // error. Treat that as a failure rather than feeding a prose apology to the
    // board parser.
    if (run.result?.is_error === true) {
      const detail =
        typeof run.result.result === 'string' ? run.result.result.slice(0, 500) : undefined;
      const failure = new ServiceUnavailableException({
        message: `Local Claude reported a failed turn${detail ? `: ${detail}` : '.'}`,
        code: 'VISION_API_ERROR',
        ...(detail ? { details: detail } : {}),
      });
      this.logFailure('local-claude', input, model, failure, {
        endpoint,
        status: response.status,
        turnSubtype: run.result.subtype,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }

    // Checked BEFORE emptiness, not inside it. A model that runs out of output
    // budget mid-JSON returns a non-empty but unparseable answer, which would
    // otherwise surface as "the screenshot may not clearly show a board" — a
    // diagnosis that sends the user to retake a perfectly good screenshot.
    if (run.result?.stop_reason === 'max_tokens') {
      const failure = new ServiceUnavailableException({
        message:
          'Local Claude hit its output limit before finishing the board. Raise the limit on ' +
          'the bridge, or use a model with more output budget.',
        code: 'VISION_OUTPUT_TRUNCATED',
      });
      this.logFailure('local-claude', input, model, failure, {
        endpoint,
        status: response.status,
        stopReason: 'max_tokens',
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }

    const text = run.result?.result;
    if (typeof text !== 'string' || !text.trim()) {
      const failure = new ServiceUnavailableException({
        message: 'Local Claude returned an empty response.',
        code: 'VISION_EMPTY_RESPONSE',
      });
      this.logFailure('local-claude', input, model, failure, {
        endpoint,
        status: response.status,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }
    return text;
  }

  /**
   * `DELETE /threads/{id}` — best effort, and deliberately so.
   *
   * Returns whether closure was confirmed. A failure here is reported as a
   * warning on an otherwise good extraction: the conversation lingers on the
   * bridge until it is restarted, which is untidy but not wrong, and is not
   * worth discarding a board the user is waiting for.
   */
  private async closeThread(baseUrl: string, token: string, threadId: string): Promise<boolean> {
    const endpoint = `${baseUrl}/threads/${encodeURIComponent(threadId)}`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), CLEANUP_TIMEOUT_MS);
    timeout.unref?.();
    try {
      const response = await fetch(endpoint, {
        method: 'DELETE',
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
        signal: controller.signal,
      });
      if (response.ok) return true;
      this.logger.warn(
        `Local Claude cleanup warning: ${JSON.stringify({
          endpoint,
          status: response.status,
          threadId,
        })}`,
      );
      return false;
    } catch (err) {
      this.logger.warn(
        `Local Claude cleanup warning: ${JSON.stringify({
          endpoint,
          threadId,
          error: describeFetchError(err),
        })}`,
      );
      return false;
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * One request to the bridge, returning the parsed body alongside the response.
   *
   * The deadline stays armed until the body has been read, not merely until the
   * headers arrive — a bridge that accepts the request and then stalls mid-turn
   * would otherwise hang here forever.
   */
  private async send(
    endpoint: string,
    options: { method: string; body: unknown; token: string; timeoutMs: number },
    input: ExtractBoardStateInput,
    model: string,
    startedAt: number,
  ): Promise<{ payload: unknown; response: Response }> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), options.timeoutMs);
    timeout.unref?.();

    let response: Response;
    try {
      response = await fetch(endpoint, {
        method: options.method,
        headers: {
          'Content-Type': 'application/json',
          ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
        },
        body: JSON.stringify(options.body),
        signal: controller.signal,
      });
    } catch (err) {
      clearTimeout(timeout);
      const timedOut = err instanceof Error && err.name === 'AbortError';
      const failure = new ServiceUnavailableException({
        message: timedOut
          ? `Local Claude timed out after ${options.timeoutMs}ms.`
          : `Local Claude request error: ${err instanceof Error ? err.message : String(err)}`,
        code: timedOut ? 'VISION_TIMEOUT' : 'VISION_API_ERROR',
      });
      this.logFailure('local-claude', input, model, err, {
        endpoint,
        timeoutMs: options.timeoutMs,
        elapsedMs: Date.now() - startedAt,
        timedOut,
        networkError: describeFetchError(err),
      });
      throw failure;
    }

    try {
      // A 204 (or any empty body) is not an error here; the caller decides.
      const text = await response.text();
      return { payload: text.trim() ? (JSON.parse(text) as unknown) : undefined, response };
    } catch (err) {
      const timedOut =
        controller.signal.aborted || (err instanceof Error && err.name === 'AbortError');
      const failure = new ServiceUnavailableException({
        message: timedOut
          ? `Local Claude timed out after ${options.timeoutMs}ms.`
          : `Local Claude returned an unreadable body (HTTP ${response.status}).`,
        code: timedOut ? 'VISION_TIMEOUT' : 'VISION_API_ERROR',
      });
      this.logFailure('local-claude', input, model, err, {
        endpoint,
        timeoutMs: options.timeoutMs,
        elapsedMs: Date.now() - startedAt,
        timedOut,
        status: response.status,
        responseError: describeFetchError(err),
      });
      throw failure;
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Turn the bridge's `{"error":{code,message}}` envelope into a typed failure.
   *
   * The distinction that matters to whoever reads the log: "the bridge is not
   * set up" (nobody started it, Claude is signed out) is an operator problem,
   * while a transport or model failure is not. Both fall back to the cloud
   * provider, but only one of them is worth acting on.
   */
  private bridgeFailure(
    action: string,
    status: number,
    payload: unknown,
    input: ExtractBoardStateInput,
    model: string,
    endpoint: string,
    startedAt: number,
  ): ServiceUnavailableException {
    const envelope =
      payload !== null && typeof payload === 'object'
        ? (payload as BridgeErrorEnvelope).error
        : undefined;
    const bridgeCode = typeof envelope?.code === 'string' ? envelope.code : 'unknown_bridge_error';
    const bridgeMessage =
      typeof envelope?.message === 'string' ? envelope.message : 'No error detail.';

    const unavailable =
      bridgeCode === 'bridge_not_started' ||
      bridgeCode === 'claude_login_required' ||
      bridgeCode === 'runtime_unavailable' ||
      bridgeCode === 'messages_api_unconfigured';
    const code = unavailable
      ? 'VISION_UNAVAILABLE'
      : bridgeCode === 'timeout'
        ? 'VISION_TIMEOUT'
        : 'VISION_API_ERROR';

    const failure = new ServiceUnavailableException({
      message: `Local Claude could not ${action} (HTTP ${status}, ${bridgeCode}): ${bridgeMessage}`,
      code,
      details: bridgeMessage.slice(0, 500),
    });
    this.logFailure('local-claude', input, model, failure, {
      endpoint,
      status,
      bridgeCode,
      bridgeMessage,
      ...(typeof envelope?.field === 'string' ? { bridgeField: envelope.field } : {}),
      elapsedMs: Date.now() - startedAt,
    });
    return failure;
  }

  private parseOutput(
    rawText: string,
    input: ExtractBoardStateInput,
    model: string,
    baseUrl: string,
  ): ExtractBoardStateResult {
    try {
      return parseVisionResponse(rawText);
    } catch (err) {
      this.logFailure('vision-invalid', input, model, err, {
        baseUrl,
        rawResponseSnippet: rawText.slice(0, 2000),
        parseError: describeFetchError(err),
      });
      throw new ServiceUnavailableException({
        message:
          'Local Claude returned a response that could not be read as a Xiangqi board ' +
          '(the screenshot may not clearly show a board).',
        code: 'VISION_INVALID_RESPONSE',
        details: err instanceof Error ? err.message : String(err),
      });
    }
  }

  private hintText(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    return hint && hint !== 'unknown'
      ? `HINT: The user indicated it is ${hint}'s turn to move.`
      : '';
  }

  /** Log bounded diagnostics without the bearer token or raw image bytes. */
  private logFailure(
    category: 'local-claude' | 'vision-invalid',
    input: ExtractBoardStateInput,
    model: string,
    err: unknown,
    diagnostics: Record<string, unknown> = {},
  ): void {
    const fields: ErrorLogFields = {
      message: err instanceof Error ? err.message : String(err),
      provider: this.name,
      model: model || 'bridge-default',
      imageBytes: input.imageBuffer.byteLength,
      mimeType: input.mimeType,
      sideToMoveHint: input.sideToMoveHint,
      ...diagnostics,
    };
    this.errorLog.log(category, fields);
    this.logger.error(`Local Claude failure: ${JSON.stringify({ category, ...fields })}`);
  }
}
