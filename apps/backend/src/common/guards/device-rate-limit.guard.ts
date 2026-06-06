import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ThrottlerException } from '@nestjs/throttler';
import { AppConfig } from '../../config/configuration';

interface RequestLike {
  headers: Record<string, string | string[] | undefined>;
  ip?: string;
}

/**
 * Per-device rolling-window cap for the (paid) analysis endpoints.
 *
 * Hints are a device-local counter on the client, so the server can't meter per
 * account. This is the cheap server-side abuse cap layered on top of the global
 * per-IP ThrottlerGuard: it bounds how many analyses a single device (the
 * `x-device-id` header, falling back to the client IP) can run within a rolling
 * window. In-memory and per-instance — a soft cap that resets on restart and is
 * not shared across replicas, which is fine for "stop one device draining the
 * OpenAI budget" without reintroducing any per-user server state.
 */
@Injectable()
export class DeviceRateLimitGuard implements CanActivate {
  private readonly hits = new Map<string, number[]>();

  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const rl = this.config.get<AppConfig['rateLimit']>('app.rateLimit');
    const windowMs = (rl?.deviceWindowSeconds ?? 86_400) * 1000;
    const limit = rl?.deviceLimit ?? 100;

    const req = context.switchToHttp().getRequest<RequestLike>();
    const header = req.headers['x-device-id'];
    const deviceId = Array.isArray(header) ? header[0] : header;
    const key = (deviceId || req.ip || 'unknown').toString();
    const now = Date.now();

    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < windowMs);
    if (recent.length >= limit) {
      throw new ThrottlerException('Daily analysis limit reached for this device.');
    }
    recent.push(now);
    this.hits.set(key, recent);

    // Opportunistic cleanup so the map can't grow without bound.
    if (this.hits.size > 10_000) {
      for (const [k, v] of this.hits) {
        if (v.every((t) => now - t >= windowMs)) this.hits.delete(k);
      }
    }
    return true;
  }
}
