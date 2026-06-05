import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { ApiError } from '../types/api-response';

/**
 * Translates every thrown error into the standard error envelope:
 *   { success: false, error: { code, message, details? } }
 *
 * - HttpException: preserve its status and message; derive a stable code.
 * - Unknown errors: 500 INTERNAL_ERROR with a generic message (no leaking
 *   internal details to the client; full error is logged server-side).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    // The client closed the connection before we could respond (e.g. the mobile
    // app was backgrounded or a duplicate/late upload was cancelled mid-stream).
    // The socket is gone, so there is nothing to send and it is not a server
    // fault — log it quietly and bail instead of emitting a scary 500.
    if (this.isClientDisconnect(exception, request, response)) {
      this.logger.warn(`${request.method} ${request.url} -> client disconnected before response`);
      return;
    }

    const { status, code, message, details } = this.normalize(exception);

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(
        `${request.method} ${request.url} -> ${status} ${code}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    } else {
      this.logger.warn(`${request.method} ${request.url} -> ${status} ${code}: ${message}`);
    }

    const body: ApiError = {
      success: false,
      error: { code, message, ...(details !== undefined ? { details } : {}) },
    };

    response.status(status).json(body);
  }

  /**
   * Detects a client-aborted request: Multer throws a plain Error("Request
   * aborted") when the upload socket closes, and the response is no longer
   * writable. In that state any attempt to send a body is pointless (or throws).
   */
  private isClientDisconnect(exception: unknown, request: Request, response: Response): boolean {
    const aborted = exception instanceof Error && /aborted/i.test(exception.message);
    return aborted && (request.destroyed === true || response.writableEnded || !response.writable);
  }

  private normalize(exception: unknown): {
    status: number;
    code: string;
    message: string;
    details?: unknown;
  } {
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const res = exception.getResponse();

      let message = exception.message;
      let details: unknown;
      // Default to a stable status-derived code; an explicit code in the
      // exception body (e.g. INVALID_BOARD, MISSING_FILE) overrides it.
      let code = this.statusToCode(status);

      if (typeof res === 'object' && res !== null) {
        const obj = res as Record<string, unknown>;

        if (typeof obj.message === 'string') {
          message = obj.message;
        } else if (Array.isArray(obj.message)) {
          // class-validator returns an array of constraint messages.
          message = 'Validation failed';
          details = obj.message;
        }

        // Honor an explicit machine-readable code thrown by domain code.
        if (typeof obj.code === 'string' && obj.code.length > 0) {
          code = obj.code;
        }

        // Honor explicit diagnostic details (e.g. the validator's error list),
        // unless validation already populated them from obj.message above.
        if (details === undefined && obj.details !== undefined) {
          details = obj.details;
        }
      }

      return { status, code, message, details };
    }

    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred.',
    };
  }

  /** Map an HTTP status to a stable, machine-readable error code. */
  private statusToCode(status: number): string {
    const map: Record<number, string> = {
      [HttpStatus.BAD_REQUEST]: 'BAD_REQUEST',
      [HttpStatus.UNAUTHORIZED]: 'UNAUTHORIZED',
      [HttpStatus.FORBIDDEN]: 'FORBIDDEN',
      [HttpStatus.NOT_FOUND]: 'NOT_FOUND',
      [HttpStatus.PAYLOAD_TOO_LARGE]: 'PAYLOAD_TOO_LARGE',
      [HttpStatus.UNSUPPORTED_MEDIA_TYPE]: 'UNSUPPORTED_MEDIA_TYPE',
      [HttpStatus.UNPROCESSABLE_ENTITY]: 'UNPROCESSABLE_ENTITY',
      [HttpStatus.TOO_MANY_REQUESTS]: 'RATE_LIMITED',
      [HttpStatus.SERVICE_UNAVAILABLE]: 'SERVICE_UNAVAILABLE',
      [HttpStatus.INTERNAL_SERVER_ERROR]: 'INTERNAL_ERROR',
    };
    return map[status] ?? `HTTP_${status}`;
  }
}
