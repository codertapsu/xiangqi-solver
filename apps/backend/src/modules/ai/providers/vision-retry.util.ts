/**
 * Shared retry policy for the cloud vision providers.
 *
 * A vision call is a single multi-second LLM request; a TRANSIENT blip (rate
 * limit, upstream 5xx, network timeout, empty body) otherwise wastes the whole
 * solve. We retry those a few times with short jittered backoff. We do NOT
 * retry deterministic failures: a 4xx (bad key, unreadable image) or a 200 that
 * parses to an invalid board — re-asking would just reproduce them.
 */

/** Outcome classification for a single attempt. */
export type AttemptResult<T> =
  | { ok: true; value: T }
  | { ok: false; retryable: boolean; error: Error };

/** HTTP statuses worth retrying: rate limiting + transient upstream faults. */
export function isTransientStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}

/** Backoff before retry N (0-based): ~250ms, ~500ms, ~1s … plus jitter. */
export function backoffMs(attempt: number): number {
  const base = 250 * 2 ** attempt;
  const jitter = Math.floor(Math.random() * 100);
  return Math.min(base + jitter, 4000);
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    timer.unref?.();
  });
}

/**
 * Run [attempt] up to (maxRetries + 1) times, retrying only while it reports
 * `retryable`. Returns the first success or throws the last error.
 */
export async function withRetries<T>(
  maxRetries: number,
  attempt: () => Promise<AttemptResult<T>>,
): Promise<T> {
  let lastError: Error | undefined;
  for (let i = 0; i <= maxRetries; i++) {
    const outcome = await attempt();
    if (outcome.ok) return outcome.value;
    lastError = outcome.error;
    if (!outcome.retryable || i === maxRetries) break;
    await sleep(backoffMs(i));
  }
  throw lastError ?? new Error('Vision request failed.');
}
