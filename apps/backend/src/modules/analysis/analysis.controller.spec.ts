import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AnalysisController } from './analysis.controller';
import { AnalysisService } from './analysis.service';
import { AnalysisResult } from './analysis.types';
import { AnalyzeScreenshotDto } from './dto/analyze-screenshot.dto';
import { AnalyzeBoardDto, SideToMoveEnum } from './dto/analyze-board.dto';

/** A real, minimal 1x1 PNG (valid signature) so magic-byte validation passes. */
const VALID_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC',
  'base64',
);

/** A buffer whose bytes are JPEG, regardless of any declared mime. */
const JPEG_BYTES = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(12)]);

const sampleResult: AnalysisResult = {
  analysisId: '00000000-0000-4000-8000-000000000000',
  board: { sideToMove: 'red', fen: 'fen', pieces: [], confidence: 1 },
  bestMove: null,
  candidates: [],
  explanation: 'x',
  warnings: [],
  engine: { provider: 'mock', ok: true },
  vision: { provider: 'mock', ok: true },
};

function buildController(): {
  controller: AnalysisController;
  service: jest.Mocked<Pick<AnalysisService, 'analyzeScreenshot' | 'analyzeBoard'>>;
} {
  const service = {
    analyzeScreenshot: jest.fn().mockResolvedValue(sampleResult),
    analyzeBoard: jest.fn().mockResolvedValue(sampleResult),
  };
  const config = {
    get: () => ({ maxBytes: 8_388_608 }),
  } as unknown as ConfigService;
  const controller = new AnalysisController(service as unknown as AnalysisService, config);
  return { controller, service };
}

function fakeFile(overrides: Partial<Express.Multer.File> = {}): Express.Multer.File {
  return {
    fieldname: 'screenshot',
    originalname: 'board.png',
    encoding: '7bit',
    mimetype: 'image/png',
    size: 1024,
    buffer: VALID_PNG,
    stream: undefined as never,
    destination: '',
    filename: '',
    path: '',
    ...overrides,
  };
}

describe('AnalysisController', () => {
  describe('analyzeScreenshot', () => {
    it('rejects a missing file with 400', async () => {
      const { controller } = buildController();
      await expect(
        controller.analyzeScreenshot(undefined, new AnalyzeScreenshotDto()),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a non-image file by magic bytes, even if the mime claims image/png', async () => {
      const { controller } = buildController();
      await expect(
        controller.analyzeScreenshot(
          fakeFile({
            mimetype: 'image/png',
            buffer: Buffer.from('this is plain text, not an image'),
          }),
          new AnalyzeScreenshotDto(),
        ),
      ).rejects.toThrow(/not a valid/i);
    });

    it('forwards the sniffed mime type, not the declared one', async () => {
      const { controller, service } = buildController();
      // Bytes are JPEG but the client mislabeled it as PNG.
      await controller.analyzeScreenshot(
        fakeFile({ mimetype: 'image/png', buffer: JPEG_BYTES }),
        new AnalyzeScreenshotDto(),
      );
      expect(service.analyzeScreenshot).toHaveBeenCalledTimes(1);
      expect(service.analyzeScreenshot.mock.calls[0][0]).toMatchObject({
        mimeType: 'image/jpeg',
      });
    });

    it('rejects an oversize file with 400', async () => {
      const { controller } = buildController();
      await expect(
        controller.analyzeScreenshot(fakeFile({ size: 9_000_000 }), new AnalyzeScreenshotDto()),
      ).rejects.toThrow(/too large/i);
    });

    it('delegates a valid upload to the service', async () => {
      const { controller, service } = buildController();
      const dto = new AnalyzeScreenshotDto();
      const result = await controller.analyzeScreenshot(fakeFile(), dto);
      expect(service.analyzeScreenshot).toHaveBeenCalledTimes(1);
      expect(result).toBe(sampleResult);
    });
  });

  describe('analyzeBoard', () => {
    it('delegates to the service with mapped pieces', async () => {
      const { controller, service } = buildController();
      const dto = new AnalyzeBoardDto();
      dto.sideToMove = SideToMoveEnum.red;
      dto.pieces = [
        { color: 'red', type: 'king', file: 4, rank: 0 } as never,
        { color: 'black', type: 'king', file: 4, rank: 9 } as never,
      ];
      const result = await controller.analyzeBoard(dto);
      expect(service.analyzeBoard).toHaveBeenCalledTimes(1);
      expect(result).toBe(sampleResult);
    });
  });
});
