import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';
import { HintGrantStore } from './hint-grant.store';

/** Why a device received the balance it did (useful for support/logging). */
export type GrantSource = 'grant' | 'first_install' | 'returning';

export interface ClaimResult {
  /** Starting hint balance for this device on (re)install. */
  hints: number;
  source: GrantSource;
}

/**
 * Decides the starting hint balance for a device on (re)install, so the
 * device-local wallet can't be reset to the free 10 by uninstalling.
 *
 * Priority (highest first):
 *   1. `grant`         — device is in the manual Hint Grants allowlist → its
 *                        configured amount, on EVERY (re)install while listed.
 *   2. `returning`     — device already in the install ledger → 0 (no re-grant).
 *   3. `first_install` — brand-new device → the configured free-on-install count.
 */
@Injectable()
export class HintGrantService {
  constructor(
    private readonly store: HintGrantStore,
    private readonly config: ConfigService,
  ) {}

  async claim(deviceId: string): Promise<ClaimResult> {
    const granted = await this.store.grantFor(deviceId);
    if (granted !== undefined) {
      // Whitelist wins, even for a returning device — record it so removing the
      // grant later falls through to `returning` (0), not another free grant.
      await this.store.markSeen(deviceId);
      return { hints: granted, source: 'grant' };
    }
    if (this.store.hasSeen(deviceId)) {
      return { hints: 0, source: 'returning' };
    }
    await this.store.markSeen(deviceId);
    return { hints: this.freeOnInstall, source: 'first_install' };
  }

  private get freeOnInstall(): number {
    return this.config.get<AppConfig['features']>('app.features')?.hints.freeOnInstall ?? 10;
  }
}
