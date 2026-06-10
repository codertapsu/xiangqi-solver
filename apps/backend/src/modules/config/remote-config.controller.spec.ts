import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { RemoteConfigController } from './remote-config.controller';
import { AppConfig } from '../../config/configuration';
import { ConfigOverrideStore } from '../admin/config-override.store';

describe('RemoteConfigController', () => {
  const features: AppConfig['features'] = {
    ads: { rewarded: false, banner: true, appOpen: false, useReal: false },
    hints: { freeOnInstall: 10, ownKeyDivisor: 3 },
    onDevice: {
      enabled: true,
      netUrl: 'https://example/pikafish.nnue',
      netBytes: 50760458,
      visionModel: 'gpt-5.4',
    },
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

  async function build(
    effective: AppConfig['features'] = features,
  ): Promise<RemoteConfigController> {
    const moduleRef = await Test.createTestingModule({
      controllers: [RemoteConfigController],
      providers: [
        {
          provide: ConfigService,
          useValue: { get: (key: string) => (key === 'app.features' ? features : undefined) },
        },
        {
          provide: ConfigOverrideStore,
          useValue: { effective: async () => effective, isActive: async () => false },
        },
      ],
    }).compile();
    return moduleRef.get(RemoteConfigController);
  }

  it('returns the env feature config when there is no admin override', async () => {
    const controller = await build();
    expect(await controller.getConfig()).toEqual(features);
    expect((await controller.getConfig()).ads.rewarded).toBe(false);
  });

  it('serves the admin override when one is active', async () => {
    const overridden: AppConfig['features'] = {
      ...features,
      ads: { ...features.ads, rewarded: true },
      history: { storedScreenshotsMax: 9 },
    };
    const controller = await build(overridden);
    const got = await controller.getConfig();
    expect(got.ads.rewarded).toBe(true);
    expect(got.history.storedScreenshotsMax).toBe(9);
  });
});
