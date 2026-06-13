import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../../config/configuration';
import {
  AiVisionProvider,
  ExtractBoardStateInput,
  ExtractBoardStateResult,
} from '../ai-provider.interface';
import { BOARD_EXTRACTION_PROMPT } from '../prompts/board-extraction.prompt';
import { parseVisionResponse } from '../vision-response.schema';
import { ErrorLogService } from '../../logging/error-log.service';

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

    const model = ai?.geminiModel ?? 'gemini-3.5-flash';
    const url = `${GEMINI_BASE_URL}/${encodeURIComponent(model)}:generateContent`;

    const body = {
      contents: [
        {
          role: 'user',
          parts: [
            { text: this.buildPrompt(input.sideToMoveHint) },
            {
              inline_data: {
                mime_type: input.mimeType,
                data: input.imageBuffer.toString('base64'),
              },
            },
          ],
        },
      ],
      generationConfig: { temperature: 0, responseMimeType: 'application/json' },
    };

    let text: string;
    try {
      text = await this.callApi(url, apiKey, body);
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
    this.errorLog.log(category, {
      message: err instanceof Error ? err.message : String(err),
      provider: this.name,
      model,
      imageBytes: input.imageBuffer.byteLength,
      mimeType: input.mimeType,
      sideToMoveHint: input.sideToMoveHint,
      ...(rawText !== undefined ? { rawResponseSnippet: rawText.slice(0, 2000) } : {}),
    });
  }

  private buildPrompt(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    if (hint && hint !== 'unknown') {
      return `${BOARD_EXTRACTION_PROMPT}\n\nHINT: The user indicated it is ${hint}'s turn to move.`;
    }
    return BOARD_EXTRACTION_PROMPT;
  }

  private async callApi(url: string, apiKey: string, body: unknown): Promise<string> {
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
        throw new ServiceUnavailableException({
          message: `Gemini API request failed (HTTP ${res.status}).`,
          code: 'VISION_API_ERROR',
          details: detail.slice(0, 500),
        });
      }

      const json = (await res.json()) as {
        candidates?: { content?: { parts?: { text?: string }[] } }[];
      };
      const text = json.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('');
      if (!text) {
        throw new ServiceUnavailableException({
          message: 'Gemini API returned an empty response.',
          code: 'VISION_EMPTY_RESPONSE',
        });
      }
      return text;
    } catch (err) {
      if (err instanceof ServiceUnavailableException) throw err;
      if (err instanceof Error && err.name === 'AbortError') {
        throw new ServiceUnavailableException({
          message: `Gemini API timed out after ${REQUEST_TIMEOUT_MS}ms.`,
          code: 'VISION_TIMEOUT',
        });
      }
      throw new ServiceUnavailableException({
        message: `Gemini API request error: ${(err as Error).message}`,
        code: 'VISION_API_ERROR',
      });
    } finally {
      clearTimeout(timeout);
    }
  }
}
