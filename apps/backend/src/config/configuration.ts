import { validateEnv } from './env.validation';

/**
 * Strongly-typed application configuration shape consumed via ConfigService.
 * Grouped by concern for clarity and easy injection.
 */
export interface AppConfig {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  /** Express `trust proxy` value; empty = trust nothing (use the socket peer). */
  trustProxy: string;
  ai: {
    provider: 'gemini' | 'openai' | 'apikeyfun' | 'mock';
    /** When true, IGNORE the client-supplied provider and always use `provider`
     *  (operator authority — lets the server switch the fleet's cloud vision
     *  even for already-installed apps that send an explicit provider). */
    providerEnforce: boolean;
    geminiApiKey: string;
    openaiApiKey: string;
    openaiModel: string;
    geminiModel: string;
    /** api.apikey.fun (OpenAI-compatible aggregator) key + model. */
    apikeyfunApiKey: string;
    apikeyfunModel: string;
    /** Which local bridge an allowlisted device tries first. At most one runs:
     *  Local Codex and Local Claude are mutually exclusive by construction. */
    localVisionProvider: 'codex' | 'claude' | 'none';
    /** Shared secret (header `x-local-vision-token`) required ALONGSIDE the
     *  device allowlist before any request reaches a local bridge. Empty
     *  disables the local-bridge path entirely. */
    localVisionRolloutToken: string;
    /** Codex HTTP bridge used for device-gated Local Codex vision. */
    localCodexUrl: string;
    localCodexToken: string;
    /** Blank model/effort values inherit the bridge server defaults. */
    localCodexModel: string;
    localCodexReasoningEffort: string;
    localCodexTimeoutMs: number;
    /** Mother Claude HTTP bridge used for device-gated Local Claude vision. */
    localClaudeUrl: string;
    localClaudeToken: string;
    /** Blank model/effort values inherit the bridge server defaults. */
    localClaudeModel: string;
    localClaudeEffort: string;
    /** Blank runs in the bridge's own default working directory. */
    localClaudeCwd: string;
    localClaudePermissionMode: string;
    localClaudeTimeoutMs: number;
    /** Downscale/recompress uploads to the provider's pixel budget pre-call. */
    visionPreprocess: boolean;
    visionImageShortSide: number;
    visionImageLongSide: number;
    /** Cap on the model's output tokens (0 = no cap). */
    maxOutputTokens: number;
    /** Retries on a transient vision-API failure. */
    maxRetries: number;
    /** Optional accuracy cascade to a stronger model on a weak primary read. */
    cascade: { enabled: boolean; model: string; minConfidence: number };
  };
  engine: {
    provider: 'pikafish' | 'mock';
    /** When true, IGNORE the client-supplied engineProvider and always use
     *  `provider` (operator authority — symmetric with ai.providerEnforce). */
    providerEnforce: boolean;
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
    /** Warm persistent engine processes kept by the pool (concurrency bound). */
    poolSize: number;
    /** Spawn + warm an engine at boot to hide the first-solve cold start. */
    prewarm: boolean;
    /** Minimum engines the idle reaper keeps warm. */
    keepWarm: number;
  };
  upload: {
    maxBytes: number;
  };
  /** Runtime data directory for grant ledgers and device allowlists. */
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
    /** Max analyses per source IP within that window (always counted).
     *  Resolved value: RATE_LIMIT_IP_LIMIT, or 5x deviceLimit when it is 0. */
    ipLimit: number;
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
    trustProxy: env.TRUST_PROXY,
    ai: {
      provider: env.AI_PROVIDER,
      providerEnforce: env.AI_PROVIDER_ENFORCE,
      geminiApiKey: env.GEMINI_API_KEY,
      openaiApiKey: env.OPENAI_API_KEY,
      openaiModel: env.OPENAI_MODEL,
      geminiModel: env.GEMINI_MODEL,
      apikeyfunApiKey: env.APIKEYFUN_API_KEY,
      apikeyfunModel: env.APIKEYFUN_MODEL,
      localCodexUrl: env.LOCAL_CODEX_URL,
      localCodexToken: env.LOCAL_CODEX_TOKEN,
      localCodexModel: env.LOCAL_CODEX_MODEL,
      localCodexReasoningEffort: env.LOCAL_CODEX_REASONING_EFFORT,
      localCodexTimeoutMs: env.LOCAL_CODEX_TIMEOUT_MS,
      localVisionProvider: env.AI_LOCAL_VISION_PROVIDER,
      localVisionRolloutToken: env.LOCAL_VISION_ROLLOUT_TOKEN,
      localClaudeUrl: env.LOCAL_CLAUDE_URL,
      localClaudeToken: env.LOCAL_CLAUDE_TOKEN,
      localClaudeModel: env.LOCAL_CLAUDE_MODEL,
      localClaudeEffort: env.LOCAL_CLAUDE_EFFORT,
      localClaudeCwd: env.LOCAL_CLAUDE_CWD,
      localClaudePermissionMode: env.LOCAL_CLAUDE_PERMISSION_MODE,
      localClaudeTimeoutMs: env.LOCAL_CLAUDE_TIMEOUT_MS,
      visionPreprocess: env.VISION_PREPROCESS,
      visionImageShortSide: env.VISION_IMAGE_SHORT_SIDE,
      visionImageLongSide: env.VISION_IMAGE_LONG_SIDE,
      maxOutputTokens: env.VISION_MAX_OUTPUT_TOKENS,
      maxRetries: env.VISION_MAX_RETRIES,
      cascade: {
        enabled: env.VISION_CASCADE_ENABLED,
        model: env.VISION_CASCADE_MODEL,
        minConfidence: env.VISION_CASCADE_MIN_CONFIDENCE,
      },
    },
    engine: {
      provider: env.ENGINE_PROVIDER,
      providerEnforce: env.ENGINE_PROVIDER_ENFORCE,
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
      poolSize: env.ENGINE_POOL_SIZE,
      prewarm: env.ENGINE_PREWARM,
      keepWarm: env.ENGINE_KEEP_WARM,
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
      // 0 = auto. Tracking the device cap keeps the IP bucket a backstop for
      // unmetered callers rather than a lower ceiling on honest ones.
      ipLimit: env.RATE_LIMIT_IP_LIMIT || env.RATE_LIMIT_DEVICE_LIMIT * 5,
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
