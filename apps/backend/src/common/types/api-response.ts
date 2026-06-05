/**
 * Shared API envelope contract. Mirrors exactly what the Flutter client
 * expects. The ResponseInterceptor produces ApiSuccess; the
 * AllExceptionsFilter produces ApiError.
 */

export interface ApiSuccess<T> {
  success: true;
  data: T;
}

export interface ApiErrorBody {
  code: string;
  message: string;
  details?: unknown;
}

export interface ApiError {
  success: false;
  error: ApiErrorBody;
}

export type ApiResponse<T> = ApiSuccess<T> | ApiError;
