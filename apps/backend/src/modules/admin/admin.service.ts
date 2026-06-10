import { timingSafeEqual } from 'node:crypto';
import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';

/**
 * Admin identity + authorization, backed by `<dataDir>/admins.json`.
 *
 * `admins.json` is a hand-edited allowlist: `{ "<deviceId>": "<note>" }`
 * (keys starting with `_` are comments). A device is an ADMIN if its
 * `x-device-id` is a key here. Re-read on change (mtime-cached), like grants.json,
 * so adding an admin needs no restart.
 *
 * Identity (who may SEE the admin UI) is device-id only. AUTHORIZATION for any
 * mutation additionally requires the shared `ADMIN_SECRET` (presented as the
 * `x-admin-secret` header) — the backend is plain HTTP, so the device id alone
 * (cleartext, also shown in Settings) is not a sufficient gate for writes.
 */
@Injectable()
export class AdminService {
  private readonly logger = new Logger(AdminService.name);
  private admins = new Set<string>();
  private mtimeMs = Number.NaN;

  constructor(private readonly config: ConfigService) {}

  private get dir(): string {
    return this.config.get<AppConfig['hints']>('app.hints')?.dataDir ?? './data';
  }

  private get adminsPath(): string {
    return path.join(this.dir, 'admins.json');
  }

  private get secret(): string {
    return this.config.get<AppConfig['admin']>('app.admin')?.secret ?? '';
  }

  /** Re-read admins.json when it changes (mtime-cached). Missing/invalid → empty. */
  private async refresh(): Promise<void> {
    try {
      const stat = await fs.stat(this.adminsPath);
      if (stat.mtimeMs === this.mtimeMs) return;
      const raw = await fs.readFile(this.adminsPath, 'utf8');
      const obj = JSON.parse(raw) as Record<string, unknown>;
      const set = new Set<string>();
      for (const id of Object.keys(obj)) {
        if (id && !id.startsWith('_')) set.add(id); // `_`-keys are comments
      }
      this.admins = set;
      this.mtimeMs = stat.mtimeMs;
    } catch {
      this.admins = new Set();
      this.mtimeMs = Number.NaN;
    }
  }

  /** Whether this device is listed as an admin (identity only — no secret). */
  async isAdmin(deviceId: string): Promise<boolean> {
    if (!deviceId) return false;
    await this.refresh();
    return this.admins.has(deviceId);
  }

  /**
   * Constant-time check of the presented secret against ADMIN_SECRET. Returns
   * false when no secret is configured (admin write API is then DISABLED).
   */
  verifySecret(secret: string | undefined): boolean {
    const expected = this.secret;
    if (!expected) return false;
    const a = Buffer.from(secret ?? '', 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  }

  /** Full authorization for a mutation: admin device AND a valid secret. */
  async authorize(deviceId: string, secret: string | undefined): Promise<boolean> {
    return (await this.isAdmin(deviceId)) && this.verifySecret(secret);
  }
}
