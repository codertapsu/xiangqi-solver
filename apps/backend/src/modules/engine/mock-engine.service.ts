import { Injectable } from '@nestjs/common';
import { BoardPosition } from '../board/xiangqi.types';
import { EngineBestMoveInput, EngineBestMoveResult, XiangqiEngine } from './engine.interface';
import { moveToUci } from './uci.util';

/**
 * Deterministic offline engine used for development and tests. Returns a
 * fixed, legal-looking opening move depending on the side to move so the
 * whole pipeline can run with zero configuration.
 *
 *  - Red to move (default):  b2e2  -> {from:{1,2}, to:{4,2}}  (cannon to center)
 *  - Black to move:          b7e7  -> {from:{1,7}, to:{4,7}}
 *  - score "+0.30", depth = requested depth.
 */
@Injectable()
export class MockEngineService implements XiangqiEngine {
  readonly name = 'mock';

  private readonly redMove = {
    from: { file: 1, rank: 2 } as BoardPosition,
    to: { file: 4, rank: 2 } as BoardPosition,
  };

  private readonly blackMove = {
    from: { file: 1, rank: 7 } as BoardPosition,
    to: { file: 4, rank: 7 } as BoardPosition,
  };

  getBestMove(input: EngineBestMoveInput): Promise<EngineBestMoveResult> {
    const { from, to } = input.sideToMove === 'black' ? this.blackMove : this.redMove;
    const uci = moveToUci(from, to);

    return Promise.resolve({
      uci,
      from,
      to,
      score: '+0.30',
      depth: input.depth,
      raw: `mock bestmove ${uci}`,
    });
  }
}
