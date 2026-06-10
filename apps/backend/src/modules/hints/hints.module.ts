import { Module } from '@nestjs/common';
import { DeviceRateLimitGuard } from '../../common/guards/device-rate-limit.guard';
import { HintGrantController } from './hint-grant.controller';
import { HintGrantService } from './hint-grant.service';
import { HintGrantStore } from './hint-grant.store';

/**
 * Hints module: the install-grant flow (`POST /api/hints/claim`) that stops the
 * device-local wallet from being reset to the free starter hints by reinstalling,
 * plus the manual "Hint Grants" allowlist. Backed by simple JSON files.
 */
@Module({
  controllers: [HintGrantController],
  providers: [HintGrantService, HintGrantStore, DeviceRateLimitGuard],
  exports: [HintGrantStore],
})
export class HintsModule {}
