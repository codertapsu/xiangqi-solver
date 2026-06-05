import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { v4 as uuidv4 } from 'uuid';
import { AppConfig } from '../../config/configuration';
import { AiService, AiProviderName } from '../ai/ai.service';
import { ExtractBoardStateResult } from '../ai/ai-provider.interface';
import { BoardValidatorService } from '../board/board-validator.service';
import { BoardNormalizerService } from '../board/board-normalizer.service';
import { FenService } from '../board/fen.service';
import { MoveNotationService, NotationLanguage } from '../board/move-notation.service';
import { BoardPiece, NormalizedBoard, SideToMove } from '../board/xiangqi.types';
import { EngineService, EngineProviderName } from '../engine/engine.service';
import { EngineBestMoveResult } from '../engine/engine.interface';
import { AnalysisBestMove, AnalysisResult, ExtractionResult } from './analysis.types';

/** Engine tuning resolved from request + config defaults. */
interface EngineOptions {
  engineProvider?: EngineProviderName;
  engineDepth?: number;
  engineMoveTimeMs?: number;
  engineThreads?: number;
  engineHashMb?: number;
  engineMultiPv?: number;
}

/** Parameters for the board (no-vision) analysis path. */
export interface AnalyzeBoardParams extends EngineOptions {
  sideToMove: SideToMove;
  pieces: BoardPiece[];
  language?: NotationLanguage;
}

/** Parameters for the screenshot (vision) analysis path. */
export interface AnalyzeScreenshotParams extends EngineOptions {
  imageBuffer: Buffer;
  mimeType: string;
  provider?: AiProviderName;
  sideToMove?: SideToMove;
  language?: NotationLanguage;
}

/** Parameters for the vision-only board extraction (no engine). */
export interface ExtractScreenshotParams {
  imageBuffer: Buffer;
  mimeType: string;
  provider?: AiProviderName;
  sideToMove?: SideToMove;
}

/**
 * Orchestrates the product flow:
 *   (screenshot) vision -> validate + normalize -> FEN -> engine -> explain.
 * The /board path skips vision and feeds pieces straight into the pipeline.
 */
@Injectable()
export class AnalysisService {
  private readonly logger = new Logger(AnalysisService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly aiService: AiService,
    private readonly engineService: EngineService,
    private readonly validator: BoardValidatorService,
    private readonly normalizer: BoardNormalizerService,
    private readonly fenService: FenService,
    private readonly notation: MoveNotationService,
  ) {}

  /** Vision path: extract board from image, then run the engine pipeline. */
  async analyzeScreenshot(params: AnalyzeScreenshotParams): Promise<AnalysisResult> {
    const { visionName, pieces, sideToMove, visionWarnings } = await this.runVision(params);
    return this.runPipeline({
      pieces,
      sideToMove,
      visionProvider: visionName,
      visionOk: true,
      incomingWarnings: visionWarnings,
      engineOptions: params,
      language: params.language,
      // Vision output is imperfect: repair the board rather than 400 the whole
      // analysis on a single mis-read piece.
      lenient: true,
    });
  }

  /**
   * Vision-only path: recognize the board from an image and return it WITHOUT
   * running the engine. Powers POST /api/analysis/extract — a client (e.g. a
   * future on-device engine) can then compute the move locally.
   */
  async extractBoard(params: ExtractScreenshotParams): Promise<ExtractionResult> {
    const { visionName, pieces, sideToMove, visionWarnings } = await this.runVision(params);
    // Repair the (imperfect) AI board; throws NO_BOARD_DETECTED on an empty one.
    const { board, fen } = this.prepareBoard(pieces, sideToMove, visionWarnings, true);
    return {
      extractionId: uuidv4(),
      board: {
        sideToMove: board.sideToMove,
        fen,
        pieces: board.pieces,
        confidence: board.confidence,
      },
      warnings: board.warnings,
      vision: { provider: visionName, ok: true },
    };
  }

