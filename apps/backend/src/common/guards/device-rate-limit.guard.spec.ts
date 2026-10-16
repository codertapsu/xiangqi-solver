import { ExecutionContext } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ThrottlerException } from '@nestjs/throttler';
import { DeviceRateLimitGuard } from './device-rate-limit.guard';

/** ConfigService stub exposing the rate-limit block under `app.rateLimit`. */
function config(rateLimit: Record<string, unknown>): ConfigService {
  return {
    get: (key: string) => (key === 'app.rateLimit' ? rateLimit : undefined),
  } as unknown as ConfigService;
}

/** A request with the given device header + source IP, as the guard sees it. */
function ctx(deviceId: string | string[] | undefined, ip = '198.51.100.7'): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => ({ headers: { 'x-device-id': deviceId }, ip }),
    }),
  } as unknown as ExecutionContext;
}

/** Call the guard `times` times, returning how many calls were allowed. */
function run(guard: DeviceRateLimitGuard, context: ExecutionContext, times: number): number {
  let allowed = 0;
  for (let i = 0; i < times; i++) {
    try {
      guard.canActivate(context);
      allowed++;
    } catch (err) {
      if (!(err instanceof ThrottlerException)) throw err;
    }
  }
  return allowed;
}

describe('DeviceRateLimitGuard', () => {
  const limits = { deviceWindowSeconds: 86_400, deviceLimit: 3, ipLimit: 5 };

  it('caps a single well-behaved device at the device limit', () => {
    const guard = new DeviceRateLimitGuard(config(limits));
    expect(run(guard, ctx('device-aaaa-0001'), 6)).toBe(3);
  });

  // Regression: the header is client-controlled and unauthenticated. Keying the
  // bucket ONLY on it meant a fresh random value per request got a fresh empty
  // bucket, so the cap never fired and one IP could drain the vision budget.
  it('does not let a rotating x-device-id escape metering — it degrades to the IP cap', () => {
    const guard = new DeviceRateLimitGuard(config(limits));
    let allowed = 0;
    for (let i = 0; i < 50; i++) {
      try {
        guard.canActivate(ctx(`rotating-device-${i}`));
        allowed++;
      } catch (err) {
        if (!(err instanceof ThrottlerException)) throw err;
      }
    }
    expect(allowed).toBe(limits.ipLimit);
  });

  it('counts the IP bucket even when the request carries a valid device ID', () => {
    const guard = new DeviceRateLimitGuard(config(limits));
    // Two devices, same IP: 3 + 2 pass, then the shared network cap stops the rest.
    expect(run(guard, ctx('device-aaaa-0001'), 3)).toBe(3);
    expect(run(guard, ctx('device-bbbb-0002'), 3)).toBe(2);
  });

  it('meters each source IP separately', () => {
    const guard = new DeviceRateLimitGuard(config(limits));
    expect(run(guard, ctx(undefined, '203.0.113.1'), 9)).toBe(5);
    expect(run(guard, ctx(undefined, '203.0.113.2'), 9)).toBe(5);
  });

  it.each([
    ['too short', 'short7'],
    ['too long', 'x'.repeat(257)],
    ['blank', '   '],
  ])('ignores a %s device ID as a bucket key, falling back to the IP cap', (_case, header) => {
    const guard = new DeviceRateLimitGuard(config(limits));
    // The controller discards IDs outside 8..256 before routing on them, so the
    // guard must not quietly accept one as a metering identity either.
    expect(run(guard, ctx(header), 9)).toBe(limits.ipLimit);
  });

  it('names the cap that was hit', () => {
    const guard = new DeviceRateLimitGuard(config({ ...limits, ipLimit: 100 }));
    run(guard, ctx('device-aaaa-0001'), 3);
    expect(() => guard.canActivate(ctx('device-aaaa-0001'))).toThrow(/for this device/);

    const ipGuard = new DeviceRateLimitGuard(config({ ...limits, ipLimit: 2 }));
    run(ipGuard, ctx(undefined), 2);
    expect(() => ipGuard.canActivate(ctx(undefined))).toThrow(/for this network/);
  });

  it('does not charge the device bucket for a request the network cap rejected', () => {
    // deviceLimit 4 > ipLimit 2 on purpose: 5 tries on one IP must spend exactly
    // 2 of the device's budget, not 5. Moving to a fresh IP then reveals what was
    // actually charged — 2 left if the guard records only allowed requests, 0 if
    // it charged the rejected ones too.
    const guard = new DeviceRateLimitGuard(config({ ...limits, deviceLimit: 4, ipLimit: 2 }));
    expect(run(guard, ctx('device-aaaa-0001'), 5)).toBe(2);

    expect(run(guard, ctx('device-aaaa-0001', '203.0.113.9'), 2)).toBe(2);
    // ...and the device budget really is exhausted now (4 of 4 spent), so this
    // is not just the second IP's own cap being observed.
    expect(() => guard.canActivate(ctx('device-aaaa-0001', '203.0.113.10'))).toThrow(
      /for this device/,
    );
  });

  it('derives the network cap from the device cap when RATE_LIMIT_IP_LIMIT is unset', () => {
    // A fixed default would sit BELOW a deployment that raised the device cap and
    // silently become every user's real limit (production runs deviceLimit 1000).
    const guard = new DeviceRateLimitGuard(config({ deviceWindowSeconds: 86_400, deviceLimit: 3 }));
    let allowed = 0;
    for (let i = 0; i < 40; i++) {
      try {
        guard.canActivate(ctx(`rotating-device-${i}`));
        allowed++;
      } catch (err) {
        if (!(err instanceof ThrottlerException)) throw err;
      }
    }
    expect(allowed).toBe(15); // 5x the device cap
  });

  it('takes the first value of a repeated header', () => {
    const guard = new DeviceRateLimitGuard(config(limits));
    run(guard, ctx(['device-aaaa-0001', 'device-bbbb-0002']), 3);
    // The first value was metered, so that device is now exhausted.
    expect(() => guard.canActivate(ctx('device-aaaa-0001'))).toThrow(ThrottlerException);
  });

  it('forgets hits older than the rolling window', () => {
    jest.useFakeTimers().setSystemTime(new Date('2026-01-01T00:00:00Z'));
    try {
      const guard = new DeviceRateLimitGuard(config({ ...limits, deviceWindowSeconds: 60 }));
      expect(run(guard, ctx('device-aaaa-0001'), 5)).toBe(3);

      jest.setSystemTime(new Date('2026-01-01T00:01:01Z'));
      expect(run(guard, ctx('device-aaaa-0001'), 5)).toBe(3);
    } finally {
      jest.useRealTimers();
    }
  });

  it('falls back to safe defaults when the rate-limit config is missing', () => {
    const guard = new DeviceRateLimitGuard({ get: () => undefined } as unknown as ConfigService);
    expect(guard.canActivate(ctx('device-aaaa-0001'))).toBe(true);
  });
});
