/**
 * Bounded, secret-free description of a Node `fetch` failure.
 *
 * Node's fetch reports almost everything as the bare message "fetch failed" and
 * puts the actionable DNS/TCP/TLS reason in `cause` (sometimes nested, sometimes
 * as an `AggregateError.errors` list). Logging only the top-level message makes
 * every network failure look identical, so walk the chain — but with a depth
 * cap, a cycle guard, per-field truncation and an explicit field allowlist, so a
 * log line can never grow unboundedly or carry something it should not.
 */

const MAX_DEPTH = 4;
const MAX_MESSAGE = 1000;
const MAX_NAME = 200;
const MAX_AGGREGATE = 8;

/** Fields that describe *where* a connection failed, never *what was sent*. */
const SAFE_FIELDS = [
  'code',
  'errno',
  'syscall',
  'hostname',
  'host',
  'address',
  'port',
  'localAddress',
] as const;

export function describeFetchError(value: unknown, depth = 0, seen = new Set<unknown>()): unknown {
  if (depth >= MAX_DEPTH) return { truncated: true };
  if (value === null || (typeof value !== 'object' && !(value instanceof Error))) {
    return { value: String(value) };
  }
  if (seen.has(value)) return { circular: true };
  seen.add(value);

  const source = value as Error & Record<string, unknown> & { cause?: unknown; errors?: unknown[] };
  const detail: Record<string, unknown> = {
    name: (typeof source.name === 'string' ? source.name : 'Error').slice(0, MAX_NAME),
    message: (typeof source.message === 'string' ? source.message : String(value)).slice(
      0,
      MAX_MESSAGE,
    ),
  };

  for (const key of SAFE_FIELDS) {
    const field = source[key];
    if (typeof field === 'string') detail[key] = field.slice(0, MAX_MESSAGE);
    else if (typeof field === 'number' || typeof field === 'boolean') detail[key] = field;
  }
  if (source.cause !== undefined) {
    detail.cause = describeFetchError(source.cause, depth + 1, seen);
  }
  if (Array.isArray(source.errors)) {
    detail.errors = source.errors
      .slice(0, MAX_AGGREGATE)
      .map((error) => describeFetchError(error, depth + 1, seen));
  }
  return detail;
}
