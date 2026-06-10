import { z } from 'zod';

/**
 * Zod schema for the remote-config `features` object (AppConfig['features']).
 * Used to validate an admin's config override before persisting it, and to
 * reject a corrupt override file on read. Keep in sync with configuration.ts.
 */
export const featuresSchema = z.object({
  ads: z.object({
    rewarded: z.boolean(),
    banner: z.boolean(),
    appOpen: z.boolean(),
    useReal: z.boolean(),
  }),
  hints: z.object({
    freeOnInstall: z.number().int().min(0).max(100_000),
    ownKeyDivisor: z.number().int().min(1).max(100),
  }),
  onDevice: z.object({
    enabled: z.boolean(),
    netUrl: z.string(),
    netBytes: z.number().int().min(0),
    visionModel: z.string(),
  }),
  history: z.object({
    storedScreenshotsMax: z.number().int().min(0).max(100),
  }),
  ui: z.object({
    backend: z.boolean(),
    providers: z.boolean(),
    engineTuning: z.boolean(),
    visionModel: z.boolean(),
    licenses: z.boolean(),
    deviceId: z.boolean(),
  }),
  appIcon: z.object({ variant: z.enum(['auto', 'vi', 'en']) }),
});

export type Features = z.infer<typeof featuresSchema>;
