import { Module } from '@nestjs/common';
import { HintsModule } from '../hints/hints.module';
import { AdminController } from './admin.controller';
import { AdminGuard } from './admin.guard';
import { AdminService } from './admin.service';
import { ConfigOverrideStore } from './config-override.store';

/**
 * Admin module: device-id + shared-secret protected management of remote config
 * (config-overrides.json), hint grants (grants.json), and the install ledger
 * (installs.json). Exports {@link ConfigOverrideStore} so RemoteConfigModule can
 * merge the override into the public GET /api/config, and {@link AdminService}
 * for reuse. Imports HintsModule for {@link HintGrantStore}.
 */
@Module({
  imports: [HintsModule],
  controllers: [AdminController],
  providers: [AdminService, AdminGuard, ConfigOverrideStore],
  exports: [ConfigOverrideStore, AdminService],
})
export class AdminModule {}
