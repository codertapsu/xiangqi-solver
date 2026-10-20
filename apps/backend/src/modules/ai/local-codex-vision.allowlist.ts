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
 * The gate is `<dataDir>/local-codex-vision-devices.json`, a hand-edited object
 * whose keys are exact device IDs and whose values are optional operator notes.
 * Keys beginning with `_` are comments. The file is re-read when its mtime
 * changes, so rollout changes need no backend restart.
 *
 * Membership alone authorizes the path, so the released app needs nothing new:
 * it already sends `x-device-id`. The trade-off is that a device ID is not a
 * secret (it travels in a header, and Settings can show it when the remote
 * `ui.deviceId` flag is on), so keep this list to your own devices.
 *
 * Fails closed: missing/unreadable/malformed data means "not allowed", and
 * callers continue through the normal cloud provider.
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

  /** Whether an exact, valid device ID is currently allowlisted. */
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
