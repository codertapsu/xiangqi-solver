import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConfigService } from '@nestjs/config';
import { ConfigOverrideStore } from './config-override.store';
import { Features } from './features.schema';

const ENV: Features = {
  ads: { rewarded: false, banner: true, appOpen: false, useReal: false },
  hints: { freeOnInstall: 10, ownKeyDivisor: 3 },
  onDevice: { enabled: true, netUrl: 'http://example/net', netBytes: 1, visionModel: 'gpt-5.4' },
  history: { storedScreenshotsMax: 5 },
  ui: {
    backend: false,
    providers: false,
    engineTuning: false,
    visionModel: false,
    licenses: false,
    deviceId: false,
  },
  appIcon: { variant: 'auto' },
};

function config(dir: string): ConfigService {
  return {
    get: (k: string) => (k === 'app.hints' ? { dataDir: dir } : undefined),
  } as unknown as ConfigService;
}

describe('ConfigOverrideStore', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'xiangqi-cfg-'));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('effective() returns env when no override exists', async () => {
    const store = new ConfigOverrideStore(config(dir));
    expect(await store.effective(ENV)).toEqual(ENV);
    expect(await store.isActive()).toBe(false);
  });

  it('set() persists a validated override that effective() then serves', async () => {
    const store = new ConfigOverrideStore(config(dir));
    const override: Features = {
      ...ENV,
      ads: { ...ENV.ads, rewarded: true },
      history: { storedScreenshotsMax: 9 },
    };
    await store.set(override);

    expect(await store.isActive()).toBe(true);
    expect((await store.effective(ENV)).ads.rewarded).toBe(true);
    expect((await store.effective(ENV)).history.storedScreenshotsMax).toBe(9);

    const onDisk = JSON.parse(
      await readFile(join(dir, 'config-overrides.json'), 'utf8'),
    ) as Features;
    expect(onDisk.ads.rewarded).toBe(true);
  });

  it('clear() removes the override and reverts to env', async () => {
    const store = new ConfigOverrideStore(config(dir));
    await store.set({ ...ENV, ads: { ...ENV.ads, rewarded: true } });
    await store.clear();
    expect(await store.isActive()).toBe(false);
    expect((await store.effective(ENV)).ads.rewarded).toBe(false);
  });

  it('ignores a structurally-invalid override file and serves env', async () => {
    await writeFile(
      join(dir, 'config-overrides.json'),
      JSON.stringify({ ads: { rewarded: 'not-a-boolean' } }),
    );
    const store = new ConfigOverrideStore(config(dir));
    expect(await store.isActive()).toBe(false);
    expect(await store.effective(ENV)).toEqual(ENV);
  });
});
