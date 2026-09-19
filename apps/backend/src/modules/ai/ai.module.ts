import { Module } from '@nestjs/common';
import { BoardModule } from '../board/board.module';
import { AiService } from './ai.service';
import { ImagePreprocessService } from './image-preprocess.service';
import { MockVisionProvider } from './providers/mock-vision.provider';
import { GeminiVisionProvider } from './providers/gemini.provider';
import { OpenAiVisionProvider } from './providers/openai.provider';
import { ApikeyFunVisionProvider } from './providers/apikeyfun.provider';
import { LocalCodexVisionProvider } from './providers/local-codex.provider';
import { LocalCodexVisionAllowlist } from './local-codex-vision.allowlist';

/**
 * AI module: exposes the AiService facade and all vision provider
 * implementations, including the device-gated Local Codex backend. The facade
 * selects per request and normalizes (downscale/recompress) uploads before any
 * provider sees them.
 */
@Module({
  imports: [BoardModule],
  providers: [
    AiService,
    ImagePreprocessService,
    MockVisionProvider,
    GeminiVisionProvider,
    OpenAiVisionProvider,
    ApikeyFunVisionProvider,
    LocalCodexVisionProvider,
    LocalCodexVisionAllowlist,
  ],
  exports: [AiService],
})
export class AiModule {}
