import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Put,
  UseGuards,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { AppConfig } from '../../config/configuration';
import { HintGrantStore } from '../hints/hint-grant.store';
import { AdminGuard } from './admin.guard';
import { AdminService } from './admin.service';
import { ConfigOverrideStore } from './config-override.store';
import { Features, featuresSchema } from './features.schema';

/**
 * Admin API. All routes are under `/api/admin`. Every route EXCEPT `status`
 * requires an admin device (`x-device-id` ∈ admins.json) AND the shared secret
 * (`x-admin-secret`) — see {@link AdminGuard}. Throttle is skipped: `status` is
 * hit once per launch, the rest are low-volume internal calls.
 *
 * Config edits persist to config-overrides.json and take effect for users on
 * their next app launch (the app re-fetches GET /api/config). Grants/installs
 * edits go straight to grants.json / installs.json via {@link HintGrantStore}.
 */
@ApiTags('admin')
@SkipThrottle()
@Controller('admin')
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly overrides: ConfigOverrideStore,
    private readonly store: HintGrantStore,
    private readonly config: ConfigService,
  ) {}

  private envFeatures(): Features {
    return this.config.get<AppConfig['features']>('app.features')! as Features;
  }

  private validId(id: unknown): string {
    const s = (typeof id === 'string' ? id : '').trim();
    if (s.length < 8 || s.length > 256) {
      throw new BadRequestException({
        message: 'A valid deviceId (8–256 chars) is required.',
        code: 'INVALID_DEVICE_ID',
      });
    }
    return s;
  }

  /** Identity probe (no secret): tells the app whether to show the admin UI. */
  @Get('status')
  async status(@Headers('x-device-id') deviceId?: string): Promise<{ isAdmin: boolean }> {
    return { isAdmin: await this.admin.isAdmin((deviceId ?? '').trim()) };
  }

  // --- Remote config -------------------------------------------------------

  /** The effective remote config (override if set, else env) + whether overridden. */
  @UseGuards(AdminGuard)
  @Get('config')
  async getConfig(): Promise<{ features: Features; overridden: boolean }> {
    return {
      features: await this.overrides.effective(this.envFeatures()),
      overridden: await this.overrides.isActive(),
    };
  }

  /** Replace the remote config with a validated override. */
  @UseGuards(AdminGuard)
  @Put('config')
  async setConfig(@Body() body: unknown): Promise<{ features: Features; overridden: boolean }> {
    const parsed = featuresSchema.safeParse(body);
    if (!parsed.success) {
      throw new BadRequestException({
        message: 'Invalid config payload.',
        code: 'INVALID_CONFIG',
        details: parsed.error.issues.map((i) => `${i.path.join('.') || '(root)'}: ${i.message}`),
      });
    }
    await this.overrides.set(parsed.data);
    return { features: parsed.data, overridden: true };
  }

  /** Reset to env defaults (delete the override). */
  @UseGuards(AdminGuard)
  @Delete('config')
  async resetConfig(): Promise<{ features: Features; overridden: boolean }> {
    await this.overrides.clear();
    return { features: this.envFeatures(), overridden: false };
  }

  // --- Hint grants (grants.json) -------------------------------------------

  @UseGuards(AdminGuard)
  @Get('grants')
  grants(): Promise<Record<string, number>> {
    return this.store.allGrants();
  }

  @UseGuards(AdminGuard)
  @Put('grants')
  async upsertGrant(
    @Body() body: { deviceId?: string; hints?: number },
  ): Promise<{ deviceId: string; hints: number }> {
    const id = this.validId(body.deviceId);
    const hints = Number(body.hints);
    if (!Number.isFinite(hints) || hints < 0) {
      throw new BadRequestException({
        message: 'hints must be a number >= 0.',
        code: 'INVALID_GRANT',
      });
    }
    const value = Math.floor(hints);
    await this.store.setGrant(id, value);
    return { deviceId: id, hints: value };
  }

  @UseGuards(AdminGuard)
  @Delete('grants')
  async removeGrant(@Body() body: { deviceId?: string }): Promise<{ removed: string }> {
    const id = this.validId(body.deviceId);
    await this.store.removeGrant(id);
    return { removed: id };
  }

  // --- Install ledger (installs.json) --------------------------------------

  @UseGuards(AdminGuard)
  @Get('installs')
  installs(): Record<string, string> {
    return this.store.allInstalls();
  }

  @UseGuards(AdminGuard)
  @Put('installs')
  async upsertInstall(
    @Body() body: { deviceId?: string; firstSeen?: string },
  ): Promise<{ deviceId: string; firstSeen: string }> {
    const id = this.validId(body.deviceId);
    await this.store.setInstall(id, body.firstSeen);
    return { deviceId: id, firstSeen: this.store.allInstalls()[id] };
  }

  @UseGuards(AdminGuard)
  @Delete('installs')
  async removeInstall(@Body() body: { deviceId?: string }): Promise<{ removed: string }> {
    const id = this.validId(body.deviceId);
    await this.store.removeInstall(id);
    return { removed: id };
  }
}
