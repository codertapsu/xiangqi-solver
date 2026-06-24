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

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const REQUEST_TIMEOUT_MS = 30_000;

/**
 * OpenAI multimodal vision provider. Sends the strict board-extraction prompt
 * plus a base64 data-URL image to the chat completions endpoint and parses the
 * JSON board state. If OPENAI_API_KEY is missing, fails clearly and points the
 * user to provider=mock.
 */
@Injectable()
export class OpenAiVisionProvider implements AiVisionProvider {
  readonly name = 'openai';

  constructor(
    private readonly config: ConfigService,
    private readonly errorLog: ErrorLogService,
  ) {}

  async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    const ai = this.config.get<AppConfig['ai']>('app.ai');
    const apiKey = ai?.openaiApiKey ?? '';
    if (!apiKey) {
      throw new ServiceUnavailableException({
        message:
          'OPENAI_API_KEY is not configured. Set it or use provider=mock for offline analysis.',
        code: 'VISION_UNAVAILABLE',
      });
    }

    const model = input.modelOverride?.trim() || ai?.openaiModel || 'gpt-5.4';
    const maxTokens = ai?.maxOutputTokens ?? 0;
    const maxRetries = ai?.maxRetries ?? 0;
    const dataUrl = `data:${input.mimeType};base64,${input.imageBuffer.toString('base64')}`;

    // The static prompt is a SYSTEM message (identical every call) so OpenAI's
    // automatic prompt caching can reuse it; only the variable turn hint + the
    // image go in the user message. The user-text part is omitted when there's
    // no hint, keeping the cached prefix maximal.
    const userContent: unknown[] = [];
    const hint = this.hintText(input.sideToMoveHint);
    if (hint) userContent.push({ type: 'text', text: hint });
    // "high" detail lets the model resolve the small piece characters on a busy
    // board, which materially improves recognition accuracy.
    userContent.push({ type: 'image_url', image_url: { url: dataUrl, detail: 'high' } });

    const body = {
      model,
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
      // Failed request to the OpenAI API (HTTP error / timeout / empty body).
      this.logFailure('openai', input, model, err);
      throw err;
    }

    try {
      return parseVisionResponse(text);
    } catch (err) {
      // The response came back but could not be turned into a board — i.e. the
      // screenshot could not be extracted. Record the raw output + reason, then
      // surface a clear, stable error to the client.
      this.logFailure('vision-invalid', input, model, err, text);
      throw new ServiceUnavailableException({
        message:
          'OpenAI returned a response that could not be read as a Xiangqi board ' +
          '(the screenshot may not clearly show a board).',
        code: 'VISION_INVALID_RESPONSE',
        details: (err as Error).message,
      });
    }
  }

  /**
   * Append a failure to the date-grouped error log. Captures enough to diagnose
   * (model, image size/type, OpenAI's real reason, and — for an unparseable
   * response — a bounded snippet of the raw model output) WITHOUT logging the
   * API key or the raw image bytes.
   */
  private logFailure(
    category: 'openai' | 'vision-invalid',
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
    // Surface OpenAI's real code/details carried on our ServiceUnavailableException.
    if (err instanceof HttpException) {
      const res = err.getResponse();
      if (res && typeof res === 'object') {
        const o = res as Record<string, unknown>;
        if (typeof o.code === 'string') fields.code = o.code;
        if (o.details !== undefined) fields.openaiDetails = o.details;
      }
    }
    if (rawText !== undefined) fields.rawResponseSnippet = rawText.slice(0, 2000);
    this.errorLog.log(category, fields);
  }

  /** The variable turn hint as a standalone user message (empty when none). */
  private hintText(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    return hint && hint !== 'unknown'
      ? `HINT: The user indicated it is ${hint}'s turn to move.`
      : '';
  }

  /** Best-effort extraction of OpenAI's { error: { message, code } } body. */
  private parseApiError(raw: string): { message?: string; code?: string } {
    try {
      const parsed = JSON.parse(raw) as { error?: { message?: string; code?: string } };
      return { message: parsed.error?.message, code: parsed.error?.code };
    } catch {
      return {};
    }
  }

  /**
   * One OpenAI request. Returns a classified outcome (never throws) so the
   * retry policy can decide: HTTP 429/5xx + timeouts + empty bodies are
   * retryable; a 4xx (bad key / unreadable image) is not.
   */
  private async attempt(apiKey: string, body: unknown): Promise<AttemptResult<string>> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const res = await fetch(OPENAI_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${apiKey}` },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        const apiError = this.parseApiError(detail);
        const hint =
          apiError.code === 'image_parse_error'
            ? ' The screenshot may be too small, corrupted, or not a real image.'
            : '';
        return {
          ok: false,
          retryable: isTransientStatus(res.status),
          error: new ServiceUnavailableException({
            // Include OpenAI's real reason so the cause is visible in logs.
            message:
              `OpenAI API request failed (HTTP ${res.status})` +
              `${apiError.message ? `: ${apiError.message}` : '.'}${hint}`,
            code: apiError.code ?? 'VISION_API_ERROR',
            details: detail.slice(0, 500),
          }),
        };
      }

      const json = (await res.json()) as {
        choices?: { message?: { content?: string }; finish_reason?: string }[];
      };
      const choice = json.choices?.[0];
      const text = choice?.message?.content;
      if (!text) {
        // A truncated completion (finish_reason "length") is DETERMINISTIC —
        // retrying just burns another paid call for the same empty body. Surface
        // it as a clear, non-retryable "raise the cap" error. Other empties are
        // likewise not retried (same temperature-0 request → same empty).
        const truncated = choice?.finish_reason === 'length';
        return {
          ok: false,
          retryable: false,
          error: new ServiceUnavailableException({
            message: truncated
              ? 'OpenAI truncated the response at the output-token cap. Raise VISION_MAX_OUTPUT_TOKENS (a reasoning model needs more) or disable it (0).'
              : 'OpenAI API returned an empty response.',
            code: truncated ? 'VISION_OUTPUT_TRUNCATED' : 'VISION_EMPTY_RESPONSE',
          }),
        };
      }
      return { ok: true, value: text };
    } catch (err) {
      if (err instanceof Error && err.name === 'AbortError') {
        return {
          ok: false,
          retryable: true,
          error: new ServiceUnavailableException({
            message: `OpenAI API timed out after ${REQUEST_TIMEOUT_MS}ms.`,
            code: 'VISION_TIMEOUT',
          }),
        };
      }
      return {
        ok: false,
        retryable: true,
        error: new ServiceUnavailableException({
          message: `OpenAI API request error: ${(err as Error).message}`,
          code: 'VISION_API_ERROR',
        }),
      };
    } finally {
      clearTimeout(timeout);
    }
  }
}
