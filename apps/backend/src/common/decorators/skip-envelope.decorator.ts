import { SetMetadata, CustomDecorator } from '@nestjs/common';

/** Metadata key the ResponseInterceptor reads to bypass wrapping. */
export const SKIP_ENVELOPE_KEY = 'skipEnvelope';

/**
 * Mark a route handler (or controller) so the global ResponseInterceptor
 * returns its payload verbatim instead of wrapping it in { success, data }.
 * Used by GET /api/health.
 */
export const SkipEnvelope = (): CustomDecorator<string> => SetMetadata(SKIP_ENVELOPE_KEY, true);
