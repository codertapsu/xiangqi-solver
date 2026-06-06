import {
  BadRequestException,
  Body,
  Controller,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import { ApiConsumes, ApiTags } from '@nestjs/swagger';
import { AppConfig } from '../../config/configuration';
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
