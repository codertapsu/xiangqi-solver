import { HttpException, Injectable, ServiceUnavailableException } from '@nestjs/common';
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
import { AttemptResult, isTransientStatus, withRetries } from './vision-retry.util';

const APIKEYFUN_URL = 'https://api.apikey.fun/v1/chat/completions';
// Streaming can legitimately run longer than a single-shot call (the proxy may
// queue behind an upstream), so allow more headroom than the direct providers.
const REQUEST_TIMEOUT_MS = 60_000;

/** An OpenAI-style error object, either HTTP-body or in-band SSE `{error:{…}}`. */
type ApiError = { message?: string; code?: string; type?: string };

/**
 * Vision provider backed by api.apikey.fun — an OpenAI-COMPATIBLE aggregator
 * (`/v1/chat/completions`, `Bearer` auth). It is driven over Server-Sent Events
 * (`stream: true`): the deltas are accumulated into the full board JSON, then
 * parsed by the shared parser. The message shape mirrors the OpenAI provider
 * (static prompt as a SYSTEM message for prompt caching; the turn hint + image
 * in the user message), and it reuses the shared retry policy + output-token
 * cap + per-call model override. If APIKEYFUN_API_KEY is missing, it fails
 * clearly and points the user to provider=mock.
 */
@Injectable()
export class ApikeyFunVisionProvider implements AiVisionProvider {
  readonly name = 'apikeyfun';

  constructor(
    private readonly config: ConfigService,
    private readonly errorLog: ErrorLogService,
  ) {}

  async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    const ai = this.config.get<AppConfig['ai']>('app.ai');
    const apiKey = ai?.apikeyfunApiKey ?? '';
    if (!apiKey) {
      throw new ServiceUnavailableException({
        message:
          'APIKEYFUN_API_KEY is not configured. Set it or use provider=mock for offline analysis.',
        code: 'VISION_UNAVAILABLE',
      });
    }

    const model = input.modelOverride?.trim() || ai?.apikeyfunModel || 'gpt-5.5';
    const maxTokens = ai?.maxOutputTokens ?? 0;
    const maxRetries = ai?.maxRetries ?? 0;
    const dataUrl = `data:${input.mimeType};base64,${input.imageBuffer.toString('base64')}`;

    // Static prompt as a SYSTEM message (identical every call → prompt-cacheable);
    // only the variable turn hint + image go in the user message.
    const userContent: unknown[] = [];
    const hint = this.hintText(input.sideToMoveHint);
    if (hint) userContent.push({ type: 'text', text: hint });
    userContent.push({ type: 'image_url', image_url: { url: dataUrl } });

    const body = {
      model,
      stream: true,
      temperature: 0,
      response_format: { type: 'json_object' },
      ...(maxTokens > 0 ? { max_completion_tokens: maxTokens } : {}),
      messages: [
        { role: 'system', content: BOARD_EXTRACTION_PROMPT },
        { role: 'user', content: userContent },
      ],
    };

    let text: string;
    try {
      text = await withRetries(maxRetries, () => this.attempt(apiKey, body));
    } catch (err) {
      this.logFailure('apikeyfun', input, model, err);
      throw err;
    }

