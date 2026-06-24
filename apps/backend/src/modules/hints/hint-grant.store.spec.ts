import { promises as fs } from 'fs';
import * as os from 'os';
import * as path from 'path';
import { ConfigService } from '@nestjs/config';
import { HintGrantStore } from './hint-grant.store';

function fakeConfig(dir: string): ConfigService {
  return {
    get: (key: string) => (key === 'app.hints' ? { dataDir: dir } : undefined),
  } as unknown as ConfigService;
}

async function makeStore(dir: string): Promise<HintGrantStore> {
  const store = new HintGrantStore(fakeConfig(dir));
  await store.onModuleInit();
  return store;
}

const logPath = (dir: string) => path.join(dir, 'installs.log');
const legacyPath = (dir: string) => path.join(dir, 'installs.json');

async function readLines(dir: string): Promise<string[]> {
  const raw = await fs.readFile(logPath(dir), 'utf8');
  return raw.split('\n').filter((l) => l.trim().length > 0);
}

describe('HintGrantStore (append-only install ledger)', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await fs.mkdtemp(path.join(os.tmpdir(), 'install-ledger-'));
  });

  afterEach(async () => {
    await fs.rm(dir, { recursive: true, force: true });
  });

  it('records each install as ONE appended NDJSON line (no whole-ledger rewrite)', async () => {
    const store = await makeStore(dir);
    await store.markSeen('device-A');
    await store.markSeen('device-B');
    await store.flush();

    const lines = await readLines(dir);
    expect(lines).toHaveLength(2);
    const parsed = lines.map((l) => JSON.parse(l) as { i: string; t: string });
    expect(parsed.map((p) => p.i).sort()).toEqual(['device-A', 'device-B']);
    expect(parsed.every((p) => typeof p.t === 'string')).toBe(true);
    // The append-only log is the source of truth; the legacy object file is not written.
    await expect(fs.access(legacyPath(dir))).rejects.toBeDefined();
  });

  it('migrates a legacy installs.json object ledger to installs.log on boot', async () => {
    await fs.writeFile(
      legacyPath(dir),
      JSON.stringify({ 'device-OLD': '2026-01-01T00:00:00.000Z' }),
      'utf8',
    );
    const store = await makeStore(dir);
    expect(store.hasSeen('device-OLD')).toBe(true);
    // The migrated entry now lives in installs.log.
    const lines = await readLines(dir);
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0])).toMatchObject({ i: 'device-OLD' });
    // The legacy file is retired so it can never shadow the log later.
    await expect(fs.access(legacyPath(dir))).rejects.toBeDefined();
    await expect(fs.access(`${legacyPath(dir)}.migrated`)).resolves.toBeUndefined();
  });

  it('REFUSES to boot when installs.log is wholly garbled (fail-loud, not fail-open)', async () => {
    // Every record unreadable -> an empty ledger would re-grant everyone.
    await fs.writeFile(logPath(dir), 'GARBAGE\nmore garbage\n{not json\n', 'utf8');
    const store = new HintGrantStore(fakeConfig(dir));
    await expect(store.onModuleInit()).rejects.toThrow(/corrupt/i);
  });

  it('still tolerates a FEW bad lines among good ones (truncated tail)', async () => {
    const good = JSON.stringify({ i: 'device-KEEP', t: new Date().toISOString() });
    await fs.writeFile(logPath(dir), `${good}\nGARBAGE-TAIL`, 'utf8');
    const store = await makeStore(dir); // must NOT throw — one good record survived
    expect(store.hasSeen('device-KEEP')).toBe(true);
  });

  it('does NOT let an empty installs.log shadow an un-migrated legacy ledger', async () => {
    // e.g. an interrupted first migration left a 0-byte log next to real legacy data.
    await fs.writeFile(logPath(dir), '', 'utf8');
    await fs.writeFile(legacyPath(dir), JSON.stringify({ 'device-LEGACY': 'x' }), 'utf8');
    const store = await makeStore(dir);
    expect(store.hasSeen('device-LEGACY')).toBe(true); // migrated, not shadowed
  });

  it('tolerates a truncated final line on replay (loses only that record)', async () => {
    const good = JSON.stringify({ i: 'device-GOOD', t: new Date().toISOString() });
    await fs.writeFile(logPath(dir), `${good}\n{"i":"device-TRUNC","t":"2026`, 'utf8');
    const store = await makeStore(dir); // must NOT throw
    expect(store.hasSeen('device-GOOD')).toBe(true);
    expect(store.hasSeen('device-TRUNC')).toBe(false);
  });

  it('removeInstall appends a tombstone; a fresh store no longer sees the device', async () => {
    const a = await makeStore(dir);
    await a.markSeen('device-TOMB');
    await a.removeInstall('device-TOMB');
    await a.flush();

    const b = await makeStore(dir);
    expect(b.hasSeen('device-TOMB')).toBe(false);
  });

  it('compacts installs.log when churn bloats it past the threshold', async () => {
    const store = await makeStore(dir);
    // Re-setting one device appends a line each time; the live map stays size 1,
    // so the >1000-line threshold triggers a compaction back to a single line.
    for (let i = 0; i <= 1000; i++) {
      await store.setInstall('device-CHURN', new Date(1700000000000 + i).toISOString());
    }
    await store.flush();

    const lines = await readLines(dir);
    expect(lines.length).toBeLessThanOrEqual(2);
    expect(store.hasSeen('device-CHURN')).toBe(true);
    // The compacted ledger still replays to exactly the one device.
    const fresh = await makeStore(dir);
    expect(fresh.allInstalls()).toEqual({ 'device-CHURN': expect.any(String) });
  });
});
