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
  rateLimit: {
    ttlSeconds: number;
    limit: number;
  };
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
    rateLimit: {
      ttlSeconds: env.RATE_LIMIT_TTL,
      limit: env.RATE_LIMIT_LIMIT,
    },
  };

  return { app };
}
