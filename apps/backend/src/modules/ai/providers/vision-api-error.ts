import { ServiceUnavailableException } from '@nestjs/common';
import { describeFetchError } from './fetch-error.util';

/**
 * Shared failure type for the cloud vision providers, with TWO channels:
 *
 *  - the CLIENT channel — the exception body, which is a fixed message plus a
 *    stable `VISION_*` code and nothing else, and
 *  - the DIAGNOSTIC channel — [diagnostics], which carries the vendor's own
 *    message/code/raw body and never leaves the error log.
 *
 * Vendor strings are not shown to users. They are written for API consumers
 * (OpenAI's 401 text embeds the partially masked key it was given plus a
 * platform.openai.com billing URL), the project does not control their wording,
 * and the whole body reaches the phone verbatim: AnalysisService rethrows,
 * AllExceptionsFilter copies `message`/`details` into the error envelope, and
 * the app renders it. Keying the public error vocabulary on them is just as
 * bad — a client cannot branch on `code` when it is `invalid_api_key` from one
 * provider and `VISION_API_ERROR` from the next.
 *
 * `diagnostics` is a plain field, NOT part of `getResponse()`, so the filter
 * cannot serialize it by accident; providers copy it into ErrorLogService.
 */
export type VisionErrorCode = 'VISION_UNAVAILABLE' | 'VISION_API_ERROR' | 'VISION_OUTPUT_TRUNCATED';

/** Log-only detail about a failure (vendor text, HTTP status, transport cause). */
export type VisionErrorDiagnostics = Record<string, unknown>;

/** The single user-visible sentence for an unusable vision backend (401/403). */
export const VISION_UNAVAILABLE_MESSAGE =
  'Board reading is unavailable right now. Please try again later.';

/** The single user-visible sentence for every other vision-API failure. */
export const VISION_API_ERROR_MESSAGE = 'Board reading failed. Please try again in a moment.';

/**
 * The user-visible sentence when the model was cut off at the output-token cap.
 *
 * The remedy ("raise VISION_MAX_OUTPUT_TOKENS") is an OPERATOR instruction about
 * a server env var, so it goes to the log. What the user needs to know is only
 * that the read did not finish — and, importantly, NOT that their screenshot was
 * unclear, which is what they were told before the truncation check was hoisted
 * above the empty-body guard.
 */
export const VISION_TRUNCATED_MESSAGE =
  'Board reading was cut short before the whole board was read. Please try again.';

/**
 * Appended when the vendor rejected the IMAGE rather than the request: that is
 * the one upstream failure the user can act on, and the sentence is ours, not
 * the vendor's.
 */
export const VISION_IMAGE_REJECTED_HINT =
  ' The screenshot may be too small, corrupted, or not a real image.';

export class VisionApiError extends ServiceUnavailableException {
  readonly code: VisionErrorCode;
  readonly diagnostics: VisionErrorDiagnostics;

  constructor(code: VisionErrorCode, message: string, diagnostics: VisionErrorDiagnostics = {}) {
    super({ message, code });
    this.code = code;
    this.diagnostics = diagnostics;
  }
}

/** An OpenAI-style error object, as an HTTP body or an in-band SSE frame. */
export interface VendorError {
  message?: string;
  code?: string;
  type?: string;
}

/**
 * Best-effort read of an OpenAI-style `{ error: { message, code } }` body. The
 * shape is shared by OpenAI, api.apikey.fun and Gemini (whose `code` is numeric,
 * hence the stringification). Anything unparseable yields an empty object — the
 * raw body is logged separately.
 */
export function parseVendorError(raw: string): VendorError {
  try {
    const parsed = JSON.parse(raw) as {
      error?: { message?: unknown; code?: unknown; status?: unknown; type?: unknown };
    };
    const err = parsed.error;
    if (!err || typeof err !== 'object') return {};
    const code = err.code ?? err.status;
    return {
      ...(typeof err.message === 'string' ? { message: err.message } : {}),
      ...(typeof code === 'string' || typeof code === 'number' ? { code: String(code) } : {}),
      ...(typeof err.type === 'string' ? { type: err.type } : {}),
    };
  } catch {
    return {};
  }
}

/**
 * A non-OK vendor HTTP response. 401/403 means the deployment's credentials are
 * rejected (an operator problem) and maps to VISION_UNAVAILABLE; everything
 * else is VISION_API_ERROR. The vendor's reason goes to the log only.
 */
export function vendorHttpFailure(status: number, body: string): VisionApiError {
  const vendor = parseVendorError(body);
  const unavailable = status === 401 || status === 403;
  const message =
    (unavailable ? VISION_UNAVAILABLE_MESSAGE : VISION_API_ERROR_MESSAGE) +
    (vendor.code === 'image_parse_error' ? VISION_IMAGE_REJECTED_HINT : '');
  return new VisionApiError(unavailable ? 'VISION_UNAVAILABLE' : 'VISION_API_ERROR', message, {
    httpStatus: status,
    ...vendorFields(vendor),
    ...(body ? { vendorBody: body.slice(0, 500) } : {}),
  });
}

/**
 * An upstream failure relayed IN-BAND after a 200 (an OpenAI-compatible
 * aggregator commits SSE headers, then sends `data: {"error":{…}}`). Same two
 * channels; the transport succeeded, so this is never VISION_UNAVAILABLE.
 */
export function vendorStreamFailure(vendor: VendorError): VisionApiError {
  return new VisionApiError('VISION_API_ERROR', VISION_API_ERROR_MESSAGE, {
    inBandError: true,
    ...vendorFields(vendor),
  });
}

/**
 * A transport-level failure (DNS, TLS, socket reset). The text is Node's — it
 * names hosts and error codes — so it is diagnostics, not a user message.
 *
 * Node's fetch reports nearly everything as the bare message "fetch failed" and
 * hides the actionable reason in `cause`, so the chain is walked by the shared
 * describeFetchError (bounded, secret-free) rather than read off `.message`.
 */
export function transportFailure(err: unknown): VisionApiError {
  return new VisionApiError('VISION_API_ERROR', VISION_API_ERROR_MESSAGE, {
    cause: describeFetchError(err),
  });
}

/**
 * The model stopped at the output-token cap. Deterministic, so callers must not
 * retry it; the operator's remedy travels as diagnostics.
 */
export function truncationFailure(remedy: string): VisionApiError {
  return new VisionApiError('VISION_OUTPUT_TRUNCATED', VISION_TRUNCATED_MESSAGE, { remedy });
}

/** The vendor's own fields, namespaced so a log line can be grepped by origin. */
function vendorFields(vendor: VendorError): VisionErrorDiagnostics {
  return {
    ...(vendor.message ? { vendorMessage: vendor.message } : {}),
    ...(vendor.code ? { vendorCode: vendor.code } : {}),
    ...(vendor.type ? { vendorType: vendor.type } : {}),
  };
}
