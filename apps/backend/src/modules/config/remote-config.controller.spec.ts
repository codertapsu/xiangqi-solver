import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { RemoteConfigController } from './remote-config.controller';
import { AppConfig } from '../../config/configuration';

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
    ui: {
      backend: false,
      providers: false,
      engineTuning: false,
      visionModel: false,
      licenses: false,
    },
  };

  it('returns the feature config from app.features', async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [RemoteConfigController],
      providers: [
        {
          provide: ConfigService,
          useValue: { get: (key: string) => (key === 'app.features' ? features : undefined) },
        },
      ],
    }).compile();

    const controller = moduleRef.get(RemoteConfigController);
    expect(controller.getConfig()).toEqual(features);
    expect(controller.getConfig().ads.rewarded).toBe(false);
  });
});
