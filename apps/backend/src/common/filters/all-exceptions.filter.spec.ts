import {
  ArgumentsHost,
  BadRequestException,
  HttpException,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import { AllExceptionsFilter } from './all-exceptions.filter';

/**
 * Exercises the global error envelope contract:
 *   { success: false, error: { code, message, details? } }
 * with the correct HTTP status, a stable/machine-readable code, and no
 * leaking of internal details for unknown (500) errors.
 */
describe('AllExceptionsFilter', () => {
  let filter: AllExceptionsFilter;
  let statusMock: jest.Mock;
  let jsonMock: jest.Mock;
  let host: ArgumentsHost;
  let capturedStatus: number | undefined;
  let capturedBody: unknown;

  beforeEach(() => {
    filter = new AllExceptionsFilter();
    capturedStatus = undefined;
    capturedBody = undefined;

    jsonMock = jest.fn((body: unknown) => {
      capturedBody = body;
    });
    statusMock = jest.fn((status: number) => {
      capturedStatus = status;
      return { json: jsonMock };
    });

    const response = { status: statusMock };
    const request = { method: 'POST', url: '/api/test' };

    host = {
      switchToHttp: () => ({
        getResponse: () => response,
        getRequest: () => request,
      }),
    } as unknown as ArgumentsHost;
  });

  it('maps a plain HttpException to its status and a stable code', () => {
    filter.catch(new NotFoundException('nope'), host);

    expect(capturedStatus).toBe(HttpStatus.NOT_FOUND);
    expect(capturedBody).toEqual({
      success: false,
      error: { code: 'NOT_FOUND', message: 'nope' },
    });
  });

  it('honors an explicit machine-readable code and details from the exception body', () => {
    filter.catch(
      new BadRequestException({
        message: 'Invalid board state',
        code: 'INVALID_BOARD',
        details: ['Missing Black king (general).'],
      }),
      host,
    );

    expect(capturedStatus).toBe(HttpStatus.BAD_REQUEST);
    expect(capturedBody).toEqual({
      success: false,
      error: {
        code: 'INVALID_BOARD',
        message: 'Invalid board state',
        details: ['Missing Black king (general).'],
      },
    });
  });

  it('flattens class-validator array messages into a validation error with details', () => {
    // NestJS ValidationPipe throws this shape.
    filter.catch(
      new BadRequestException({
        statusCode: 400,
        message: ['field must be a string', 'field should not be empty'],
        error: 'Bad Request',
      }),
      host,
    );

    expect(capturedStatus).toBe(HttpStatus.BAD_REQUEST);
    expect(capturedBody).toMatchObject({
      success: false,
      error: {
        code: 'BAD_REQUEST',
        message: 'Validation failed',
        details: ['field must be a string', 'field should not be empty'],
      },
    });
  });

  it('omits the details key entirely when there are none', () => {
    filter.catch(new BadRequestException('just a message'), host);

    const body = capturedBody as { error: Record<string, unknown> };
    expect(body.error).not.toHaveProperty('details');
  });

  it('maps an unknown (non-HTTP) error to a generic 500 without leaking internals', () => {
    filter.catch(new Error('database password is hunter2'), host);

    expect(capturedStatus).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(capturedBody).toEqual({
      success: false,
      error: { code: 'INTERNAL_ERROR', message: 'An unexpected error occurred.' },
    });
    // The raw error message must never reach the client.
    expect(JSON.stringify(capturedBody)).not.toContain('hunter2');
  });

  it('derives a fallback code for statuses without an explicit mapping', () => {
    filter.catch(new HttpException('teapot', 418), host);

    expect(capturedStatus).toBe(418);
    expect((capturedBody as { error: { code: string } }).error.code).toBe('HTTP_418');
  });

  it('maps 429 to a RATE_LIMITED code', () => {
    filter.catch(new HttpException('slow down', HttpStatus.TOO_MANY_REQUESTS), host);

    expect((capturedBody as { error: { code: string } }).error.code).toBe('RATE_LIMITED');
  });

  it('mirrors a failed request to the error log (category "request" with status + code)', () => {
    const logMock = jest.fn();
    const logged = new AllExceptionsFilter({ log: logMock } as never);

    logged.catch(new NotFoundException('nope'), host);

    expect(logMock).toHaveBeenCalledTimes(1);
    expect(logMock).toHaveBeenCalledWith(
      'request',
      expect.objectContaining({
        method: 'POST',
        url: '/api/test',
        status: HttpStatus.NOT_FOUND,
        code: 'NOT_FOUND',
        message: 'nope',
      }),
    );
  });

  it('logs a stack only for server (5xx) faults', () => {
    const logMock = jest.fn();
    const logged = new AllExceptionsFilter({ log: logMock } as never);

    logged.catch(new Error('boom'), host);

    const fields = logMock.mock.calls[0][1] as Record<string, unknown>;
    expect(fields.status).toBe(HttpStatus.INTERNAL_SERVER_ERROR);
    expect(typeof fields.stack).toBe('string');
  });

  it('silently ignores a client-aborted request without writing a response', () => {
    const response = { status: statusMock, writable: false };
    const request = { method: 'POST', url: '/api/analysis/screenshot', destroyed: true };
    const abortHost = {
      switchToHttp: () => ({
        getResponse: () => response,
        getRequest: () => request,
      }),
    } as unknown as ArgumentsHost;

    // Multer throws a plain Error('Request aborted') when the upload socket
    // closes mid-stream; we must not try to respond on a dead socket.
    filter.catch(new Error('Request aborted'), abortHost);

    expect(statusMock).not.toHaveBeenCalled();
    expect(jsonMock).not.toHaveBeenCalled();
  });
});
