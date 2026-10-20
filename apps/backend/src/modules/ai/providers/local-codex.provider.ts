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

const DEFAULT_BASE_URL = 'https://codertapsu.ngrok.app';
// The bridge itself waits up to 600 seconds. Leave a small delivery margin so
// this client does not abandon a turn that the bridge is still running.
const DEFAULT_TIMEOUT_MS = 620_000;
const CLEANUP_WARNING =
  'Local Codex read the board, but deleting its one-time conversation could not be confirmed.';

interface CodexTurnResult {
  status?: unknown;
  response?: unknown;
  thread_deleted?: unknown;
}

interface CodexErrorEnvelope {
  error?: {
    code?: unknown;
    message?: unknown;
    thread_id?: unknown;
    turn_id?: unknown;
    result?: unknown;
    thread_deleted?: unknown;
  };
}

/**
 * Vision provider backed by the Codex HTTP bridge. Every extraction starts a
 * one-time conversation, attaches the normalized board image, waits for the
 * final response, and asks the bridge to delete the conversation before
 * success is returned.
 *
 * The call is intentionally not retried here. POST /chat is a model mutation,
 * and a connection failure can leave the first turn running even when this
 * process did not receive its response. AiService owns the provider fallback.
 */
@Injectable()
export class LocalCodexVisionProvider implements AiVisionProvider {
  readonly name = 'local-codex';
  private readonly logger = new Logger(LocalCodexVisionProvider.name);

  constructor(
    private readonly config: ConfigService,
    private readonly errorLog: ErrorLogService,
  ) {}

  async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    const ai = this.config.get<AppConfig['ai']>('app.ai');
    const baseUrl = ai?.localCodexUrl?.trim() || DEFAULT_BASE_URL;
    const token = ai?.localCodexToken?.trim() || '';
    const model = input.modelOverride?.trim() || ai?.localCodexModel?.trim() || '';
    const reasoningEffort = ai?.localCodexReasoningEffort?.trim() || '';
    const timeoutMs = Math.min(
      ai?.localCodexTimeoutMs ?? DEFAULT_TIMEOUT_MS,
      input.timeoutMs ?? Number.POSITIVE_INFINITY,
    );
    const endpoint = `${baseUrl.replace(/\/+$/, '')}/chat`;
    const dataUrl = `data:${input.mimeType};base64,${input.imageBuffer.toString('base64')}`;
    const hint = this.hintText(input.sideToMoveHint);
    const startedAt = Date.now();

    const body = {
      message: hint ? `${BOARD_EXTRACTION_PROMPT}\n\n${hint}` : BOARD_EXTRACTION_PROMPT,
      image_data_url: dataUrl,
      delete_after_response: true,
      ...(model ? { model } : {}),
      ...(reasoningEffort ? { config: { model_reasoning_effort: reasoningEffort } } : {}),
    };

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    timeout.unref?.();

    this.logger.log(
      `Local Codex request started: ${JSON.stringify({
        endpoint,
        model: model || 'bridge-default',
        reasoningEffort: reasoningEffort || 'bridge-default',
        timeoutMs,
        imageBytes: input.imageBuffer.byteLength,
        mimeType: input.mimeType,
        bearerTokenConfigured: Boolean(token),
      })}`,
    );

    let response: Response;
    try {
      response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } catch (err) {
      const timedOut = err instanceof Error && err.name === 'AbortError';
      const failure = new ServiceUnavailableException({
        message: timedOut
          ? `Local Codex timed out after ${timeoutMs}ms.`
          : `Local Codex request error: ${err instanceof Error ? err.message : String(err)}`,
        code: timedOut ? 'VISION_TIMEOUT' : 'VISION_API_ERROR',
      });
      this.logFailure('local-codex', input, model, err, {
        endpoint,
        timeoutMs,
        elapsedMs: Date.now() - startedAt,
        timedOut,
        networkError: this.describeError(err),
      });
      clearTimeout(timeout);
      throw failure;
    }

