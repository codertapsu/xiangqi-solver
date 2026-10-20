import { BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Response } from 'express';
import {
  AnalysisController,
  STREAM_HEARTBEAT_MS,
  SYNC_LOCAL_VISION_BUDGET_MS,
} from './analysis.controller';
import { AnalysisService } from './analysis.service';
import { AnalysisResult, ExtractionResult } from './analysis.types';
import { AnalyzeScreenshotDto } from './dto/analyze-screenshot.dto';
import { AnalyzeBoardDto, SideToMoveEnum } from './dto/analyze-board.dto';
import { ExtractScreenshotDto } from './dto/extract-screenshot.dto';

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

const sampleExtraction: ExtractionResult = {
  extractionId: '00000000-0000-4000-8000-000000000001',
  board: sampleResult.board,
  warnings: [],
  vision: { provider: 'mock', ok: true },
};

function buildController(): {
  controller: AnalysisController;
  service: jest.Mocked<
    Pick<AnalysisService, 'analyzeScreenshot' | 'analyzeBoard' | 'extractBoard'>
  >;
} {
  const service = {
    analyzeScreenshot: jest.fn().mockResolvedValue(sampleResult),
    analyzeBoard: jest.fn().mockResolvedValue(sampleResult),
    extractBoard: jest.fn().mockResolvedValue(sampleExtraction),
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
      const result = await controller.analyzeScreenshot(fakeFile(), dto, '  device-main  ');
      expect(service.analyzeScreenshot).toHaveBeenCalledTimes(1);
      // Not streamed, so the app's 60 s limit applies: the local bridge gets a
      // capped budget and the cloud fallback still has time to answer.
      expect(service.analyzeScreenshot).toHaveBeenCalledWith(
        expect.objectContaining({
          deviceId: 'device-main',
          localBudgetMs: SYNC_LOCAL_VISION_BUDGET_MS,
        }),
      );
      expect(result).toBe(sampleResult);
    });
  });

  it('forwards the device ID for streaming screenshot analysis', async () => {
    const { controller, service } = buildController();
    const response = {
      status: jest.fn().mockReturnThis(),
      setHeader: jest.fn(),
      write: jest.fn(),
      end: jest.fn(),
    } as unknown as Response;

    await controller.analyzeScreenshotStream(
      fakeFile(),
      new AnalyzeScreenshotDto(),
      response,
      '  device-stream  ',
    );

    expect(service.analyzeScreenshot).toHaveBeenCalledWith(
      expect.objectContaining({ deviceId: 'device-stream' }),
    );
    // Keep-alives hold the stream open, so the bridge keeps its full timeout.
    expect(service.analyzeScreenshot.mock.calls[0][0].localBudgetMs).toBeUndefined();
  });

  describe('analyzeScreenshotStream keep-alive', () => {
    afterEach(() => jest.useRealTimers());

    function streamResponse(): { response: Response; lines: () => unknown[] } {
      const write = jest.fn();
      const response = {
        status: jest.fn().mockReturnThis(),
        setHeader: jest.fn(),
        write,
        end: jest.fn(),
      } as unknown as Response;
      const lines = (): unknown[] =>
        write.mock.calls.map(([chunk]) => JSON.parse(String(chunk).trim()) as unknown);
      return { response, lines };
    }

    it('sends waiting lines while a slow vision stage runs, then stops', async () => {
      jest.useFakeTimers();
      const { controller, service } = buildController();
      let finish: (value: AnalysisResult) => void = () => undefined;
      service.analyzeScreenshot.mockReturnValue(
        new Promise<AnalysisResult>((resolve) => (finish = resolve)),
      );
      const { response, lines } = streamResponse();

      const done = controller.analyzeScreenshotStream(
        fakeFile(),
        new AnalyzeScreenshotDto(),
        response,
      );
      await jest.advanceTimersByTimeAsync(STREAM_HEARTBEAT_MS * 3);
      expect(lines()).toEqual([
        { stage: 'received' },
        { stage: 'waiting' },
        { stage: 'waiting' },
        { stage: 'waiting' },
      ]);

      finish(sampleResult);
      await done;
      await jest.advanceTimersByTimeAsync(STREAM_HEARTBEAT_MS * 3);
      expect(lines().slice(4)).toEqual([{ stage: 'done', data: sampleResult }]);
      expect(response.end).toHaveBeenCalledTimes(1);
    });

    it('stops the keep-alive when the analysis fails', async () => {
      jest.useFakeTimers();
      const { controller, service } = buildController();
      service.analyzeScreenshot.mockRejectedValue(new Error('boom'));
      const { response, lines } = streamResponse();

      await controller.analyzeScreenshotStream(fakeFile(), new AnalyzeScreenshotDto(), response);
      await jest.advanceTimersByTimeAsync(STREAM_HEARTBEAT_MS * 2);

      expect(lines()).toEqual([
        { stage: 'received' },
        {
          stage: 'error',
          error: { code: 'INTERNAL_ERROR', message: 'Analysis failed unexpectedly.' },
        },
      ]);
    });

    it('does not write after the client has disconnected', async () => {
      jest.useFakeTimers();
      const { controller, service } = buildController();
      service.analyzeScreenshot.mockReturnValue(new Promise<AnalysisResult>(() => undefined));
      const { response, lines } = streamResponse();

      void controller.analyzeScreenshotStream(fakeFile(), new AnalyzeScreenshotDto(), response);
      await jest.advanceTimersByTimeAsync(0);
      (response as unknown as { destroyed: boolean }).destroyed = true;
      await jest.advanceTimersByTimeAsync(STREAM_HEARTBEAT_MS * 2);

      expect(lines()).toEqual([{ stage: 'received' }]);
    });
  });

  it('forwards the device ID for vision-only extraction', async () => {
    const { controller, service } = buildController();

    const result = await controller.extractScreenshot(
      fakeFile(),
      new ExtractScreenshotDto(),
      '  device-extract  ',
    );

    expect(service.extractBoard).toHaveBeenCalledWith(
      expect.objectContaining({
        deviceId: 'device-extract',
        localBudgetMs: SYNC_LOCAL_VISION_BUDGET_MS,
      }),
    );
    expect(result).toBe(sampleExtraction);
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
