import { Module } from '@nestjs/common';
import { BoardValidatorService } from './board-validator.service';
import { BoardNormalizerService } from './board-normalizer.service';
import { FenService } from './fen.service';
import { MoveNotationService } from './move-notation.service';

/**
 * Pure domain module: board validation, normalization, FEN conversion, and
 * traditional move notation. Stateless services, easy to unit test and reuse.
 */
@Module({
  providers: [BoardValidatorService, BoardNormalizerService, FenService, MoveNotationService],
  exports: [BoardValidatorService, BoardNormalizerService, FenService, MoveNotationService],
})
export class BoardModule {}
