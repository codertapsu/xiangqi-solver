import { Module } from '@nestjs/common';
import { BoardModule } from '../board/board.module';
import { AiService } from './ai.service';
import { MockVisionProvider } from './providers/mock-vision.provider';
import { GeminiVisionProvider } from './providers/gemini.provider';
import { OpenAiVisionProvider } from './providers/openai.provider';

/**
 * AI module: exposes the AiService facade and all vision provider
 * implementations (mock + Gemini + OpenAI). The facade selects per-request.
 */
@Module({
  imports: [BoardModule],
  providers: [AiService, MockVisionProvider, GeminiVisionProvider, OpenAiVisionProvider],
  exports: [AiService],
})
export class AiModule {}
