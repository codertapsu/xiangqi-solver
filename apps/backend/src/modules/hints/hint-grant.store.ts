import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { promises as fs } from 'fs';
import * as path from 'path';
import { AppConfig } from '../../config/configuration';

/** One append-only ledger record: an upsert (`t`) or a tombstone (`d`). */
interface LedgerLine {
  /** deviceId */
  i: string;
  /** firstSeen ISO (upsert) */
  t?: string;
  /** tombstone (removal) */
  d?: 1;
}

/**
 * Tiny JSON-file store backing the install-grant flow. Two files live in the
 * configured data dir (HINTS_DATA_DIR, default ./data — gitignored):
 *
 *  - `installs.log` — the INSTALL LEDGER: device ids we have already granted the
 *    free starter hints to, so reinstalling doesn't re-grant them. APPEND-ONLY
 *    NDJSON (one `LedgerLine` per row): recording a new device is a single small
 *    `appendFile`, NOT a rewrite of the whole ledger — so the hot path never
 *    builds a multi-MB JSON string on the event loop as the ledger grows.
 *    Replayed on boot (last-write-wins; tombstones remove); compacted rarely to
 *    reclaim churn. A legacy object-format `installs.json` is migrated on first
 *    boot. Reads are in-memory.
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
  /** Physical lines currently in installs.log — the compaction trigger. */
  private physicalLines = 0;
  private writeChain: Promise<void> = Promise.resolve(); // serialize installs writes
  private grantsWriteChain: Promise<void> = Promise.resolve(); // serialize grants writes
  private capWarned = false;

  /**
   * Hard cap on ledger size so it can't grow without bound under random-device-id
   * spam. Reaching it needs sustained abuse past the per-IP throttler; at that
   * point the JSON store has been outgrown and should move to a DB. Beyond the
   * cap we stop recording (and log once) — availability over strict anti-abuse.
   */
  private static readonly MAX_INSTALLS = 1_000_000;

  constructor(private readonly config: ConfigService) {}

  async onModuleInit(): Promise<void> {
    this.dir = this.config.get<AppConfig['hints']>('app.hints')?.dataDir ?? './data';
    await fs.mkdir(this.dir, { recursive: true });
    this.installs = await this.loadInstalls();
    await this.refreshGrants();
    this.logger.log(
      `Hint-grant store ready (dir=${this.dir}, installs=${this.installs.size}, grants=${this.grants.size}).`,
    );
  }

  private get installsLogPath(): string {
    return path.join(this.dir, 'installs.log');
  }

  /** Legacy object-format ledger, migrated to installs.log on first boot. */
  private get legacyInstallsPath(): string {
    return path.join(this.dir, 'installs.json');
  }

  private get grantsPath(): string {
    return path.join(this.dir, 'grants.json');
  }

  /** Await all queued install writes (tests / graceful shutdown). */
  flush(): Promise<void> {
    return this.writeChain;
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
   * Record a device in the install ledger. Idempotent + atomically persisted as
   * a single appended line.
   *
   * Fails CLOSED: if the append doesn't land (read-only/full/unmounted data dir)
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
            `devices (reinstall protection degraded). Migrate the ledger to a database.`,
        );
      }
      return;
    }
    const iso = new Date().toISOString();
    this.installs.set(deviceId, iso);
    try {
      await this.append({ i: deviceId, t: iso });
    } catch (e) {
      this.installs.delete(deviceId); // keep memory consistent with disk
      this.logger.error(`Failed to persist install ledger: ${(e as Error).message}`);
      throw e;
    }
    this.maybeCompact();
  }

  /**
   * Append one ledger line. Serialized so concurrent writes can't interleave;
   * the returned promise reflects THIS write's real outcome (may reject), while
   * the chain itself is kept alive so one failed write doesn't poison the next.
   * Append (O_APPEND) is atomic per line on a POSIX filesystem.
   */
  private append(line: LedgerLine): Promise<void> {
    const run = this.writeChain.then(async () => {
      await fs.appendFile(this.installsLogPath, `${JSON.stringify(line)}\n`, 'utf8');
      this.physicalLines += 1;
    });
    this.writeChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  /**
   * Rewrite installs.log compactly (one live line per device) when churn
   * (re-sets / tombstones) has bloated it. Atomic temp+rename; serialized.
   * Rare and amortized — the per-record hot path stays a single append.
   */
  private maybeCompact(): void {
    if (this.physicalLines <= Math.max(2 * this.installs.size, 1000)) return;
    void this.compact();
  }

  private compact(): Promise<void> {
    const run = this.writeChain.then(async () => {
      await fs.mkdir(this.dir, { recursive: true });
      // Synchronous snapshot of the live map — atomic w.r.t. concurrent writes
      // (which are serialized behind this on the same chain).
      const body = [...this.installs]
        .map(([id, ts]) => JSON.stringify({ i: id, t: ts } satisfies LedgerLine))
        .join('\n');
      const tmp = `${this.installsLogPath}.tmp`;
      await fs.writeFile(tmp, body.length ? `${body}\n` : '', 'utf8');
      await fs.rename(tmp, this.installsLogPath); // atomic on the same filesystem
      this.physicalLines = this.installs.size;
    });
    this.writeChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  /**
   * Boot order: replay installs.log; if it has entries, use it. Otherwise (no
   * log, or an EMPTY log — e.g. an interrupted first migration) fall through to
   * a legacy installs.json migration. This avoids an empty log SHADOWING real
   * legacy records (which would re-grant everyone).
   */
  private async loadInstalls(): Promise<Map<string, string>> {
    const fromLog = await this.replayLog(); // throws on whole-file corruption
    if (fromLog && fromLog.size > 0) return fromLog;
    const migrated = await this.migrateLegacy();
    if (migrated.size > 0) return migrated;
    return fromLog ?? migrated; // both empty (first run, or all-removed)
  }

  /** Replay the append-only log into a map (last-write-wins; tombstones remove). */
  private async replayLog(): Promise<Map<string, string> | null> {
    let raw: string;
    try {
      raw = await fs.readFile(this.installsLogPath, 'utf8');
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'ENOENT') return null; // no log yet
      throw e;
    }
    const map = new Map<string, string>();
    let lines = 0;
    let bad = 0;
    for (const raw_line of raw.split('\n')) {
      const text = raw_line.trim();
      if (!text) continue;
      lines += 1;
      try {
        const entry = JSON.parse(text) as LedgerLine;
        if (!entry || typeof entry.i !== 'string' || !entry.i) {
          bad += 1;
          continue;
        }
        if (entry.d === 1) map.delete(entry.i);
        else if (typeof entry.t === 'string') map.set(entry.i, entry.t);
        else bad += 1;
      } catch {
        // A truncated last line (crash mid-append) is the EXPECTED bad case: we
        // lose at most that one record (the device just re-claims once). Tracked
        // and bounded by the whole-file-corruption guard below.
        bad += 1;
      }
    }
    this.physicalLines = lines;
    // Whole-file corruption guard (parity with the legacy fail-loud path): if
    // the file had lines but EVERY one was unreadable (map empty), the ledger is
    // garbled — refuse to boot rather than silently start empty and re-grant the
    // free hints to the entire installed base. A few bad lines among good ones
    // (the truncated-tail case) is tolerated.
    if (lines > 0 && map.size === 0 && bad > 0) {
      throw new Error(
        `installs.log is corrupt: all ${lines} record(s) were unreadable. Refusing to start ` +
          `with an empty ledger (which would re-grant free hints to every returning device). ` +
          `Inspect or remove ${this.installsLogPath} (removing it intentionally resets the ` +
          `install ledger), then restart.`,
      );
    }
    if (bad > 0) {
      this.logger.warn(`Ignored ${bad} unreadable line(s) while replaying installs.log.`);
    }
    return map;
  }

  /** Read a legacy `{ deviceId: iso }` ledger and write it as installs.log once. */
  private async migrateLegacy(): Promise<Map<string, string>> {
    let raw: string;
    try {
      raw = await fs.readFile(this.legacyInstallsPath, 'utf8');
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === 'ENOENT') {
        this.physicalLines = 0;
        return new Map(); // first run — no ledger at all
      }
      throw e; // an existing file we can't read → fail loud, don't re-grant everyone
    }
    let map: Map<string, string>;
    try {
      const obj = JSON.parse(raw) as Record<string, string>;
      map = new Map(Object.entries(obj));
    } catch (e) {
      // Corrupt legacy ledger: refuse to boot rather than silently start empty
      // (which would re-grant the free hints to EVERY returning device).
      throw new Error(
        `installs.json is corrupt (${(e as Error).message}). Refusing to start with an empty ` +
          `ledger. Fix or remove ${this.legacyInstallsPath} (removing it intentionally resets the ` +
          `install ledger), then restart.`,
      );
    }
    this.installs = map;
    await this.compact(); // write installs.log from the migrated map
    // Retire the legacy file so it can never SHADOW the log on a later boot
    // (e.g. an empty log + a lingering installs.json). Best-effort.
    await fs.rename(this.legacyInstallsPath, `${this.legacyInstallsPath}.migrated`).catch(() => {});
    this.logger.log(`Migrated ${map.size} install(s) from installs.json to installs.log.`);
    return map;
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

  // --- Admin CRUD over grants.json / installs.log --------------------------

  /** All manual grants `{ deviceId: hints }` (refreshes from disk first). */
  async allGrants(): Promise<Record<string, number>> {
    await this.refreshGrants();
    return Object.fromEntries(this.grants);
  }

  /** Add/replace a device's manual grant (atomic, serialized). */
  async setGrant(deviceId: string, hints: number): Promise<void> {
    await this.refreshGrants();
    this.grants.set(deviceId, Math.max(0, Math.floor(hints)));
    await this.writeGrants();
  }

  /** Remove a device's manual grant (atomic; no-op if absent). */
  async removeGrant(deviceId: string): Promise<void> {
    await this.refreshGrants();
    if (this.grants.delete(deviceId)) await this.writeGrants();
  }

  /** Serialize grants.json writes; atomic temp+rename; refresh the mtime cache. */
  private writeGrants(): Promise<void> {
    const run = this.grantsWriteChain.then(async () => {
      await fs.mkdir(this.dir, { recursive: true });
      const tmp = `${this.grantsPath}.tmp`;
      const json = JSON.stringify(Object.fromEntries(this.grants), null, 2);
      await fs.writeFile(tmp, json, 'utf8');
      await fs.rename(tmp, this.grantsPath);
      this.grantsMtimeMs = (await fs.stat(this.grantsPath)).mtimeMs;
    });
    this.grantsWriteChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }

  /** The full install ledger `{ deviceId: firstSeen ISO }`. */
  allInstalls(): Record<string, string> {
    return Object.fromEntries(this.installs);
  }

  /** Add/replace an install ledger entry (appended). Invalid/missing date → now. */
  async setInstall(deviceId: string, firstSeenIso?: string): Promise<void> {
    const iso =
      firstSeenIso && !Number.isNaN(Date.parse(firstSeenIso))
        ? new Date(firstSeenIso).toISOString()
        : new Date().toISOString();
    this.installs.set(deviceId, iso);
    await this.append({ i: deviceId, t: iso });
    this.maybeCompact();
  }

  /** Remove an install ledger entry (appends a tombstone; no-op if absent). */
  async removeInstall(deviceId: string): Promise<void> {
    if (!this.installs.delete(deviceId)) return;
    await this.append({ i: deviceId, d: 1 });
    this.maybeCompact();
  }
}
