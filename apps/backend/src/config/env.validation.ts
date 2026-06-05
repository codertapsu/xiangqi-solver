import { z } from 'zod';

/**
 * Zod schema that validates AND defaults the process environment.
 *
 * Every field has a safe default so the application boots with ZERO
 * configuration. The defaults select the fully offline / deterministic
 * "mock" providers, meaning no secrets or external binaries are required.
 */

/** Coerce a string env value into a bounded integer with a default. */
const intFromEnv = (def: number, min: number, max: number) =>
  z.coerce.number().int().min(min).max(max).default(def);

export const aiProviderSchema = z.enum(['gemini', 'openai', 'mock']);
export const engineProviderSchema = z.enum(['pikafish', 'mock']);

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),

  PORT: intFromEnv(3000, 1, 65535),

  AI_PROVIDER: aiProviderSchema.default('mock'),
  ENGINE_PROVIDER: engineProviderSchema.default('mock'),

  // AI credentials (optional; required only by the matching real provider).
  GEMINI_API_KEY: z.string().default(''),
  OPENAI_API_KEY: z.string().default(''),
  OPENAI_MODEL: z.string().default('gpt-4o-mini'),
  GEMINI_MODEL: z.string().default('gemini-1.5-flash'),

  // Engine settings.
  PIKAFISH_BINARY_PATH: z.string().default(''),
  // Absolute path to pikafish.nnue. If empty, the engine relies on its default
  // (a "pikafish.nnue" co-located with the binary's working directory).
  PIKAFISH_NNUE_PATH: z.string().default(''),
  ENGINE_DEFAULT_DEPTH: intFromEnv(12, 1, 30),
  ENGINE_DEFAULT_MOVE_TIME_MS: intFromEnv(1000, 50, 60000),
  // Pikafish UCI options (no-ops for the mock engine). Pikafish has NO skill/elo
  // option — strength is controlled only by depth/movetime above.
  ENGINE_THREADS: intFromEnv(1, 1, 1024),
  ENGINE_HASH_MB: intFromEnv(128, 1, 32768),
  ENGINE_MULTIPV: intFromEnv(1, 1, 10),
  ENGINE_MOVE_OVERHEAD_MS: intFromEnv(10, 0, 5000),

  // Upload guardrails.
  MAX_UPLOAD_BYTES: intFromEnv(8_388_608, 1, 64 * 1024 * 1024),

  // Rate limiting.
  RATE_LIMIT_TTL: intFromEnv(60, 1, 86400),
  RATE_LIMIT_LIMIT: intFromEnv(30, 1, 100000),
});

export type Env = z.infer<typeof envSchema>;

/**
 * Validate the raw env. Throws a readable aggregated error on failure so
 * misconfiguration fails fast at boot instead of at request time.
 */
export function validateEnv(config: Record<string, unknown>): Env {
  const parsed = envSchema.safeParse(config);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((issue) => `  - ${issue.path.join('.') || '(root)'}: ${issue.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  return parsed.data;
}
