import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import sharp from 'sharp';
import { AppConfig } from '../../config/configuration';

/** Result of normalizing an upload for the vision call. */
export interface PreprocessedImage {
  buffer: Buffer;
  mimeType: string;
}

/**
 * Downscales/recompresses screenshots BEFORE they are base64'd into the vision
 * request.
 *
 * Vision providers tile images after scaling them down themselves (OpenAI
 * "high" detail: fit within 2048px, then shortest side to 768px), so pixels
 * beyond that budget are pure waste: a full-resolution lossless phone PNG
 * (1–8 MB) costs seconds of VPS->provider upload and extra tiles without the
 * model ever seeing the difference. We mirror the provider's own budget
 * (shortest side <= TARGET_SHORT_SIDE, longest <= TARGET_LONG_SIDE) and
 * re-encode as JPEG — typically 1–5 MB -> 100–300 KB with pixel-identical
 * model input.
 *
 * Fail-open: any decode/transform error returns the original buffer untouched
 * (the provider then surfaces its own, clearer error for a corrupt image).
 */
@Injectable()
export class ImagePreprocessService {
  private readonly logger = new Logger(ImagePreprocessService.name);

  constructor(private readonly config: ConfigService) {}

  async normalizeForVision(buffer: Buffer, mimeType: string): Promise<PreprocessedImage> {
    const ai = this.config.get<AppConfig['ai']>('app.ai');
    if (ai?.visionPreprocess === false) return { buffer, mimeType };
    const shortSide = ai?.visionImageShortSide ?? 768;
    const longSide = ai?.visionImageLongSide ?? 2048;
    const jpegQuality = 90;
    // Below this size the bandwidth win is negligible; skip the CPU work
    // unless the image is also dimensionally oversized.
    const skipBytes = 300_000;

    try {
      const meta = await sharp(buffer).metadata();
      // Dimensions as the viewer sees them: EXIF orientation 5-8 swaps axes.
      const exifSwapsAxes = (meta.orientation ?? 1) >= 5;
      const width = (exifSwapsAxes ? meta.height : meta.width) ?? 0;
      const height = (exifSwapsAxes ? meta.width : meta.height) ?? 0;
      if (!width || !height) return { buffer, mimeType };

      const short = Math.min(width, height);
      const long = Math.max(width, height);
      const scale = Math.min(shortSide / short, longSide / long, 1);
      const withinBudget = scale >= 1 && (meta.orientation ?? 1) === 1;
      // Already within the pixel budget: skip when small, and ALWAYS skip
      // JPEGs (clients now pre-downscale to this budget at quality 92 — a
      // second lossy re-encode would only degrade the glyphs).
      if (withinBudget && (mimeType === 'image/jpeg' || buffer.byteLength <= skipBytes)) {
        return { buffer, mimeType };
      }

      const out = await sharp(buffer)
        // Bake EXIF orientation into the pixels FIRST: resize strips metadata,
        // and a camera photo would otherwise reach the model sideways.
        .rotate()
        .resize({
          width: Math.max(1, Math.round(width * scale)),
          height: Math.max(1, Math.round(height * scale)),
          fit: 'fill',
          withoutEnlargement: true,
        })
        // Board screenshots compress extremely well as JPEG; quality 90 keeps
        // the piece glyph edges crisp for OCR-style reading.
        .jpeg({ quality: jpegQuality })
        .toBuffer();

      // Never "optimize" into a bigger payload.
      if (out.byteLength >= buffer.byteLength) return { buffer, mimeType };
      return { buffer: out, mimeType: 'image/jpeg' };
    } catch (err) {
      this.logger.warn(`Image preprocess failed (sending original): ${(err as Error).message}`);
      return { buffer, mimeType };
    }
  }
}
