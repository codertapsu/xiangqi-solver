import { Module } from '@nestjs/common';
import { AdminModule } from '../admin/admin.module';
import { RemoteConfigController } from './remote-config.controller';

// Imports AdminModule for ConfigOverrideStore so GET /api/config serves the
// admin override (config-overrides.json) when present, else the env defaults.
@Module({ imports: [AdminModule], controllers: [RemoteConfigController] })
export class RemoteConfigModule {}