  /**
   * Run the AI vision provider and resolve the authoritative side to move. The
   * caller's explicit side (e.g. "I am Red") overrides the vision guess; a
   * mismatch is surfaced as a warning.
   */
  private async runVision(params: ExtractScreenshotParams): Promise<{
    visionName: string;
    pieces: BoardPiece[];
    sideToMove: SideToMove;
    visionWarnings: string[];
  }> {
    const visionName = params.provider ?? this.aiService.defaultProvider;
    let extraction: ExtractBoardStateResult;
    try {
      extraction = await this.aiService.extractBoardState(
        {
          imageBuffer: params.imageBuffer,
          mimeType: params.mimeType,
          sideToMoveHint: params.sideToMove,
        },
        params.provider,
      );
    } catch (err) {
      // Surface provider errors (e.g. missing key) directly to the caller.
      this.logger.warn(`Vision extraction failed via "${visionName}": ${(err as Error).message}`);
      throw err;
    }

    const visionWarnings = [...extraction.warnings];
    if (!extraction.boardDetected) {
      visionWarnings.push('Vision provider did not confidently detect a board.');
    }

    let sideToMove: SideToMove;
    if (params.sideToMove && params.sideToMove !== 'unknown') {
      sideToMove = params.sideToMove;
      if (extraction.sideToMove !== 'unknown' && extraction.sideToMove !== params.sideToMove) {
        visionWarnings.push(
          `You selected ${params.sideToMove} to move, but the image looked like ` +
            `${extraction.sideToMove} to move. Using your selection (${params.sideToMove}).`,
        );
      }
    } else {
      sideToMove = extraction.sideToMove;
    }

    return { visionName, pieces: extraction.pieces, sideToMove, visionWarnings };
  }

  /** No-vision path: pieces are supplied directly. */
  async analyzeBoard(params: AnalyzeBoardParams): Promise<AnalysisResult> {
    return this.runPipeline({
      pieces: params.pieces,
      sideToMove: params.sideToMove,
      // vision is bypassed but reported for a consistent envelope shape.
      visionProvider: 'none',
      visionOk: true,
      incomingWarnings: [],
      engineOptions: params,
      language: params.language,
      // Explicit input is expected to be correct; validate strictly.
      lenient: false,
    });
  }

  /** Shared core: validate -> normalize -> FEN -> engine -> explanation. */
  private async runPipeline(args: {
    pieces: BoardPiece[];
    sideToMove: SideToMove;
    visionProvider: string;
    visionOk: boolean;
    incomingWarnings: string[];
    engineOptions: EngineOptions;
    language?: NotationLanguage;
    lenient: boolean;
  }): Promise<AnalysisResult> {
    const analysisId = uuidv4();
    const language: NotationLanguage = args.language ?? 'en';

    // 1-3. Repair/validate -> normalize -> FEN (shared with /extract).
    const { pieces, board, fen } = this.prepareBoard(
      args.pieces,
      args.sideToMove,
      args.incomingWarnings,
      args.lenient,
    );

    // 4. Run the engine — but only if both generals are present (a position
    //    without a king is illegal and not solvable). On an imperfect capture we
    //    return the board + a clear warning instead of failing the request.
    const engineName = args.engineOptions.engineProvider ?? this.engineService.defaultProvider;
    const engineDefaults = this.config.get<AppConfig['engine']>('app.engine');
    const depth = args.engineOptions.engineDepth ?? engineDefaults?.defaultDepth ?? 12;
    const moveTimeMs =
      args.engineOptions.engineMoveTimeMs ?? engineDefaults?.defaultMoveTimeMs ?? 1000;

    const warnings = [...board.warnings];
    let bestMove: AnalysisBestMove | null = null;
    let candidates: AnalysisBestMove[] = [];
    let engineOk = true;

    const missingGenerals = this.missingGenerals(pieces);
    if (missingGenerals) {
      engineOk = false;
      warnings.push(
        `Could not locate ${missingGenerals}, so the best move was not computed. ` +
          'Re-capture with a clearer, unobstructed view of the board ' +
          '(framing just the board with a capture area helps).',
      );
    } else {
      try {
        const result: EngineBestMoveResult = await this.engineService.getBestMove(
          {
            fen,
            sideToMove: board.sideToMove,
            depth,
            moveTimeMs,
            // Undefined values fall back to engine config defaults.
            threads: args.engineOptions.engineThreads,
            hashMb: args.engineOptions.engineHashMb,
            multiPv: args.engineOptions.engineMultiPv,
          },
          args.engineOptions.engineProvider,
        );
        // Describe each move in traditional, localized Xiangqi notation using the
        // pre-move board (board.pieces) to identify the moving piece.
        const described = this.notation.describe({
          from: result.from,
          to: result.to,
          pieces: board.pieces,
          language,
        });
        bestMove = {
          from: result.from,
          to: result.to,
          uci: result.uci,
          human: described.human,
          notation: described.wxf,
          score: result.score,
          depth: result.depth,
        };
        // When MultiPV > 1, surface the ranked candidate moves (localized).
        candidates = (result.multipv ?? []).map((line) => {
          const d = this.notation.describe({
            from: line.from,
            to: line.to,
            pieces: board.pieces,
            language,
          });
          return {
            from: line.from,
            to: line.to,
            uci: line.uci,
            human: d.human,
            notation: d.wxf,
            score: line.score,
            depth: line.depth,
          };
        });
      } catch (err) {
        engineOk = false;
        warnings.push(`Engine "${engineName}" failed: ${(err as Error).message}`);
        this.logger.warn(`Engine "${engineName}" failed: ${(err as Error).message}`);
      }
    }

    const explanation = this.buildExplanation(board, bestMove, language);

    return {
      analysisId,
      board: {
        sideToMove: board.sideToMove,
        fen,
        pieces: board.pieces,
        confidence: board.confidence,
      },
      bestMove,
      candidates,
      explanation,
      warnings,
      engine: { provider: engineName, ok: engineOk },
      vision: { provider: args.visionProvider, ok: args.visionOk },
    };
  }

