import { timingSafeEqual } from 'node:crypto';
import { promises as fs } from 'node:fs';
import * as path from 'node:path';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';

const FILE_NAME = 'local-codex-vision-devices.json';
const MIN_DEVICE_ID_LENGTH = 8;
const MAX_DEVICE_ID_LENGTH = 256;

/**
 * Runtime gate for routing selected devices through a local vision bridge.
 *
 * Authorization has TWO factors, mirroring [AdminService]:
 *
 *  - IDENTITY — `<dataDir>/local-codex-vision-devices.json`, a hand-edited
 *    object whose keys are exact device IDs and whose values are optional
 *    operator notes. Keys beginning with `_` are comments. The file is re-read
 *    when its mtime changes, so rollout changes need no backend restart.
 *  - AUTHORIZATION — `LOCAL_VISION_ROLLOUT_TOKEN`, presented as the
 *    `x-local-vision-token` header and compared in constant time.
 *
 * The device ID alone cannot authorize this path. It is a PUBLIC identifier:
 * the app renders a "Device ID" tile in Settings whose documented purpose is
 * for users to share it with the operator to receive hint grants. Anyone who
 * saw a tester's ID could otherwise send arbitrary images to the operator's own
 * machine on the operator's personal subscription, holding a socket open for
 * the bridge's whole (multi-minute) deadline — and the response's
 * `vision.provider` would confirm each guess.
 *
 * Fails closed everywhere: missing/unreadable/malformed data, an unset token,
 * or a mismatched token all mean "not allowed", and callers continue through
 * the normal cloud provider.
 */
@Injectable()
export class LocalCodexVisionAllowlist {
  private deviceIds = new Set<string>();
  private mtimeMs = Number.NaN;

  constructor(private readonly config: ConfigService) {}

  private get filePath(): string {
    const dataDir = this.config.get<AppConfig['hints']>('app.hints')?.dataDir ?? './data';
    return path.join(dataDir, FILE_NAME);
  }

  private get rolloutToken(): string {
    // Trimmed on BOTH sides of the compare: the presented header is trimmed by
    // the controller, so a configured value with stray whitespace (an easy .env
    // typo) would otherwise be a token that can never match anything.
    return (this.config.get<AppConfig['ai']>('app.ai')?.localVisionRolloutToken ?? '').trim();
  }

  /**
   * Full authorization for the local-bridge path: a valid rollout token AND an
   * allowlisted device. The token is checked first — it is an in-memory compare,
   * so an unauthorized caller never reaches the allowlist file at all.
   */
  async authorize(deviceId: string | undefined, token: string | undefined): Promise<boolean> {
    return this.verifyRolloutToken(token) && (await this.isAllowlisted(deviceId));
  }

  /**
   * Constant-time check of the presented rollout token against
   * LOCAL_VISION_ROLLOUT_TOKEN. False when no token is configured — the
   * local-bridge path is then DISABLED, exactly like an unset ADMIN_SECRET
   * disables admin writes.
   */
  verifyRolloutToken(token: string | undefined): boolean {
    const expected = this.rolloutToken;
    if (!expected) return false;
    const a = Buffer.from(token ?? '', 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  }

  /** Whether an exact, valid device ID is currently allowlisted (identity only). */
  async isAllowlisted(deviceId?: string): Promise<boolean> {
    if (!this.isValidDeviceId(deviceId)) return false;
    await this.refresh();
    return this.deviceIds.has(deviceId);
  }

  private isValidDeviceId(deviceId: string | undefined): deviceId is string {
    return (
      typeof deviceId === 'string' &&
      deviceId.length >= MIN_DEVICE_ID_LENGTH &&
      deviceId.length <= MAX_DEVICE_ID_LENGTH
    );
  }

  private async refresh(): Promise<void> {
    try {
      const stat = await fs.stat(this.filePath);
      if (stat.mtimeMs === this.mtimeMs) return;

      const parsed: unknown = JSON.parse(await fs.readFile(this.filePath, 'utf8'));
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        throw new TypeError(`${FILE_NAME} must contain a JSON object.`);
      }

      const next = new Set<string>();
      for (const id of Object.keys(parsed)) {
        if (!id.startsWith('_') && this.isValidDeviceId(id)) next.add(id);
      }
      this.deviceIds = next;
      this.mtimeMs = stat.mtimeMs;
    } catch {
      this.deviceIds = new Set();
      // Retry on the next request so a repaired or newly created file is seen.
      this.mtimeMs = Number.NaN;
    }
  }
}
