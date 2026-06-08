import { Controller, Get, Logger, NotFoundException, Res } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { existsSync } from 'fs';
import { resolve } from 'path';
import type { Response } from 'express';
import { AppConfig } from '../../config/configuration';
import { SkipEnvelope } from '../../common/decorators/skip-envelope.decorator';

/**
 * Serves the Pikafish NNUE master-net that the ON-DEVICE app downloads, so the
 * app fetches it from OUR backend (the same host it already talks to) instead of
 * GitHub releases — which were returning 504s. The file is copied to
 * `ONDEVICE_NET_PATH` on the host during each release and MUST be the master-net
 * (`ONDEVICE_NET_BYTES` bytes); the app verifies the downloaded size.
 *
 * `@SkipEnvelope()` returns the raw bytes (no `{ success, data }` wrapper).
 * `@SkipThrottle()` keeps this large, cacheable, once-per-install download off
 * the per-IP analysis throttle. `res.sendFile` streams the file and gives
 * Content-Length + HTTP range support (resumable) for free.
 */
@ApiTags('engine')
@Controller('engine')
export class EngineNetController {
  private readonly logger = new Logger(EngineNetController.name);

  constructor(private readonly config: ConfigService) {}

  @Get('net')
  @SkipEnvelope()
  @SkipThrottle()
  getNet(@Res() res: Response): void {
    const path = this.netPath();
    if (!path) {
      throw new NotFoundException({
        message: 'On-device engine net is not available on this server.',
        code: 'NET_UNAVAILABLE',
      });
    }
    res.type('application/octet-stream');
    res.set('Cache-Control', 'public, max-age=31536000, immutable');
    res.sendFile(path, (err) => {
      if (err) this.logger.warn(`Failed to send engine net: ${(err as Error).message}`);
    });
  }

  /** The configured net file as an ABSOLUTE path (sendFile requires it), or null
   *  when unset/missing — so the route 404s instead of throwing mid-stream. */
  private netPath(): string | null {
    const configured = this.config.get<AppConfig['engine']>('app.engine')?.onDeviceNetPath;
    if (!configured) return null;
    const abs = resolve(configured);
    return existsSync(abs) ? abs : null;
  }
}
