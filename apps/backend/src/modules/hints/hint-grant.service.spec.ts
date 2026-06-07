import { promises as fs } from 'fs';
import * as os from 'os';
import * as path from 'path';
import { ConfigService } from '@nestjs/config';
import { HintGrantStore } from './hint-grant.store';
import { HintGrantService } from './hint-grant.service';

function fakeConfig(dir: string, freeOnInstall = 10): ConfigService {
  return {
    get: (key: string) => {
      if (key === 'app.hints') return { dataDir: dir };
      if (key === 'app.features') return { hints: { freeOnInstall } };
      return undefined;
    },
  } as unknown as ConfigService;
}

async function makeService(dir: string, freeOnInstall = 10) {
  const config = fakeConfig(dir, freeOnInstall);
  const store = new HintGrantStore(config);
  await store.onModuleInit();
  return { store, service: new HintGrantService(store, config) };
}

describe('HintGrantService', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await fs.mkdtemp(path.join(os.tmpdir(), 'hint-grants-'));
  });

  afterEach(async () => {
    await fs.rm(dir, { recursive: true, force: true });
  });

  it('grants the free starter hints on first install, then 0 on reinstall', async () => {
    const { service } = await makeService(dir, 10);
    expect(await service.claim('device-AAAAAAAA')).toEqual({
      hints: 10,
      source: 'first_install',
    });
    expect(await service.claim('device-AAAAAAAA')).toEqual({
      hints: 0,
      source: 'returning',
    });
  });

  it('records installs durably (a fresh store sees a returning device)', async () => {
    const a = await makeService(dir);
    await a.service.claim('device-PERSIST'); // claim awaits the atomic write
    const b = await makeService(dir);
    expect(await b.service.claim('device-PERSIST')).toEqual({
      hints: 0,
      source: 'returning',
    });
  });

  it('a manual grant overrides the ledger and applies on every reinstall', async () => {
    const { service } = await makeService(dir, 10);
    // Already seen → would be 0...
    await service.claim('device-VIP');
    expect((await service.claim('device-VIP')).source).toBe('returning');
    // ...until we add it to grants.json (re-read live, no restart):
    await fs.writeFile(
      path.join(dir, 'grants.json'),
      JSON.stringify({ 'device-VIP': 1000 }),
      'utf8',
    );
    expect(await service.claim('device-VIP')).toEqual({ hints: 1000, source: 'grant' });
    // and it keeps granting while it stays listed:
    expect(await service.claim('device-VIP')).toEqual({ hints: 1000, source: 'grant' });
  });

  it('ignores comment keys and malformed grant values', async () => {
    const { service } = await makeService(dir, 10);
    await fs.writeFile(
      path.join(dir, 'grants.json'),
      JSON.stringify({ _comment: 'note', 'device-BAD': 'notanumber', 'device-OK': 50 }),
      'utf8',
    );
    expect((await service.claim('device-OK')).hints).toBe(50);
    // device-BAD has a non-numeric value → not listed → falls through to first install.
    expect(await service.claim('device-BAD')).toEqual({ hints: 10, source: 'first_install' });
  });

  it('honors the configured free-on-install count', async () => {
    const { service } = await makeService(dir, 25);
    expect((await service.claim('device-NEW1234')).hints).toBe(25);
  });

  it('fails closed when the install can not be persisted (rolls back in memory)', async () => {
    const { store, service } = await makeService(dir);
    // The data dir vanishes after init → the atomic write can't land.
    await fs.rm(dir, { recursive: true, force: true });
    await expect(service.claim('device-ZZZZZZZZ')).rejects.toBeDefined();
    // Rolled back, so it isn't wrongly treated as already-seen.
    expect(store.hasSeen('device-ZZZZZZZZ')).toBe(false);
  });

  it('refuses to boot on a corrupt installs.json (never silently re-grants)', async () => {
    await fs.writeFile(path.join(dir, 'installs.json'), '{ not valid json', 'utf8');
    const store = new HintGrantStore(fakeConfig(dir));
    await expect(store.onModuleInit()).rejects.toThrow(/corrupt/i);
  });
});
