import { validateEnv } from './env.validation';

/**
 * Strongly-typed application configuration shape consumed via ConfigService.
 * Grouped by concern for clarity and easy injection.
 */
export interface AppConfig {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  ai: {
    provider: 'gemini' | 'openai' | 'mock';
    geminiApiKey: string;
    openaiApiKey: string;
    openaiModel: string;
    geminiModel: string;
  };
  engine: {
    provider: 'pikafish' | 'mock';
    pikafishBinaryPath: string;
    pikafishNnuePath: string;
    /** File served at GET /api/engine/net — the Pikafish master-net the ON-DEVICE
     *  app downloads (must be the ONDEVICE_NET_BYTES-sized net, NOT the server
     *  engine's own pikafishNnuePath). Copied to the host on each release. */
    onDeviceNetPath: string;
    uciVariant: string;
    defaultDepth: number;
    defaultMoveTimeMs: number;
    threads: number;
    hashMb: number;
    multiPv: number;
    moveOverheadMs: number;
  };
  upload: {
    maxBytes: number;
  };
  /** Install-grant store (JSON files). */
  hints: {
    dataDir: string;
  };
  /** Date-grouped error/failure logs. */
  logging: {
    dir: string;
  };
  rateLimit: {
    ttlSeconds: number;
    limit: number;
    /** Per-device rolling window for the analysis endpoints (seconds). */
    deviceWindowSeconds: number;
    /** Max analyses per device within that window. */
    deviceLimit: number;
  };
  /** Remote config served to the app by GET /api/config. */
  features: {
    ads: { rewarded: boolean; banner: boolean; appOpen: boolean; useReal: boolean };
    hints: { freeOnInstall: number; ownKeyDivisor: number };
    onDevice: { enabled: boolean; netUrl: string; netBytes: number; visionModel: string };
    /** History/local-storage tunables. */
    history: { storedScreenshotsMax: number };
    /** Visibility of optional settings sections (all default OFF). */
    ui: {
      backend: boolean;
      providers: boolean;
      engineTuning: boolean;
      visionModel: boolean;
      licenses: boolean;
      deviceId: boolean;
    };
    /** Launcher icon + name variant: 'auto' follows the in-app App-language. */
    appIcon: { variant: 'auto' | 'vi' | 'en' };
  };
  /** Admin API (config/grants/installs management). */
  admin: { secret: string };
}

/**
 * Config factory passed to ConfigModule.forRoot({ load: [configuration] }).
 * Validates env once and projects it into the typed AppConfig tree.
 */
export function configuration(): { app: AppConfig } {
  const env = validateEnv(process.env);

  const app: AppConfig = {
    nodeEnv: env.NODE_ENV,
    port: env.PORT,
    ai: {
      provider: env.AI_PROVIDER,
      geminiApiKey: env.GEMINI_API_KEY,
      openaiApiKey: env.OPENAI_API_KEY,
      openaiModel: env.OPENAI_MODEL,
      geminiModel: env.GEMINI_MODEL,
    },
    engine: {
      provider: env.ENGINE_PROVIDER,
      pikafishBinaryPath: env.PIKAFISH_BINARY_PATH,
      pikafishNnuePath: env.PIKAFISH_NNUE_PATH,
      onDeviceNetPath: env.ONDEVICE_NET_PATH,
      uciVariant: env.ENGINE_UCI_VARIANT,
      defaultDepth: env.ENGINE_DEFAULT_DEPTH,
      defaultMoveTimeMs: env.ENGINE_DEFAULT_MOVE_TIME_MS,
      threads: env.ENGINE_THREADS,
      hashMb: env.ENGINE_HASH_MB,
      multiPv: env.ENGINE_MULTIPV,
      moveOverheadMs: env.ENGINE_MOVE_OVERHEAD_MS,
    },
    upload: {
      maxBytes: env.MAX_UPLOAD_BYTES,
    },
    hints: {
      dataDir: env.HINTS_DATA_DIR,
    },
    logging: {
      dir: env.LOGS_DIR,
    },
    rateLimit: {
      ttlSeconds: env.RATE_LIMIT_TTL,
      limit: env.RATE_LIMIT_LIMIT,
      deviceWindowSeconds: env.RATE_LIMIT_DEVICE_WINDOW_SECONDS,
      deviceLimit: env.RATE_LIMIT_DEVICE_LIMIT,
    },
    features: {
      ads: {
        rewarded: env.FEATURE_REWARDED_ADS,
        banner: env.FEATURE_BANNER_ADS,
        appOpen: env.FEATURE_APP_OPEN_ADS,
        useReal: env.FEATURE_USE_REAL_ADS,
      },
      hints: {
        freeOnInstall: env.HINTS_FREE_ON_INSTALL,
        ownKeyDivisor: env.HINTS_OWN_KEY_DIVISOR,
      },
      onDevice: {
        enabled: env.ONDEVICE_ENABLED,
        netUrl: env.ONDEVICE_NET_URL,
        netBytes: env.ONDEVICE_NET_BYTES,
        visionModel: env.ONDEVICE_VISION_MODEL,
      },
      history: {
        storedScreenshotsMax: env.STORED_SCREENSHOTS_MAX,
      },
      ui: {
        backend: env.FEATURE_UI_BACKEND,
        providers: env.FEATURE_UI_PROVIDERS,
        engineTuning: env.FEATURE_UI_ENGINE_TUNING,
        visionModel: env.FEATURE_UI_VISION_MODEL,
        licenses: env.FEATURE_UI_LICENSES,
        deviceId: env.FEATURE_UI_DEVICE_ID,
      },
      appIcon: { variant: env.APP_ICON_VARIANT },
    },
    admin: { secret: env.ADMIN_SECRET },
  };

  return { app };
}
