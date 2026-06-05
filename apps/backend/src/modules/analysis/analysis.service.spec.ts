import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AnalysisService } from './analysis.service';
import { AiService } from '../ai/ai.service';
import { MockVisionProvider } from '../ai/providers/mock-vision.provider';
import { GeminiVisionProvider } from '../ai/providers/gemini.provider';
import { OpenAiVisionProvider } from '../ai/providers/openai.provider';
import { EngineService } from '../engine/engine.service';
import { MockEngineService } from '../engine/mock-engine.service';
import { PikafishEngineService } from '../engine/pikafish-engine.service';
import { BoardValidatorService } from '../board/board-validator.service';
import { BoardNormalizerService } from '../board/board-normalizer.service';
import { FenService } from '../board/fen.service';
import { MoveNotationService } from '../board/move-notation.service';
import { buildStartPosition } from '../board/start-position';
import { START_POSITION_FEN } from '../board/xiangqi.types';

/** Build a ConfigService stub with mock providers + default engine settings. */
function buildConfig(): ConfigService {
  return {
    get: (key: string) => {
      switch (key) {
        case 'app.ai':
          return { provider: 'mock' };
        case 'app.engine':
          return {
            provider: 'mock',
            pikafishBinaryPath: '',
            defaultDepth: 12,
            defaultMoveTimeMs: 1000,
          };
        case 'app.upload':
          return { maxBytes: 8_388_608 };
        default:
          return undefined;
      }
    },
  } as unknown as ConfigService;
}

