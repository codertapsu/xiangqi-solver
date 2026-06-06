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

  constructor(private readonly config: ConfigService) {}

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

    const model = ai?.openaiModel ?? 'gpt-5.4';
    const dataUrl = `data:${input.mimeType};base64,${input.imageBuffer.toString('base64')}`;

    const body = {
      model,
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: this.buildPrompt(input.sideToMoveHint) },
            // "high" detail lets the model resolve the small piece characters on
            // a busy board, which materially improves recognition accuracy.
            { type: 'image_url', image_url: { url: dataUrl, detail: 'high' } },
          ],
        },
      ],
    };

    const text = await this.callApi(apiKey, body);
    return parseVisionResponse(text);
  }

  private buildPrompt(hint?: ExtractBoardStateInput['sideToMoveHint']): string {
    if (hint && hint !== 'unknown') {
      return `${BOARD_EXTRACTION_PROMPT}\n\nHINT: The user indicated it is ${hint}'s turn to move.`;
    }
    return BOARD_EXTRACTION_PROMPT;
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

  private async callApi(apiKey: string, body: unknown): Promise<string> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const res = await fetch(OPENAI_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
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
        throw new ServiceUnavailableException({
          // Include OpenAI's real reason so the cause is visible in logs, not
          // just a bare HTTP status.
          message:
            `OpenAI API request failed (HTTP ${res.status})` +
            `${apiError.message ? `: ${apiError.message}` : '.'}${hint}`,
          code: apiError.code ?? 'VISION_API_ERROR',
          details: detail.slice(0, 500),
        });
      }

      const json = (await res.json()) as {
        choices?: { message?: { content?: string } }[];
      };
      const text = json.choices?.[0]?.message?.content;
      if (!text) {
        throw new ServiceUnavailableException({
          message: 'OpenAI API returned an empty response.',
          code: 'VISION_EMPTY_RESPONSE',
        });
      }
      return text;
    } catch (err) {
      if (err instanceof ServiceUnavailableException) throw err;
      if (err instanceof Error && err.name === 'AbortError') {
        throw new ServiceUnavailableException({
          message: `OpenAI API timed out after ${REQUEST_TIMEOUT_MS}ms.`,
          code: 'VISION_TIMEOUT',
        });
      }
      throw new ServiceUnavailableException({
        message: `OpenAI API request error: ${(err as Error).message}`,
        code: 'VISION_API_ERROR',
      });
    } finally {
      clearTimeout(timeout);
    }
  }
}
