import { parseTrustProxy } from './trust-proxy.util';

describe('parseTrustProxy', () => {
  it('returns undefined for an unset value, so Express keeps its default', () => {
    // The default must stay "trust nothing": a spoofable X-Forwarded-For would
    // let any caller mint a fresh IP bucket and walk past the rate caps.
    expect(parseTrustProxy('')).toBeUndefined();
    expect(parseTrustProxy('   ')).toBeUndefined();
  });

  it('passes named presets and address lists through for Express to parse', () => {
    // 'loopback' is the setting for the documented Caddy-on-the-same-host deploy.
    expect(parseTrustProxy('loopback')).toBe('loopback');
    expect(parseTrustProxy(' uniquelocal ')).toBe('uniquelocal');
    expect(parseTrustProxy('127.0.0.1, 10.0.0.0/8')).toBe('127.0.0.1, 10.0.0.0/8');
  });

  it('parses a hop count as a number, not a string', () => {
    expect(parseTrustProxy('1')).toBe(1);
    expect(parseTrustProxy('0')).toBe(0);
  });

  it('parses the booleans', () => {
    expect(parseTrustProxy('true')).toBe(true);
    expect(parseTrustProxy('false')).toBe(false);
  });
});