    try {
      return parseVisionResponse(text);
    } catch (err) {
      this.logFailure('vision-invalid', input, model, err, text);
      throw new ServiceUnavailableException({
        message:
          'api.apikey.fun returned a response that could not be read as a Xiangqi board ' +
          '(the screenshot may not clearly show a board).',
        code: 'VISION_INVALID_RESPONSE',
        details: (err as Error).message,
      });
    }
  }

  /**
   * One streamed request. Returns a classified outcome (never throws) so the
   * retry policy can decide: HTTP 429/5xx + timeouts + network errors are
   * retryable; a 4xx (bad key / unreadable image) and an empty/truncated body
   * are not.
   */
  private async attempt(apiKey: string, body: unknown): Promise<AttemptResult<string>> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const res = await fetch(APIKEYFUN_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        const apiError = this.parseApiError(detail);
        return {
          ok: false,
          retryable: isTransientStatus(res.status),
          error: new ServiceUnavailableException({
            message:
              `api.apikey.fun request failed (HTTP ${res.status})` +
              `${apiError.message ? `: ${apiError.message}` : '.'}`,
            code: apiError.code ?? 'VISION_API_ERROR',
            details: detail.slice(0, 500),
          }),
        };
      }

      const { content, finishReason, apiError } = await this.readStream(res);

      // An OpenAI-compatible aggregator commonly commits HTTP 200 + SSE headers
      // and THEN relays an upstream failure IN-BAND as a `data: {"error":{...}}`
      // frame. The non-200 path never sees it (the status was already 200), so
      // handle it here: surface the real upstream reason and retry it when it
      // looks transient (rate-limit / overloaded / upstream 5xx).
      if (apiError) {
        const upstream = [apiError.code, apiError.message].filter(Boolean).join(': ');
        return {
          ok: false,
          retryable: this.isTransientApiError(apiError),
          error: new ServiceUnavailableException({
            message: `api.apikey.fun upstream error${upstream ? `: ${upstream}` : '.'}`,
            code: 'VISION_API_ERROR',
            details: upstream || undefined,
          }),
        };
      }

      // Truncated at the output-token cap (finish_reason "length"): the JSON is
      // incomplete whether the delta was empty or a partial object, so a re-send
      // is deterministic (don't retry) and the remedy is to raise the cap. Check
      // BEFORE the empty guard so a partial-then-truncated stream is diagnosed
      // as a token-cap issue, not misread as an unclear screenshot downstream.
      if (finishReason === 'length') {
        return {
          ok: false,
          retryable: false,
          error: new ServiceUnavailableException({
            message:
              'api.apikey.fun truncated the response at the output-token cap. Raise VISION_MAX_OUTPUT_TOKENS or disable it (0).',
            code: 'VISION_OUTPUT_TRUNCATED',
          }),
        };
      }

      if (!content) {
        return {
          ok: false,
          retryable: false,
          error: new ServiceUnavailableException({
            message: 'api.apikey.fun returned an empty response.',
            code: 'VISION_EMPTY_RESPONSE',
          }),
        };
      }
      return { ok: true, value: content };
    } catch (err) {
      if (err instanceof Error && err.name === 'AbortError') {
        return {
          ok: false,
          retryable: true,
          error: new ServiceUnavailableException({
            message: `api.apikey.fun timed out after ${REQUEST_TIMEOUT_MS}ms.`,
            code: 'VISION_TIMEOUT',
          }),
        };
      }
      return {
        ok: false,
        retryable: true,
        error: new ServiceUnavailableException({
          message: `api.apikey.fun request error: ${(err as Error).message}`,
          code: 'VISION_API_ERROR',
        }),
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Read the SSE stream: accumulate `choices[].delta.content` across frames,
   * capture the final `finish_reason`, and surface any in-band `{"error":{…}}`
   * frame the aggregator relays after a 200. Frames are `data:` lines separated
   * by a blank line; `[DONE]` ends the stream. Malformed frames are skipped.
   */
  private async readStream(
    res: Response,
  ): Promise<{ content: string; finishReason?: string; apiError?: ApiError }> {
    const stream = res.body;
    if (!stream) return { content: '' };
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    let content = '';
    let finishReason: string | undefined;
    let apiError: ApiError | undefined;

    const consume = (frame: string): void => {
      const data = frame
        .split(/\r?\n/)
        .filter((line) => line.startsWith('data:'))
        .map((line) => line.slice(5).trim())
        .join('\n');
      if (!data || data === '[DONE]') return;
      try {
        const chunk = JSON.parse(data) as {
          choices?: { delta?: { content?: string }; finish_reason?: string }[];
          error?: ApiError;
        };
        // An in-band upstream failure (HTTP 200, then `data: {"error":{…}}`) —
        // keep the first one so attempt() can classify + surface the real cause.
        if (chunk.error && !apiError) {
          apiError = {
            message: chunk.error.message,
            code: chunk.error.code,
            type: chunk.error.type,
          };
        }
        for (const choice of chunk.choices ?? []) {
          content += choice.delta?.content ?? '';
          if (choice.finish_reason) finishReason = choice.finish_reason;
        }
      } catch {
        // A partial/keepalive/non-JSON frame — skip it.
      }
    };

    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const frames = buffer.split(/\r?\n\r?\n/);
        buffer = frames.pop() ?? ''; // keep the last (possibly incomplete) frame
        for (const frame of frames) consume(frame);
      }
      // Flush any pending multi-byte char and process a FINAL frame that ended
      // without a trailing blank line (some servers omit it before closing).
      buffer += decoder.decode();
      if (buffer.trim()) consume(buffer);
    } finally {
      reader.releaseLock();
    }
    return { content, finishReason, apiError };
  }

  /**
   * True when an in-band upstream error looks transient (worth a retry): a
   * rate-limit, an overload, or an upstream 5xx surfaced as an OpenAI-style
   * error object. Permanent errors (bad request, auth, quota) are not retried.
   */
  private isTransientApiError(err: ApiError): boolean {
    const s = `${err.code ?? ''} ${err.type ?? ''}`.toLowerCase();
    return (
      s.includes('rate_limit') ||
      s.includes('overloaded') ||
      s.includes('server_error') ||
      s.includes('unavailable') ||
      s.includes('timeout') ||
      s.includes('try_again') ||
      s.includes('temporarily')
    );
  }

  /** The variable turn hint as a standalone user message (empty when none). */
  private hintText(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    return hint && hint !== 'unknown'
      ? `HINT: The user indicated it is ${hint}'s turn to move.`
      : '';
  }

  /** Best-effort extraction of an OpenAI-style { error: { message, code } } body. */
  private parseApiError(raw: string): { message?: string; code?: string } {
    try {
      const parsed = JSON.parse(raw) as { error?: { message?: string; code?: string } };
      return { message: parsed.error?.message, code: parsed.error?.code };
    } catch {
      return {};
    }
  }

  /** Append a failure to the date-grouped error log (never the key/image bytes). */
  private logFailure(
    category: 'apikeyfun' | 'vision-invalid',
    input: ExtractBoardStateInput,
    model: string,
    err: unknown,
    rawText?: string,
  ): void {
    const fields: ErrorLogFields = {
      message: err instanceof Error ? err.message : String(err),
      provider: this.name,
      model,
      imageBytes: input.imageBuffer.byteLength,
      mimeType: input.mimeType,
      sideToMoveHint: input.sideToMoveHint,
    };
    if (err instanceof HttpException) {
      const res = err.getResponse();
      if (res && typeof res === 'object') {
        const o = res as Record<string, unknown>;
        if (typeof o.code === 'string') fields.code = o.code;
        if (o.details !== undefined) fields.apiDetails = o.details;
      }
    }
    if (rawText !== undefined) fields.rawResponseSnippet = rawText.slice(0, 2000);
    this.errorLog.log(category, fields);
  }
}
