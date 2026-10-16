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
import {
  transportFailure,
  truncationFailure,
  vendorHttpFailure,
  VisionApiError,
} from './vision-api-error';

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
    // OpenAI's real reason travels on the DIAGNOSTIC channel only (never in the
    // exception body the client sees) — copy it into the log here.
    if (err instanceof VisionApiError) {
      fields.code = err.code;
      Object.assign(fields, err.diagnostics);
    } else if (err instanceof HttpException) {
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

  /**
   * One OpenAI request. Returns a classified outcome (never throws) so the
   * retry policy can decide: HTTP 429/5xx, timeouts and transport errors are
   * retryable; a 4xx (bad key / unreadable image), a truncated completion and an
   * empty body are not — re-asking at temperature 0 reproduces them.
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
        return {
          ok: false,
          retryable: isTransientStatus(res.status),
          // Fixed user-facing message + stable code; OpenAI's own reason (which
          // embeds the masked key and a billing URL on a 401) is carried as
          // log-only diagnostics.
          error: vendorHttpFailure(res.status, detail),
        };
      }

      const json = (await res.json()) as {
        choices?: { message?: { content?: string }; finish_reason?: string }[];
      };
      const choice = json.choices?.[0];
      const text = choice?.message?.content;

      // Truncated at the output-token cap (finish_reason "length"): the JSON is
      // incomplete whether the content was empty or a PARTIAL object, so this is
      // checked BEFORE emptiness. A partial body that skipped this guard would
      // fail in parseVisionResponse and be reported to the user as an unclear
      // screenshot — sending them to retake a screenshot that was never the
      // problem. Deterministic, so it is never retried; the remedy is the cap.
      if (choice?.finish_reason === 'length') {
        return {
          ok: false,
          retryable: false,
          error: truncationFailure(
            'OpenAI truncated the response at the output-token cap. Raise VISION_MAX_OUTPUT_TOKENS (a reasoning model needs more) or disable it (0).',
          ),
        };
      }

      if (!text) {
        // Not retried either: the same temperature-0 request yields the same empty.
        return {
          ok: false,
          retryable: false,
          error: new ServiceUnavailableException({
            message: 'OpenAI API returned an empty response.',
            code: 'VISION_EMPTY_RESPONSE',
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
      // Node's transport text ("getaddrinfo ENOTFOUND api.openai.com") is a
      // diagnostic, not something to render in the app.
      return { ok: false, retryable: true, error: transportFailure(err) };
    } finally {
      clearTimeout(timeout);
    }
  }
}
