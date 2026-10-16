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

const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/models';
const REQUEST_TIMEOUT_MS = 30_000;

/**
 * Google Gemini multimodal vision provider. Sends the strict board-extraction
 * prompt + the base64 image to the generateContent endpoint and parses the
 * JSON board state from the response. If GEMINI_API_KEY is missing, fails with
 * a clear ServiceUnavailable error pointing the user to provider=mock.
 */
@Injectable()
export class GeminiVisionProvider implements AiVisionProvider {
  readonly name = 'gemini';

  constructor(
    private readonly config: ConfigService,
    private readonly errorLog: ErrorLogService,
  ) {}

  async extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    const ai = this.config.get<AppConfig['ai']>('app.ai');
    const apiKey = ai?.geminiApiKey ?? '';
    if (!apiKey) {
      throw new ServiceUnavailableException({
        message:
          'GEMINI_API_KEY is not configured. Set it or use provider=mock for offline analysis.',
        code: 'VISION_UNAVAILABLE',
      });
    }

    const model = input.modelOverride?.trim() || ai?.geminiModel || 'gemini-3.5-flash';
    const maxTokens = ai?.maxOutputTokens ?? 0;
    const maxRetries = ai?.maxRetries ?? 0;
    const url = `${GEMINI_BASE_URL}/${encodeURIComponent(model)}:generateContent`;

    // The static prompt is a `systemInstruction` (identical every call) so
    // Gemini's implicit prompt caching can reuse it; only the variable turn hint
    // + image go in the user content. The hint part is omitted when absent.
    const parts: unknown[] = [];
    const hint = this.hintText(input.sideToMoveHint);
    if (hint) parts.push({ text: hint });
    parts.push({
      inline_data: { mime_type: input.mimeType, data: input.imageBuffer.toString('base64') },
    });

    const body = {
      systemInstruction: { parts: [{ text: BOARD_EXTRACTION_PROMPT }] },
      contents: [{ role: 'user', parts }],
      generationConfig: {
        temperature: 0,
        responseMimeType: 'application/json',
        ...(maxTokens > 0 ? { maxOutputTokens: maxTokens } : {}),
      },
    };

    let text: string;
    try {
      text = await withRetries(maxRetries, () => this.attempt(url, apiKey, body));
    } catch (err) {
      this.logFailure('gemini', input, model, err);
      throw err;
    }

    try {
      return parseVisionResponse(text);
    } catch (err) {
      // Parity with the OpenAI provider: record the unreadable response and
      // surface the same stable, user-explainable error code instead of a 500.
      this.logFailure('vision-invalid', input, model, err, text);
      throw new ServiceUnavailableException({
        message:
          'Gemini returned a response that could not be read as a Xiangqi board ' +
          '(the screenshot may not clearly show a board).',
        code: 'VISION_INVALID_RESPONSE',
        details: (err as Error).message,
      });
    }
  }

  /** Append a failure to the date-grouped error log (never the key/image bytes). */
  private logFailure(
    category: 'gemini' | 'vision-invalid',
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
    // Google's real reason travels on the DIAGNOSTIC channel only (never in the
    // exception body the client sees) — copy it into the log here.
    if (err instanceof VisionApiError) {
      fields.code = err.code;
      Object.assign(fields, err.diagnostics);
    } else if (err instanceof HttpException) {
      const res = err.getResponse();
      if (res && typeof res === 'object') {
        const o = res as Record<string, unknown>;
        if (typeof o.code === 'string') fields.code = o.code;
        if (o.details !== undefined) fields.geminiDetails = o.details;
      }
    }
    if (rawText !== undefined) fields.rawResponseSnippet = rawText.slice(0, 2000);
    this.errorLog.log(category, fields);
  }

  /** The variable turn hint as a standalone user part (empty when none). */
  private hintText(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    return hint && hint !== 'unknown'
      ? `HINT: The user indicated it is ${hint}'s turn to move.`
      : '';
  }

  /**
   * One Gemini request. Returns a classified outcome (never throws) so the
   * retry policy can decide: 429/5xx, timeouts and transport errors are
   * retryable; a 4xx (bad key / unreadable image), a truncated response and an
   * empty body are not — re-asking at temperature 0 reproduces them.
   */
  private async attempt(
    url: string,
    apiKey: string,
    body: unknown,
  ): Promise<AttemptResult<string>> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!res.ok) {
        const detail = await res.text().catch(() => '');
        return {
          ok: false,
          retryable: isTransientStatus(res.status),
          // Fixed user-facing message + stable code, identical to the other
          // cloud providers; Google's own reason is log-only diagnostics.
          error: vendorHttpFailure(res.status, detail),
        };
      }

      const json = (await res.json()) as {
        candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
      };
      const candidate = json.candidates?.[0];
      const text = candidate?.content?.parts?.map((p) => p.text ?? '').join('');

      // finishReason "MAX_TOKENS" = truncated at the output cap. Checked BEFORE
      // emptiness because the model may emit PART of the JSON and then hit the
      // cap: that partial body is non-empty, would fail in parseVisionResponse,
      // and the user would be told their screenshot was unclear when the real
      // cause is the token cap. Deterministic, so it is never retried.
      if (candidate?.finishReason === 'MAX_TOKENS') {
        return {
          ok: false,
          retryable: false,
          error: truncationFailure(
            'Gemini truncated the response at the output-token cap. Raise VISION_MAX_OUTPUT_TOKENS (its thinking budget counts against this) or disable it (0).',
          ),
        };
      }

      if (!text) {
        // Not retried either: the same temperature-0 request yields the same empty.
        return {
          ok: false,
          retryable: false,
          error: new ServiceUnavailableException({
            message: 'Gemini API returned an empty response.',
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
            message: `Gemini API timed out after ${REQUEST_TIMEOUT_MS}ms.`,
            code: 'VISION_TIMEOUT',
          }),
        };
      }
      // Node's transport text names hosts and error codes — diagnostics, not a
      // sentence to render in the app.
      return { ok: false, retryable: true, error: transportFailure(err) };
    } finally {
      clearTimeout(timeout);
    }
  }
}
