import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ThrottlerException } from '@nestjs/throttler';
import { AppConfig } from '../../config/configuration';

interface RequestLike {
  headers: Record<string, string | string[] | undefined>;
  ip?: string;
}

/** Same bounds the analysis controller applies, so guard and router agree. */
const MIN_DEVICE_ID_LENGTH = 8;
const MAX_DEVICE_ID_LENGTH = 256;

/** One rolling-window bucket to check and, if the request is allowed, record. */
interface Bucket {
  key: string;
  limit: number;
  /** Used in the 429 message so the caller knows WHICH cap it hit. */
  scope: 'device' | 'network';
}

/**
 * Per-device AND per-source-IP rolling-window cap for the (paid) analysis
 * endpoints.
 *
 * Hints are a device-local counter on the client, so the server can't meter per
 * account. This is the cheap server-side abuse cap layered on top of the global
 * per-IP ThrottlerGuard: it bounds how many analyses a single device can run
 * within a rolling window. In-memory and per-instance — a soft cap that resets
 * on restart and is not shared across replicas, which is fine for "stop one
 * device draining the vision budget" without reintroducing per-user state.
 *
 * `x-device-id` is CLIENT-CONTROLLED and unauthenticated, so it is a hint, not
 * an identity: a caller that sends a fresh random id per request would get a
 * fresh empty bucket every time and never reach the cap. That is why the IP
 * bucket is counted on EVERY request, not only when the header is absent — a
 * rotating or missing id degrades to the network cap instead of escaping
 * metering. Both buckets must be under their limit for the request to pass.
 *
 * The network cap is deliberately looser than the device cap (several phones
 * legitimately share one NAT), and `req.ip` is the socket peer: behind a
 * reverse proxy the whole fleet would share one bucket unless Express `trust
 * proxy` is enabled there.
 */
@Injectable()
export class DeviceRateLimitGuard implements CanActivate {
  private readonly hits = new Map<string, number[]>();

  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const rl = this.config.get<AppConfig['rateLimit']>('app.rateLimit');
    const windowMs = (rl?.deviceWindowSeconds ?? 86_400) * 1000;
    const deviceLimit = rl?.deviceLimit ?? 100;
    // Same 5x relationship configuration.ts resolves, for the no-config path.
    const ipLimit = rl?.ipLimit ?? deviceLimit * 5;

    const req = context.switchToHttp().getRequest<RequestLike>();
    const deviceId = this.normalizeDeviceId(req.headers['x-device-id']);
    const ip = (req.ip ?? 'unknown').toString();

    // Prefixed so a device id can never collide with (or masquerade as) an IP.
    const buckets: Bucket[] = [{ key: `ip:${ip}`, limit: ipLimit, scope: 'network' }];
    if (deviceId) buckets.push({ key: `device:${deviceId}`, limit: deviceLimit, scope: 'device' });

    const now = Date.now();
    // Prune first, decide second, record last: a rejected request must not
    // consume budget in the other bucket.
    const pending = buckets.map((bucket) => ({
      bucket,
      recent: (this.hits.get(bucket.key) ?? []).filter((t) => now - t < windowMs),
    }));

    const exceeded = pending.find((p) => p.recent.length >= p.bucket.limit);
    if (exceeded) {
      throw new ThrottlerException(
        exceeded.bucket.scope === 'device'
          ? 'Daily analysis limit reached for this device.'
          : 'Daily analysis limit reached for this network.',
      );
    }

    for (const { bucket, recent } of pending) {
      recent.push(now);
      this.hits.set(bucket.key, recent);
    }

    // Opportunistic cleanup so the map can't grow without bound.
    if (this.hits.size > 10_000) {
      for (const [k, v] of this.hits) {
        if (v.every((t) => now - t >= windowMs)) this.hits.delete(k);
      }
    }
    return true;
  }

  /**
   * The header as a bucket key, or undefined when it is not a plausible device
   * id. Same 8..256 bounds the controller uses before routing on it — an id the
   * router would discard must not silently become a metering identity here.
   */
  private normalizeDeviceId(header: string | string[] | undefined): string | undefined {
    const raw = Array.isArray(header) ? header[0] : header;
    const id = (raw ?? '').trim();
    return id.length >= MIN_DEVICE_ID_LENGTH && id.length <= MAX_DEVICE_ID_LENGTH ? id : undefined;
  }
}
