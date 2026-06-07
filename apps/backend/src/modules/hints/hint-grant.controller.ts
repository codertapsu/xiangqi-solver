import { BadRequestException, Controller, Headers, Post, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { DeviceRateLimitGuard } from '../../common/guards/device-rate-limit.guard';
import { ClaimResult, HintGrantService } from './hint-grant.service';

/**
 * Install-grant endpoint. The app calls it ONCE on first launch (before seeding
 * its device-local wallet) to learn how many hints this install starts with.
 *
 * Returned under the standard `{ success, data }` envelope. Keyed by the stable
 * `x-device-id` header (the same id the per-device rate limit uses), so a
 * reinstall on the same device is recognized and doesn't re-grant the free hints
 * — unless the device is in the manual "Hint Grants" allowlist.
 *
 * Guarded by [DeviceRateLimitGuard] (per-device cap) on top of the global per-IP
 * throttler, so one device/IP can't hammer claim to bloat the install ledger.
 */
@ApiTags('hints')
@Controller('hints')
@UseGuards(DeviceRateLimitGuard)
export class HintGrantController {
  constructor(private readonly grants: HintGrantService) {}

  @Post('claim')
  claim(@Headers('x-device-id') deviceId?: string): Promise<ClaimResult> {
    const id = (deviceId ?? '').trim();
    if (id.length < 8 || id.length > 256) {
      throw new BadRequestException({
        message: 'A valid x-device-id header (8–256 chars) is required.',
        code: 'INVALID_DEVICE_ID',
      });
    }
    return this.grants.claim(id);
  }
}