    let payload: unknown;
    try {
      payload = await response.json();
    } catch (err) {
      const timedOut =
        controller.signal.aborted || (err instanceof Error && err.name === 'AbortError');
      const failure = new ServiceUnavailableException({
        message: timedOut
          ? `Local Codex timed out after ${timeoutMs}ms.`
          : `Local Codex returned an invalid JSON envelope (HTTP ${response.status}).`,
        code: timedOut ? 'VISION_TIMEOUT' : 'VISION_API_ERROR',
      });
      this.logFailure('local-codex', input, model, err, {
        endpoint,
        timeoutMs,
        elapsedMs: Date.now() - startedAt,
        timedOut,
        status: response.status,
        responseError: this.describeError(err),
      });
      throw failure;
    } finally {
      // Keep the deadline active through response-body delivery, not merely
      // until the response headers arrive.
      clearTimeout(timeout);
    }

    if (!response.ok) {
      const envelope = this.asErrorEnvelope(payload);
      const bridgeError = envelope?.error;
      const retained = this.asTurnResult(bridgeError?.result);

      // The model already completed in this case; only conversation deletion
      // failed. Reusing the retained answer avoids paying for or racing a second
      // model turn. If that answer is unusable, parseOutput throws and AiService
      // can fall back to the normal provider.
      if (
        response.status === 502 &&
        bridgeError?.code === 'cleanup_failed' &&
        retained?.status === 'completed' &&
        typeof retained.response === 'string' &&
        retained.response.trim()
      ) {
        this.errorLog.log('local-codex', {
          message: CLEANUP_WARNING,
          provider: this.name,
          model: model || 'bridge-default',
          imageBytes: input.imageBuffer.byteLength,
          mimeType: input.mimeType,
          sideToMoveHint: input.sideToMoveHint,
          status: response.status,
          bridgeCode: 'cleanup_failed',
          ...(typeof bridgeError.thread_id === 'string' ? { threadId: bridgeError.thread_id } : {}),
        });
        this.logger.warn(
          `Local Codex cleanup warning: ${JSON.stringify({
            endpoint,
            status: response.status,
            bridgeCode: 'cleanup_failed',
            elapsedMs: Date.now() - startedAt,
            ...(typeof bridgeError.thread_id === 'string'
              ? { threadId: bridgeError.thread_id }
              : {}),
          })}`,
        );
        const result = this.parseOutput(retained.response, input, model, endpoint);
        return { ...result, warnings: [...result.warnings, CLEANUP_WARNING] };
      }

      const bridgeCode =
        typeof bridgeError?.code === 'string' ? bridgeError.code : 'unknown_bridge_error';
      const bridgeMessage =
        typeof bridgeError?.message === 'string' ? bridgeError.message : 'No error detail.';
      const failure = new ServiceUnavailableException({
        message: `Local Codex request failed (HTTP ${response.status}, ${bridgeCode}): ${bridgeMessage}`,
        code: bridgeCode === 'timeout' ? 'VISION_TIMEOUT' : 'VISION_API_ERROR',
        details: bridgeMessage.slice(0, 500),
      });
      this.logFailure('local-codex', input, model, failure, {
        endpoint,
        status: response.status,
        bridgeCode,
        bridgeMessage,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }

    const result = this.asTurnResult(payload);
    if (!result || result.status !== 'completed') {
      const failure = new ServiceUnavailableException({
        message: 'Local Codex did not return a completed turn.',
        code: 'VISION_API_ERROR',
      });
      this.logFailure('local-codex', input, model, failure, {
        endpoint,
        status: response.status,
        bridgeStatus: result?.status,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }
    if (typeof result.response !== 'string' || !result.response.trim()) {
      const failure = new ServiceUnavailableException({
        message: 'Local Codex returned an empty response.',
        code: 'VISION_EMPTY_RESPONSE',
      });
      this.logFailure('local-codex', input, model, failure, {
        endpoint,
        status: response.status,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }
    if (result.thread_deleted !== true) {
      const failure = new ServiceUnavailableException({
        message: 'Local Codex did not confirm deletion of its one-time conversation.',
        code: 'VISION_API_ERROR',
      });
      this.logFailure('local-codex', input, model, failure, {
        endpoint,
        status: response.status,
        threadDeleted: result.thread_deleted,
        elapsedMs: Date.now() - startedAt,
      });
      throw failure;
    }

    const parsed = this.parseOutput(result.response, input, model, endpoint);
    this.logger.log(
      `Local Codex request completed: ${JSON.stringify({
        endpoint,
        status: response.status,
        elapsedMs: Date.now() - startedAt,
        threadDeleted: true,
      })}`,
    );
    return parsed;
  }

  private parseOutput(
    rawText: string,
    input: ExtractBoardStateInput,
    model: string,
    endpoint: string,
  ): ExtractBoardStateResult {
    try {
      return parseVisionResponse(rawText);
    } catch (err) {
      this.logFailure('vision-invalid', input, model, err, {
        endpoint,
        rawResponseSnippet: rawText.slice(0, 2000),
        parseError: this.describeError(err),
      });
      throw new ServiceUnavailableException({
        message:
          'Local Codex returned a response that could not be read as a Xiangqi board ' +
          '(the screenshot may not clearly show a board).',
        code: 'VISION_INVALID_RESPONSE',
        details: err instanceof Error ? err.message : String(err),
      });
    }
  }

  private asTurnResult(value: unknown): CodexTurnResult | undefined {
    return value !== null && typeof value === 'object' ? (value as CodexTurnResult) : undefined;
  }

  private asErrorEnvelope(value: unknown): CodexErrorEnvelope | undefined {
    return value !== null && typeof value === 'object' ? (value as CodexErrorEnvelope) : undefined;
  }

  private hintText(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    return hint && hint !== 'unknown'
      ? `HINT: The user indicated it is ${hint}'s turn to move.`
      : '';
  }

  /**
   * Extract the useful parts of Node/Undici errors. Node's fetch usually puts
   * the actionable DNS/TCP/TLS reason in `cause`, while the top-level message
   * is only "fetch failed".
   */
  private describeError(value: unknown, depth = 0, seen = new Set<unknown>()): unknown {
    if (depth >= 4) return { truncated: true };
    if (value === null || (typeof value !== 'object' && !(value instanceof Error))) {
      return { value: String(value) };
    }
    if (seen.has(value)) return { circular: true };
    seen.add(value);

    const source = value as Error &
      Record<string, unknown> & {
        cause?: unknown;
        errors?: unknown[];
      };
    const detail: Record<string, unknown> = {
      name: (typeof source.name === 'string' ? source.name : 'Error').slice(0, 200),
      message: (typeof source.message === 'string' ? source.message : String(value)).slice(0, 1000),
    };
    const safeFields = [
      'code',
      'errno',
      'syscall',
      'hostname',
      'host',
      'address',
      'port',
      'localAddress',
    ] as const;
    for (const key of safeFields) {
      const field = source[key];
      if (typeof field === 'string') detail[key] = field.slice(0, 1000);
      else if (typeof field === 'number' || typeof field === 'boolean') detail[key] = field;
    }
    if (source.cause !== undefined) {
      detail.cause = this.describeError(source.cause, depth + 1, seen);
    }
    if (Array.isArray(source.errors)) {
      detail.errors = source.errors
        .slice(0, 8)
        .map((error) => this.describeError(error, depth + 1, seen));
    }
    return detail;
  }

  /** Log bounded diagnostics without the bearer token or raw image bytes. */
  private logFailure(
    category: 'local-codex' | 'vision-invalid',
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
    this.logger.error(`Local Codex failure: ${JSON.stringify({ category, ...fields })}`);
  }
}
