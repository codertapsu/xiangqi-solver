import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';

/** Health/liveness module. */
@Module({
  controllers: [HealthController],
})
export class HealthModule {}
