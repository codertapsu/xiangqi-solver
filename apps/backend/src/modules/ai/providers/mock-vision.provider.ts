import { Injectable } from '@nestjs/common';
import {
  AiVisionProvider,
  ExtractBoardStateInput,
  ExtractBoardStateResult,
} from '../ai-provider.interface';
import { buildStartPosition } from '../../board/start-position';

/**
 * Deterministic offline vision provider. Always "detects" the standard
 * 32-piece Xiangqi start position so the full pipeline runs with zero
 * configuration and no external API. Never inspects the image bytes.
 */
@Injectable()
export class MockVisionProvider implements AiVisionProvider {
  readonly name = 'mock';

  extractBoardState(input: ExtractBoardStateInput): Promise<ExtractBoardStateResult> {
    const sideToMove =
      input.sideToMoveHint && input.sideToMoveHint !== 'unknown' ? input.sideToMoveHint : 'red';

    return Promise.resolve({
      boardDetected: true,
      sideToMove,
      confidence: 0.9,
      pieces: buildStartPosition(),
      warnings: [],
    });
  }
}
