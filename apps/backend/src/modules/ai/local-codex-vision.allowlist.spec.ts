import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';
import { ConfigService } from '@nestjs/config';
import { LocalCodexVisionAllowlist } from './local-codex-vision.allowlist';

const FILE_NAME = 'local-codex-vision-devices.json';
const ROLLOUT_TOKEN = 'rollout-secret-value';

function config(dataDir: string, localVisionRolloutToken = ROLLOUT_TOKEN): ConfigService {
  return {
    get: (key: string) => {
      if (key === 'app.hints') return { dataDir };
      if (key === 'app.ai') return { localVisionRolloutToken };
      return undefined;
    },
  } as unknown as ConfigService;
}

describe('LocalCodexVisionAllowlist', () => {
  let dataDir: string;
  let filePath: string;

  beforeEach(async () => {
    dataDir = await fs.mkdtemp(path.join(tmpdir(), 'xiangqi-local-codex-'));
    filePath = path.join(dataDir, FILE_NAME);
  });

  afterEach(async () => {
    jest.restoreAllMocks();
    await fs.rm(dataDir, { recursive: true, force: true });
  });

  it('matches exact valid IDs, ignores values and comments, and enforces ID length bounds', async () => {
    const minLengthId = '12345678';
    const maxLengthId = 'x'.repeat(256);
    const specialId = 'D4Uixyz7ZKINq6BAyy2NFhjYJoARCPX5e+ES4FyYldg=';
    await fs.writeFile(
      filePath,
      JSON.stringify({
        _comment: 'operator note',
        [minLengthId]: null,
        [maxLengthId]: { note: 'any JSON value is allowed' },
        [specialId]: 1,
        ['x'.repeat(7)]: true,
        ['x'.repeat(257)]: true,
      }),
    );
    const allowlist = new LocalCodexVisionAllowlist(config(dataDir));

    expect(await allowlist.isAllowlisted(minLengthId)).toBe(true);
    expect(await allowlist.isAllowlisted(maxLengthId)).toBe(true);
    expect(await allowlist.isAllowlisted(specialId)).toBe(true);
    expect(await allowlist.isAllowlisted(specialId.toLowerCase())).toBe(false);
    expect(await allowlist.isAllowlisted('_comment')).toBe(false);
    expect(await allowlist.isAllowlisted('x'.repeat(7))).toBe(false);
    expect(await allowlist.isAllowlisted('x'.repeat(257))).toBe(false);
    expect(await allowlist.isAllowlisted(undefined)).toBe(false);
  });

  it.each([
    ['malformed JSON', '{ not json'],
    ['an array', JSON.stringify(['device-A'])],
    ['null', 'null'],
    ['a primitive', JSON.stringify('device-A')],
  ])('fails closed when the file contains %s', async (_case, contents) => {
    await fs.writeFile(filePath, contents);
    const allowlist = new LocalCodexVisionAllowlist(config(dataDir));

    expect(await allowlist.isAllowlisted('device-A')).toBe(false);
  });

  it('fails closed on a read error and retries successfully on the next request', async () => {
    await fs.writeFile(filePath, JSON.stringify({ 'device-A': 'enabled' }));
    const allowlist = new LocalCodexVisionAllowlist(config(dataDir));
    jest.spyOn(fs, 'readFile').mockRejectedValueOnce(new Error('unreadable'));

    expect(await allowlist.isAllowlisted('device-A')).toBe(false);
    expect(await allowlist.isAllowlisted('device-A')).toBe(true);
  });

  it('fails closed when missing and sees a file created later', async () => {
    const allowlist = new LocalCodexVisionAllowlist(config(dataDir));
    expect(await allowlist.isAllowlisted('device-A')).toBe(false);

    await fs.writeFile(filePath, JSON.stringify({ 'device-A': 'enabled' }));
    expect(await allowlist.isAllowlisted('device-A')).toBe(true);
  });

  describe('rollout-token authorization', () => {
    // `x-device-id` is a PUBLIC value — Settings shows it so users can share it
    // to receive hint grants — so allowlist membership alone must never open the
    // path to the operator's own machine.
    beforeEach(async () => {
      await fs.writeFile(filePath, JSON.stringify({ 'device-A': 'test phone' }));
    });

    it('authorizes only an allowlisted device that ALSO presents the token', async () => {
      const allowlist = new LocalCodexVisionAllowlist(config(dataDir));

      expect(await allowlist.authorize('device-A', ROLLOUT_TOKEN)).toBe(true);
      expect(await allowlist.authorize('device-B', ROLLOUT_TOKEN)).toBe(false);
    });

    it.each([
      ['a missing token', undefined],
      ['an empty token', ''],
      ['a wrong token', 'some-other-secret-val'],
      ['a prefix of the token', ROLLOUT_TOKEN.slice(0, 8)],
      ['the token plus a suffix', `${ROLLOUT_TOKEN}x`],
    ])('refuses an allowlisted device with %s', async (_case, token) => {
      const allowlist = new LocalCodexVisionAllowlist(config(dataDir));

      expect(await allowlist.authorize('device-A', token)).toBe(false);
      expect(allowlist.verifyRolloutToken(token)).toBe(false);
    });

    it('fails closed when LOCAL_VISION_ROLLOUT_TOKEN is unset — even for the empty string', async () => {
      const allowlist = new LocalCodexVisionAllowlist(config(dataDir, ''));

      expect(await allowlist.authorize('device-A', '')).toBe(false);
      expect(await allowlist.authorize('device-A', undefined)).toBe(false);
      expect(allowlist.verifyRolloutToken('')).toBe(false);
    });

    it('checks the token BEFORE touching the allowlist file', async () => {
      const allowlist = new LocalCodexVisionAllowlist(config(dataDir));
      const statSpy = jest.spyOn(fs, 'stat');

      expect(await allowlist.authorize('device-A', 'wrong-secret-value')).toBe(false);
      // An unauthorized caller must not be able to make the server do I/O.
      expect(statSpy).not.toHaveBeenCalled();
    });
  });

  it('uses its mtime cache and live-reloads changed membership', async () => {
    await fs.writeFile(filePath, JSON.stringify({ 'device-A': 'first' }));
    const allowlist = new LocalCodexVisionAllowlist(config(dataDir));
    const readSpy = jest.spyOn(fs, 'readFile');

    expect(await allowlist.isAllowlisted('device-A')).toBe(true);
    expect(await allowlist.isAllowlisted('device-A')).toBe(true);
    expect(readSpy).toHaveBeenCalledTimes(1);

    await fs.writeFile(filePath, JSON.stringify({ 'device-B': 'second' }));
    const changed = new Date(Date.now() + 5_000);
    await fs.utimes(filePath, changed, changed);

    expect(await allowlist.isAllowlisted('device-A')).toBe(false);
    expect(await allowlist.isAllowlisted('device-B')).toBe(true);
    expect(readSpy).toHaveBeenCalledTimes(2);
  });
});