describe('AnalysisService', () => {
  let service: AnalysisService;

  beforeEach(() => {
    const config = buildConfig();
    const aiService = new AiService(
      config,
      new MockVisionProvider(),
      new GeminiVisionProvider(config),
      new OpenAiVisionProvider(config),
    );
    const engineService = new EngineService(
      config,
      new MockEngineService(),
      new PikafishEngineService(config),
    );
    service = new AnalysisService(
      config,
      aiService,
      engineService,
      new BoardValidatorService(),
      new BoardNormalizerService(),
      new FenService(),
      new MoveNotationService(),
    );
  });

  describe('analyzeBoard (no-vision path)', () => {
    it('runs the full mock pipeline and returns a complete result', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'red',
        pieces: buildStartPosition(),
      });

      expect(result.analysisId).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
      expect(result.board.fen).toBe(START_POSITION_FEN);
      expect(result.board.sideToMove).toBe('red');
      expect(result.engine).toEqual({ provider: 'mock', ok: true });
      expect(result.vision).toEqual({ provider: 'none', ok: true });
    });

    it('returns the deterministic mock best move for Red', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'red',
        pieces: buildStartPosition(),
      });
      expect(result.bestMove).not.toBeNull();
      expect(result.bestMove?.uci).toBe('b2e2');
      // Traditional notation: the left cannon (Red file 8) traverses to file 5.
      expect(result.bestMove?.human).toBe('Cannon 8 traverses to 5');
      expect(result.bestMove?.notation).toBe('C8=5');
      expect(result.bestMove?.score).toBe('+0.30');
      expect(result.bestMove?.depth).toBe(12);
      expect(result.explanation).toContain('Cannon 8 traverses to 5');
    });

    it('localizes the notation when a language is given (vi)', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'red',
        pieces: buildStartPosition(),
        language: 'vi',
      });
      expect(result.bestMove?.human).toBe('Pháo 8 bình 5');
      expect(result.bestMove?.notation).toBe('C8=5');
      expect(result.explanation).toContain('Pháo 8 bình 5');
    });

    it('returns the deterministic mock best move for Black', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'black',
        pieces: buildStartPosition(),
      });
      expect(result.bestMove?.uci).toBe('b7e7');
    });

    it('honors an explicit engine depth override', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'red',
        pieces: buildStartPosition(),
        engineDepth: 7,
      });
      expect(result.bestMove?.depth).toBe(7);
    });

    it('warns when side to move is unknown and defaults FEN to Red', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'unknown',
        pieces: buildStartPosition(),
      });
      expect(result.board.fen.split(' ')[1]).toBe('w');
      expect(result.warnings.some((w) => /side to move is unknown/i.test(w))).toBe(true);
    });

    it('throws BadRequest on an invalid board', async () => {
      await expect(
        service.analyzeBoard({
          sideToMove: 'red',
          pieces: [{ color: 'red', type: 'king', file: 4, rank: 0 }], // missing black king
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('records engine failure (ok:false) when using an unconfigured pikafish engine', async () => {
      const result = await service.analyzeBoard({
        sideToMove: 'red',
        pieces: buildStartPosition(),
        engineProvider: 'pikafish',
      });
      expect(result.engine).toEqual({ provider: 'pikafish', ok: false });
      expect(result.bestMove).toBeNull();
      expect(result.warnings.some((w) => /engine "pikafish" failed/i.test(w))).toBe(true);
    });
  });

  describe('analyzeScreenshot (vision path)', () => {
    it('extracts the board via the mock vision provider then runs the engine', async () => {
      const result = await service.analyzeScreenshot({
        imageBuffer: Buffer.from('fake-png'),
        mimeType: 'image/png',
      });
      expect(result.vision).toEqual({ provider: 'mock', ok: true });
      expect(result.board.fen).toBe(START_POSITION_FEN);
      expect(result.bestMove?.uci).toBe('b2e2');
    });

    it('uses the side-to-move hint from the request', async () => {
      const result = await service.analyzeScreenshot({
        imageBuffer: Buffer.from('fake-png'),
        mimeType: 'image/png',
        sideToMove: 'black',
      });
      expect(result.board.sideToMove).toBe('black');
      expect(result.bestMove?.uci).toBe('b7e7');
    });

    it('propagates a clear error when a real provider lacks credentials', async () => {
      await expect(
        service.analyzeScreenshot({
          imageBuffer: Buffer.from('fake-png'),
          mimeType: 'image/png',
          provider: 'openai',
        }),
      ).rejects.toThrow(/OPENAI_API_KEY/i);
    });
  });

  describe('analyzeScreenshot leniency (imperfect AI extraction)', () => {
    function serviceWithExtraction(pieces: unknown[]): AnalysisService {
      const config = buildConfig();
      const aiStub = {
        defaultProvider: 'mock',
        extractBoardState: async () => ({
          boardDetected: true,
          sideToMove: 'red',
          confidence: 0.5,
          pieces,
          warnings: [],
        }),
      } as unknown as AiService;
      const engineService = new EngineService(
        config,
        new MockEngineService(),
        new PikafishEngineService(config),
      );
      return new AnalysisService(
        config,
        aiStub,
        engineService,
        new BoardValidatorService(),
        new BoardNormalizerService(),
        new FenService(),
        new MoveNotationService(),
      );
    }

    const run = (svc: AnalysisService) =>
      svc.analyzeScreenshot({ imageBuffer: Buffer.from('x'), mimeType: 'image/png' });

    it('repairs overlapping pieces instead of failing, and still returns a move', async () => {
      const result = await run(
        serviceWithExtraction([
          { color: 'red', type: 'king', file: 4, rank: 0 },
          { color: 'black', type: 'king', file: 4, rank: 9 },
          { color: 'red', type: 'rook', file: 0, rank: 0, confidence: 0.3 },
          { color: 'red', type: 'cannon', file: 0, rank: 0, confidence: 0.9 }, // overlap
        ]),
      );
      expect(result.bestMove).not.toBeNull();
      expect(result.warnings.some((w) => /overlapping/i.test(w))).toBe(true);
    });

    it('returns the board + warning (no 400, null move) when a general is missing', async () => {
      const result = await run(
        serviceWithExtraction([
          { color: 'red', type: 'king', file: 4, rank: 0 },
          { color: 'red', type: 'rook', file: 0, rank: 0 }, // no Black king
        ]),
      );
      expect(result.bestMove).toBeNull();
      expect(result.engine.ok).toBe(false);
      expect(result.warnings.some((w) => /general/i.test(w))).toBe(true);
      expect(result.board.pieces.length).toBeGreaterThan(0);
    });

    it('throws only when no board pieces are detected at all', async () => {
      await expect(run(serviceWithExtraction([]))).rejects.toBeInstanceOf(BadRequestException);
    });
  });
});
