import {
  BadRequestException,
  Body,
  Controller,
  HttpException,
  Post,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import { ApiConsumes, ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { AppConfig } from '../../config/configuration';
import { SkipEnvelope } from '../../common/decorators/skip-envelope.decorator';
import { AnalysisService } from './analysis.service';
import { AnalysisResult, ExtractionResult } from './analysis.types';
import { AnalyzeBoardDto } from './dto/analyze-board.dto';
import { AnalyzeScreenshotDto } from './dto/analyze-screenshot.dto';
import { ExtractScreenshotDto } from './dto/extract-screenshot.dto';
import { detectImageType, DetectedImageType } from '../../common/utils/image-type.util';
import { DeviceRateLimitGuard } from '../../common/guards/device-rate-limit.guard';

const ACCEPTED_MIME_TYPES: readonly DetectedImageType[] = ['image/png', 'image/jpeg', 'image/webp'];

/**
 * Analysis endpoints. Both return an AnalysisResult under the standard
 * { success, data } envelope (applied globally by the ResponseInterceptor).
 *
 * These call the AI/engine (real cost), so on top of the global per-IP throttle
 * they are also capped per device by [DeviceRateLimitGuard] (the `x-device-id`
 * header) — the cheap abuse cap now that hints are a device-local counter.
 */
@ApiTags('analysis')
@Controller('analysis')
@UseGuards(DeviceRateLimitGuard)
export class AnalysisController {
  constructor(
    private readonly analysisService: AnalysisService,
    private readonly config: ConfigService,
  ) {}

  /**
   * POST /api/analysis/screenshot (multipart/form-data).
   * Upload an image; vision extracts the board, then the engine analyzes it.
   */
  @Post('screenshot')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('screenshot'))
  async analyzeScreenshot(
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: AnalyzeScreenshotDto,
  ): Promise<AnalysisResult> {
    const upload = this.validateUpload(file);

    return this.analysisService.analyzeScreenshot({
      imageBuffer: upload.buffer,
      // Use the type sniffed from the bytes, NOT the client-declared mime, so a
      // mislabeled-but-valid image is sent to the vision API correctly.
      mimeType: upload.mimeType,
      provider: dto.provider,
      sideToMove: dto.sideToMove,
      engineProvider: dto.engineProvider,
      engineDepth: dto.engineDepth,
      engineMoveTimeMs: dto.engineMoveTimeMs,
      engineThreads: dto.engineThreads,
      engineHashMb: dto.engineHashMb,
      engineMultiPv: dto.engineMultiPv,
      language: dto.language,
    });
  }

  /**
   * POST /api/analysis/screenshot/stream (multipart/form-data) -> NDJSON.
   *
   * Same work as /screenshot, but PROGRESSIVE: one JSON object per line as
   * each stage completes, so the client can render the recognized board while
   * the engine is still searching. Stages:
   *   {"stage":"received"}                          - upload accepted
   *   {"stage":"board","board":{...}}               - vision + repair done
   *   {"stage":"done","data":<AnalysisResult>}      - engine + notation done
   *   {"stage":"error","error":{code,message}}      - failure after streaming began
   * Errors BEFORE the first byte (missing/invalid file) use the standard
   * { success:false, error } envelope with a real HTTP status.
   */
  @Post('screenshot/stream')
  @SkipEnvelope()
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('screenshot'))
  async analyzeScreenshotStream(
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: AnalyzeScreenshotDto,
    @Res() res: Response,
  ): Promise<void> {
    // Validate BEFORE any byte is written: these errors still get the normal
    // envelope + HTTP status via the global exception filter.
    const upload = this.validateUpload(file);

    res.status(200);
    res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
    res.setHeader('Cache-Control', 'no-cache');
    // Disable proxy buffering (nginx/Caddy) so stages reach the client live.
    res.setHeader('X-Accel-Buffering', 'no');
    const write = (obj: unknown): void => {
      res.write(`${JSON.stringify(obj)}\n`);
    };
    write({ stage: 'received' });

    try {
      const result = await this.analysisService.analyzeScreenshot({
        imageBuffer: upload.buffer,
        mimeType: upload.mimeType,
        provider: dto.provider,
        sideToMove: dto.sideToMove,
        engineProvider: dto.engineProvider,
        engineDepth: dto.engineDepth,
        engineMoveTimeMs: dto.engineMoveTimeMs,
        engineThreads: dto.engineThreads,
        engineHashMb: dto.engineHashMb,
        engineMultiPv: dto.engineMultiPv,
        language: dto.language,
        onBoard: (board) => write({ stage: 'board', board }),
      });
      write({ stage: 'done', data: result });
    } catch (err) {
      // Headers are already sent: deliver the failure as the final NDJSON line
      // (mirrors the envelope's { code, message } shape).
      write({ stage: 'error', error: this.streamError(err) });
    } finally {
      res.end();
    }
  }

  /** Map an exception to the { code, message } shape used by the envelope. */
  private streamError(err: unknown): { code: string; message: string } {
    if (err instanceof HttpException) {
      const body = err.getResponse();
      if (body && typeof body === 'object') {
        const o = body as Record<string, unknown>;
        return {
          code: typeof o.code === 'string' ? o.code : `HTTP_${err.getStatus()}`,
          message: typeof o.message === 'string' ? o.message : err.message,
        };
      }
      return { code: `HTTP_${err.getStatus()}`, message: err.message };
    }
    return { code: 'INTERNAL_ERROR', message: 'Analysis failed unexpectedly.' };
  }

  /**
   * POST /api/analysis/extract (multipart/form-data).
   * Vision-only: recognize the board and return it WITHOUT running the engine.
   * Intended for clients that compute the move themselves (e.g. an on-device
   * engine), keeping the AI key server-side.
   */
  @Post('extract')
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(FileInterceptor('screenshot'))
  async extractScreenshot(
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() dto: ExtractScreenshotDto,
  ): Promise<ExtractionResult> {
    const upload = this.validateUpload(file);
    return this.analysisService.extractBoard({
      imageBuffer: upload.buffer,
      mimeType: upload.mimeType,
      provider: dto.provider,
      sideToMove: dto.sideToMove,
    });
  }

  /**
   * POST /api/analysis/board (application/json).
   * Provide pieces directly; vision is bypassed and the engine runs.
   */
  @Post('board')
  async analyzeBoard(@Body() dto: AnalyzeBoardDto): Promise<AnalysisResult> {
    return this.analysisService.analyzeBoard({
      sideToMove: dto.sideToMove,
      pieces: dto.pieces.map((p) => ({
        color: p.color,
        type: p.type,
        file: p.file,
        rank: p.rank,
        ...(typeof p.confidence === 'number' ? { confidence: p.confidence } : {}),
      })),
      engineProvider: dto.engineProvider,
      engineDepth: dto.engineDepth,
      engineMoveTimeMs: dto.engineMoveTimeMs,
      engineThreads: dto.engineThreads,
      engineHashMb: dto.engineHashMb,
      engineMultiPv: dto.engineMultiPv,
      language: dto.language,
    });
  }

  /**
   * Reject missing files, oversize uploads, and anything that is not a real
   * PNG/JPEG/WebP image (validated by magic bytes, not the declared mime).
   * Returns the upload buffer plus the authoritative, sniffed mime type.
   */
  private validateUpload(file: Express.Multer.File | undefined): {
    buffer: Buffer;
    mimeType: DetectedImageType;
  } {
    if (!file) {
      throw new BadRequestException({
        message: 'A "screenshot" image file is required.',
        code: 'MISSING_FILE',
      });
    }

    const maxBytes = this.config.get<AppConfig['upload']>('app.upload')?.maxBytes ?? 8_388_608;
    if (file.size > maxBytes) {
      throw new BadRequestException({
        message: `File too large (${file.size} bytes). Maximum is ${maxBytes} bytes.`,
        code: 'FILE_TOO_LARGE',
      });
    }

    const detected = detectImageType(file.buffer);
    if (!detected || !ACCEPTED_MIME_TYPES.includes(detected)) {
      throw new BadRequestException({
        message:
          `The uploaded file is not a valid ${ACCEPTED_MIME_TYPES.join(', ')} image ` +
          `(declared "${file.mimetype}", detected "${detected ?? 'unknown'}"). ` +
          'It may be corrupted, truncated, or a different format.',
        code: 'UNSUPPORTED_MEDIA_TYPE',
      });
    }

    return { buffer: file.buffer, mimeType: detected };
  }
}
