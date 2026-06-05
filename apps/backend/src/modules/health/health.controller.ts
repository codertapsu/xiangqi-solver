import { Controller, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { SkipEnvelope } from '../../common/decorators/skip-envelope.decorator';

export interface HealthResponse {
  status: 'ok';
  timestamp: string;
  uptimeSeconds: number;
  version: string;
}

/**
 * Liveness endpoint. Intentionally NOT wrapped in the success envelope
 * (via @SkipEnvelope) so external monitors see a flat, stable payload.
 */
@ApiTags('health')
@Controller('health')
export class HealthController {
  private readonly version: string = process.env.npm_package_version ?? '0.1.0';

  @Get()
  @SkipEnvelope()
  check(): HealthResponse {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptimeSeconds: Math.round(process.uptime()),
      version: this.version,
    };
  }
}
