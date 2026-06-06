import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { AppConfig } from '../../config/configuration';

/**
 * Remote config / feature flags for the app. The app fetches this on launch and
 * caches the last good value, so behavior (which ad formats show, the free-hint
 * count, the own-key hint divisor, on-device availability + net URL) is tunable
 * from the SERVER (env) without shipping a new app version.
 *
 * Returned under the standard `{ success, data }` envelope; the client reads
 * `data` and falls back to its own safe defaults when offline.
 *
 * `@SkipThrottle()`: this is a cheap, public, read-only endpoint hit once per
 * launch. It must NOT share the per-IP analysis throttle budget — if it were
 * throttled (e.g. many devices behind one NAT), a 429 would make the client
 * silently keep stale flags, defeating the whole "tunable from the server" point.
 */
@ApiTags('config')
@SkipThrottle()
@Controller('config')
export class RemoteConfigController {
  constructor(private readonly config: ConfigService) {}

  @Get()
  getConfig(): AppConfig['features'] {
    // Always present (validated + defaulted at boot by configuration()).
    return this.config.get<AppConfig['features']>('app.features')!;
  }
}
