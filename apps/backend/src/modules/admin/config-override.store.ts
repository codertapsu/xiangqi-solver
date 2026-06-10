import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import { Features, featuresSchema } from './features.schema';

/**
 * Persists an admin-edited remote-config override in
 * `<dataDir>/config-overrides.json` (a full, validated `features` object).
 *
 * When present, it REPLACES the env-derived features for `GET /api/config`
 * (the admin becomes the source of truth; a reset deletes the file to fall back
 * to env). Read is mtime-cached; writes are atomic (temp + rename) and
 * serialized. An invalid file is ignored (env defaults are served) and logged.
 */
@Injectable()
export class ConfigOverrideStore {
  private readonly logger = new Logger(ConfigOverrideStore.name);
  private cache: Features | null = null;
  private mtimeMs = Number.NaN;
  private writeChain: Promise<void> = Promise.resolve();

  constructor(private readonly config: ConfigService) {}

  private get dir(): string {
    return this.config.get<AppConfig['hints']>('app.hints')?.dataDir ?? './data';
  }

  private get filePath(): string {
    return path.join(this.dir, 'config-overrides.json');
  }

  /** The persisted override, or null when absent/invalid (mtime-cached). */
  private async read(): Promise<Features | null> {
    try {
      const stat = await fs.stat(this.filePath);
      if (stat.mtimeMs === this.mtimeMs) return this.cache;
      const raw = await fs.readFile(this.filePath, 'utf8');
      const parsed = featuresSchema.safeParse(JSON.parse(raw));
      if (!parsed.success) {
        this.logger.warn(
          'config-overrides.json is invalid — ignoring it and serving env defaults.',
        );
      }
      this.cache = parsed.success ? parsed.data : null;
      this.mtimeMs = stat.mtimeMs;
      return this.cache;
    } catch {
      this.cache = null;
      this.mtimeMs = Number.NaN;
      return null;
    }
  }

  /** Whether an override is currently active. */
  async isActive(): Promise<boolean> {
    return (await this.read()) !== null;
  }

  /** Effective features = the override if present, else [envFeatures]. */
  async effective(envFeatures: Features): Promise<Features> {
    return (await this.read()) ?? envFeatures;
  }

  /** Persist a validated full features override (atomic, serialized). */
  async set(features: Features): Promise<void> {
    await fs.mkdir(this.dir, { recursive: true });
    const run = this.writeChain.then(async () => {
      const tmp = `${this.filePath}.tmp`;
      await fs.writeFile(tmp, JSON.stringify(features, null, 2), 'utf8');
      await fs.rename(tmp, this.filePath);
      this.cache = features;
      this.mtimeMs = (await fs.stat(this.filePath)).mtimeMs;
    });
    this.writeChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  /** Remove the override file (revert to env defaults). */
  async clear(): Promise<void> {
    const run = this.writeChain.then(async () => {
      await fs.rm(this.filePath, { force: true });
      this.cache = null;
      this.mtimeMs = Number.NaN;
    });
    this.writeChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
}
