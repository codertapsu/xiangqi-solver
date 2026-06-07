import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { promises as fs } from 'fs';
import * as path from 'path';
import { AppConfig } from '../../config/configuration';

/**
 * Tiny JSON-file store backing the install-grant flow. Two files live in the
 * configured data dir (HINTS_DATA_DIR, default ./data — gitignored):
 *
 *  - `installs.json` — the INSTALL LEDGER: device ids we have already granted the
 *    free starter hints to, so reinstalling doesn't re-grant them. Map of
 *    `deviceId -> firstSeen ISO date`. Written atomically (temp + rename) and
 *    serialized through a single in-process write chain.
 *
 *  - `grants.json` — the manual HINT GRANTS allowlist: `{ deviceId: hints }`.
 *    Hand-edited to comp a specific device a custom starting balance on every
 *    (re)install. RE-READ on each claim (mtime-cached) so edits apply WITHOUT a
 *    restart. Takes priority over the ledger.
 *
 * In-memory + single-process (matches the "simple JSON file is enough" decision
 * and the existing in-memory DeviceRateLimitGuard). Not shared across replicas.
 */
@Injectable()
export class HintGrantStore implements OnModuleInit {
  private readonly logger = new Logger(HintGrantStore.name);
  private dir = './data';
  private installs = new Map<string, string>(); // deviceId -> firstSeen ISO
  private grants = new Map<string, number>(); // deviceId -> hints
  private grantsMtimeMs = Number.NaN;
  private writeChain: Promise<void> = Promise.resolve(); // serialize installs writes
  private capWarned = false;

  /**
   * Hard cap on ledger size so the JSON file (and the O(n) rewrite on each new
   * device) can't grow without bound under random-device-id spam. Reaching it
   * needs sustained abuse past the per-IP throttler; at that point the JSON store
   * has been outgrown and should move to a DB. Beyond the cap we stop recording
   * (and log once) — availability over strict anti-abuse for that tail.
   */
  private static readonly MAX_INSTALLS = 1_000_000;

  constructor(private readonly config: ConfigService) {}

  async onModuleInit(): Promise<void> {
    this.dir = this.config.get<AppConfig['hints']>('app.hints')?.dataDir ?? './data';
    await fs.mkdir(this.dir, { recursive: true });
    this.installs = await this.readInstalls();
    await this.refreshGrants();
    this.logger.log(
      `Hint-grant store ready (dir=${this.dir}, installs=${this.installs.size}, grants=${this.grants.size}).`,
    );
  }

  private get installsPath(): string {
    return path.join(this.dir, 'installs.json');
  }

  private get grantsPath(): string {
    return path.join(this.dir, 'grants.json');
  }

  /** Whether this device has already been granted its starter hints. */
  hasSeen(deviceId: string): boolean {
    return this.installs.has(deviceId);
  }

  /** The manual Hint Grant for a device, if listed. Re-reads grants.json on change. */
  async grantFor(deviceId: string): Promise<number | undefined> {
    await this.refreshGrants();
    return this.grants.get(deviceId);
  }

  /**
   * Record a device in the install ledger. Idempotent + atomically persisted.
   *
   * Fails CLOSED: if the write doesn't land (read-only/full/unmounted data dir)
   * the in-memory entry is rolled back and the error propagates, so claim()
   * returns a 5xx and the client falls back to its offline path (which banks NO
   * free hints) instead of silently re-granting after the next restart.
   */
  async markSeen(deviceId: string): Promise<void> {
    if (this.installs.has(deviceId)) return;
    if (this.installs.size >= HintGrantStore.MAX_INSTALLS) {
      if (!this.capWarned) {
        this.capWarned = true;
        this.logger.error(
          `Install ledger hit the ${HintGrantStore.MAX_INSTALLS} cap; no longer recording new ` +
            `devices (reinstall protection degraded). Migrate installs.json to a database.`,
        );
      }
      return;
    }
    this.installs.set(deviceId, new Date().toISOString());
    try {
      await this.enqueueWrite();
    } catch (e) {
      this.installs.delete(deviceId); // keep memory consistent with disk
      this.logger.error(`Failed to persist installs.json: ${(e as Error).message}`);
      throw e;
    }
  }

  /**
   * Serialize installs.json writes so concurrent claims can't corrupt the file.
   * The returned promise reflects THIS write's real outcome (may reject), while
   * the chain itself is kept alive so one failed write doesn't poison the next.
   */
  private enqueueWrite(): Promise<void> {
    const run = this.writeChain.then(() => this.writeInstalls());
    this.writeChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  private async writeInstalls(): Promise<void> {
    const tmp = `${this.installsPath}.tmp`;
    const json = JSON.stringify(Object.fromEntries(this.installs), null, 2);
    await fs.writeFile(tmp, json, 'utf8');
    await fs.rename(tmp, this.installsPath); // atomic on the same filesystem
  }

  private async readInstalls(): Promise<Map<string, string>> {
    let raw: string;
    try {
      raw = await fs.readFile(this.installsPath, 'utf8');
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'ENOENT') return new Map(); // first run — no ledger yet
      throw e; // an existing file we can't read → fail loud, don't re-grant everyone
    }
    try {
      const obj = JSON.parse(raw) as Record<string, string>;
      return new Map(Object.entries(obj));
    } catch (e) {
      // Corrupt ledger: refuse to boot rather than silently start empty (which
      // would re-grant the free hints to EVERY returning device). The atomic
      // temp+rename write means our own writes never produce this — so it's an
      // external cause the operator must resolve.
      throw new Error(
        `installs.json is corrupt (${(e as Error).message}). Refusing to start with an empty ` +
          `ledger. Fix or remove ${this.installsPath} (removing it intentionally resets the ` +
          `install ledger), then restart.`,
      );
    }
  }

  private async refreshGrants(): Promise<void> {
    try {
      const stat = await fs.stat(this.grantsPath);
      if (stat.mtimeMs === this.grantsMtimeMs) return; // unchanged since last read
      const raw = await fs.readFile(this.grantsPath, 'utf8');
      const obj = JSON.parse(raw) as Record<string, unknown>;
      const map = new Map<string, number>();
      for (const [id, value] of Object.entries(obj)) {
        if (!id || id.startsWith('_')) continue; // `_`-keys are comments
        const n = typeof value === 'number' ? value : Number(value);
        if (Number.isFinite(n) && n >= 0) map.set(id, Math.floor(n));
      }
      this.grants = map;
      this.grantsMtimeMs = stat.mtimeMs;
    } catch {
      // No grants.json (or invalid JSON) → empty allowlist. Reset mtime so a file
      // that appears later is picked up.
      this.grants = new Map();
      this.grantsMtimeMs = Number.NaN;
    }
  }
}