  /**
   * Repair (lenient/AI) or strictly validate the raw pieces, then normalize and
   * convert to FEN. Throws NO_BOARD_DETECTED (lenient) or INVALID_BOARD (strict).
   */
  private prepareBoard(
    rawPieces: BoardPiece[],
    sideToMove: SideToMove,
    incomingWarnings: string[],
    lenient: boolean,
  ): { pieces: BoardPiece[]; board: NormalizedBoard; fen: string } {
    let pieces: BoardPiece[];
    const preWarnings: string[] = [];
    if (lenient) {
      const repaired = this.validator.repair(rawPieces);
      pieces = repaired.pieces;
      preWarnings.push(...repaired.warnings);
      if (pieces.length === 0) {
        throw new BadRequestException({
          message: 'No Xiangqi board was detected in the screenshot.',
          code: 'NO_BOARD_DETECTED',
          details: [
            'Make sure the whole board is clearly visible, then try again. ' +
              'Tip: in Solver Mode use “Select capture area” to frame just the board.',
          ],
        });
      }
    } else {
      preWarnings.push(...this.validator.validateOrThrow(rawPieces));
      pieces = rawPieces;
    }

    const board = this.normalizer.normalize(pieces, sideToMove, [
      ...incomingWarnings,
      ...preWarnings,
    ]);
    const fen = this.fenService.toFen(board.pieces, board.sideToMove);
    return { pieces, board, fen };
  }

  /** A human phrase for any absent general(s), or null when both are present. */
  private missingGenerals(pieces: BoardPiece[]): string | null {
    const hasRed = pieces.some((p) => p.type === 'king' && p.color === 'red');
    const hasBlack = pieces.some((p) => p.type === 'king' && p.color === 'black');
    if (hasRed && hasBlack) return null;
    if (!hasRed && !hasBlack) return 'either general';
    return hasRed ? 'the Black general' : 'the Red general';
  }

  /** Compose a localized, human-friendly explanation of the recommended move. */
  private buildExplanation(
    board: NormalizedBoard,
    bestMove: AnalysisBestMove | null,
    language: NotationLanguage,
  ): string {
    const side = this.sideLabel(board.sideToMove, language);

    if (!bestMove) {
      switch (language) {
        case 'vi':
          return `Không thể tính nước đi cho ${side}.`;
        case 'zh':
          return `无法为${side}计算最佳着法。`;
        default:
          return `Could not compute a move for ${side}.`;
      }
    }

    const { human, notation, score, depth } = bestMove;
    switch (language) {
      case 'vi':
        return `${side} đi — nước tốt nhất: ${human} (${notation}). Đánh giá ${score}, độ sâu ${depth}.`;
      case 'zh':
        return `${side}走棋 — 最佳着法：${human}（${notation}）。评估 ${score}，深度 ${depth}。`;
      default:
        return `${side} to move — best: ${human} (${notation}). Eval ${score}, depth ${depth}.`;
    }
  }

  private sideLabel(side: SideToMove, language: NotationLanguage): string {
    const labels: Record<NotationLanguage, Record<SideToMove, string>> = {
      en: { red: 'Red', black: 'Black', unknown: 'Red (assumed)' },
      vi: { red: 'Đỏ', black: 'Đen', unknown: 'Đỏ (giả định)' },
      zh: { red: '紅方', black: '黑方', unknown: '紅方（假定）' },
    };
    return labels[language][side];
  }
}
