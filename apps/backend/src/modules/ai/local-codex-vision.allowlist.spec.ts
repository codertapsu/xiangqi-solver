import { promises as fs } from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';
import { ConfigService } from '@nestjs/config';
import { LocalCodexVisionAllowlist } from './local-codex-vision.allowlist';

const FILE_NAME = 'local-codex-vision-devices.json';

function config(dataDir: string): ConfigService {
  return {
    get: (key: string) => (key === 'app.hints' ? { dataDir } : undefined),
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

  it('lets an allowlisted device through on its device ID alone', async () => {
    // The released app sends only x-device-id; membership is the whole gate.
    await fs.writeFile(filePath, JSON.stringify({ 'device-A': 'test phone' }));
    const allowlist = new LocalCodexVisionAllowlist(config(dataDir));

    expect(await allowlist.isAllowlisted('device-A')).toBe(true);
    expect(await allowlist.isAllowlisted('device-B')).toBe(false);
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
