import { CallHandler, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { firstValueFrom, of } from 'rxjs';
import { ResponseInterceptor } from './response.interceptor';
import { SKIP_ENVELOPE_KEY } from '../decorators/skip-envelope.decorator';

/**
 * Exercises the global success envelope contract:
 *   { success: true, data: <payload> }
 * and the @SkipEnvelope() bypass used by GET /api/health.
 */
describe('ResponseInterceptor', () => {
  let reflector: Reflector;
  let interceptor: ResponseInterceptor<unknown>;

  // Stable references so metadata-lookup assertions can compare them.
  const handlerRef = (): undefined => undefined;
  class ControllerRef {}
  const context = {
    getHandler: () => handlerRef,
    getClass: () => ControllerRef,
  } as unknown as ExecutionContext;

  const handlerReturning = (value: unknown): CallHandler => ({
    handle: () => of(value),
  });

  beforeEach(() => {
    reflector = new Reflector();
    interceptor = new ResponseInterceptor(reflector);
  });

  it('wraps a payload in the success envelope by default', async () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue(false);

    const result = await firstValueFrom(
      interceptor.intercept(context, handlerReturning({ id: 7 })),
    );

    expect(result).toEqual({ success: true, data: { id: 7 } });
  });

  it('wraps falsy payloads (null) without dropping them', async () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue(false);

    const result = await firstValueFrom(interceptor.intercept(context, handlerReturning(null)));

    expect(result).toEqual({ success: true, data: null });
  });

  it('returns the payload verbatim when @SkipEnvelope() metadata is present', async () => {
    jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue(true);

    const health = { status: 'ok', timestamp: 'x', uptimeSeconds: 1, version: '0.1.0' };
    const result = await firstValueFrom(interceptor.intercept(context, handlerReturning(health)));

    expect(result).toEqual(health);
    expect(result).not.toHaveProperty('success');
  });

  it('reads the skip flag from both handler and class metadata', async () => {
    const spy = jest.spyOn(reflector, 'getAllAndOverride').mockReturnValue(false);

    await firstValueFrom(interceptor.intercept(context, handlerReturning('x')));

    expect(spy).toHaveBeenCalledWith(SKIP_ENVELOPE_KEY, [context.getHandler(), context.getClass()]);
  });
});
