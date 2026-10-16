/**
 * Express `trust proxy` setting, parsed from the TRUST_PROXY env value.
 *
 * `req.ip` is the SOCKET peer unless Express is told which hops to trust. Behind
 * the documented Caddy reverse proxy (deploy/Caddyfile → 127.0.0.1:3000) that
 * peer is Caddy itself, so every request would share one IP — collapsing both
 * the global ThrottlerGuard and the per-source-IP cap in [DeviceRateLimitGuard]
 * into a single fleet-wide bucket.
 *
 * It is opt-in and OFF by default because the opposite mistake is worse:
 * trusting `X-Forwarded-For` when nothing rewrites it lets any caller spoof its
 * own IP and escape metering entirely. Set it to exactly what sits in front:
 *
 *  - ''        (default) no proxy — use the socket peer.
 *  - 'loopback' Caddy/nginx on the same host (the deploy/Caddyfile setup).
 *  - '1', '2'   trust that many hops closest to the server.
 *  - 'true'     trust every hop. Only behind a proxy that REPLACES the header.
 *  - a comma-separated list of IPs/CIDRs — trust exactly those.
 */
export function parseTrustProxy(value: string): boolean | number | string | undefined {
  const raw = value.trim();
  if (!raw) return undefined;
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  if (/^\d+$/.test(raw)) return Number(raw);
  // 'loopback' | 'linklocal' | 'uniquelocal' | IP / CIDR list — Express parses
  // these itself, so pass them through as written.
  return raw;
}
