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

/** Coerce a string env flag ("true"/"1") into a boolean with a default. */
const boolFromEnv = (def: boolean) =>
  z.preprocess(
    (v) => (v === undefined ? def : v === true || v === 'true' || v === '1'),
    z.boolean(),
  );

export const aiProviderSchema = z.enum(['gemini', 'openai', 'mock']);
export const engineProviderSchema = z.enum(['pikafish', 'mock']);

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),

  PORT: intFromEnv(3000, 1, 65535),

  AI_PROVIDER: aiProviderSchema.default('mock'),
  ENGINE_PROVIDER: engineProviderSchema.default('mock'),

  // AI credentials (optional; required only by the matching real provider).
  // Default real provider is OpenAI (gpt-5.4). To switch the cloud vision to
  // Gemini 3 Flash, set AI_PROVIDER=gemini + GEMINI_API_KEY (GEMINI_MODEL
  // already defaults to the Gemini 3 Flash id). Both providers return the
  // SAME parsed board, so the app behaves identically either way.
  GEMINI_API_KEY: z.string().default(''),
  OPENAI_API_KEY: z.string().default(''),
  OPENAI_MODEL: z.string().default('gpt-5.4'),
  GEMINI_MODEL: z.string().default('gemini-3-flash-preview'),

  // Engine settings.
  PIKAFISH_BINARY_PATH: z.string().default(''),
  // UCI_Variant to select before loading the net. Empty for Pikafish. Set to
  // 'xiangqi' when PIKAFISH_BINARY_PATH points at Fairy-Stockfish (so you can
  // run the CC0 xiangqi net — the commercially-clean engine). See MONETIZATION.md.
  ENGINE_UCI_VARIANT: z.string().default(''),
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
  // Global per-IP throttle (all endpoints).
  RATE_LIMIT_TTL: intFromEnv(60, 1, 86400),
  RATE_LIMIT_LIMIT: intFromEnv(30, 1, 100000),
  // Per-device cap for the (paid) analysis endpoints — keyed by the x-device-id
  // header. Hints are a device-local counter on the client, so this is the cheap
  // server-side abuse cap that bounds OpenAI cost per device. Defaults: 100/day.
  RATE_LIMIT_DEVICE_WINDOW_SECONDS: intFromEnv(86400, 1, 2592000),
  RATE_LIMIT_DEVICE_LIMIT: intFromEnv(100, 1, 100000),

  // Install-grant data dir (POST /api/hints/claim). Holds `installs.json` (the
  // ledger that stops a reinstall from re-granting the free starter hints) and
  // `grants.json` (the manual per-device "Hint Grants" allowlist). Simple JSON
  // files; gitignored. Put it on a persistent volume in production.
  HINTS_DATA_DIR: z.string().default('./data'),

  // ---------------------------------------------------------------------------
  // Remote config / feature flags — served by GET /api/config so the app's
  // behavior is tunable WITHOUT a new release. Change these on the server and
  // restart; the app picks them up on next launch.
  // ---------------------------------------------------------------------------
  // Which ad formats the app may show. Rewarded ads are a capped loss-leader, so
  // they default OFF; banner ads are the primary format and default ON.
  FEATURE_REWARDED_ADS: boolFromEnv(false),
  FEATURE_BANNER_ADS: boolFromEnv(true),
  FEATURE_APP_OPEN_ADS: boolFromEnv(false),
  // Whether the app uses the REAL ad unit ids (vs Google's test units). Default
  // OFF so a build never serves real ads until the server explicitly enables it.
  FEATURE_USE_REAL_ADS: boolFromEnv(false),
  // Hint economy. Free hints granted on first install; with the user's OWN
  // OpenAI key we charge 1 hint per N analyses (their key, our engine cost only);
  // with OUR key it's always 1 per analysis (enforced client-side).
  HINTS_FREE_ON_INSTALL: intFromEnv(10, 0, 100000),
  HINTS_OWN_KEY_DIVISOR: intFromEnv(3, 1, 100),
  // On-device Pikafish. The engine binary ships in the APK; the NNUE net is
  // downloaded at runtime from this URL (default = the official master-net, which
  // matches the bundled binary). netBytes lets the app verify a complete download.
  ONDEVICE_ENABLED: boolFromEnv(true),
  ONDEVICE_NET_URL: z
    .string()
    .default(
      'https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue',
    ),
  ONDEVICE_NET_BYTES: intFromEnv(50760458, 0, 1024 * 1024 * 1024),
  // Default OpenAI model the app uses for the on-device (BYO-key) board reading.
  // On-device vision is OpenAI-only; this is the model used when the user hasn't
  // overridden it in Settings. Keep it a capable model (gpt-4o-mini misreads the
  // small glyphs). Tunable from the server without an app release.
  ONDEVICE_VISION_MODEL: z.string().default('gpt-5.4'),
  // Which OPTIONAL settings sections the app exposes. All default OFF (hidden)
  // so a shipped build shows only the core flow; flip per environment to reveal
  // these power-user / debug sections WITHOUT a new release.
  FEATURE_UI_BACKEND: boolFromEnv(false),
  FEATURE_UI_PROVIDERS: boolFromEnv(false),
  FEATURE_UI_ENGINE_TUNING: boolFromEnv(false),
  FEATURE_UI_VISION_MODEL: boolFromEnv(false),
  // The "Open-source licenses" entry in Settings (GPLv3 on-device engine notice).
  FEATURE_UI_LICENSES: boolFromEnv(false),
  // The "Device ID" tile in Settings (users share it to receive a Hint Grant).
  FEATURE_UI_DEVICE_ID: boolFromEnv(false),

  // Which launcher icon + name variant the app shows. 'auto' = follow the in-app
  // App-language; 'vi'/'en' force one. Switches among the icons BUNDLED in the
  // app (Android can't apply a runtime-downloaded image).
  APP_ICON_VARIANT: z.enum(['auto', 'vi', 'en']).default('auto'),
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
