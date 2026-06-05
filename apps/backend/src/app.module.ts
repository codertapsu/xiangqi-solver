import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { configuration, AppConfig } from './config/configuration';
import { validateEnv } from './config/env.validation';
import { HealthModule } from './modules/health/health.module';
import { AnalysisModule } from './modules/analysis/analysis.module';
import { AiModule } from './modules/ai/ai.module';
import { BoardModule } from './modules/board/board.module';
import { EngineModule } from './modules/engine/engine.module';
import { StorageModule } from './modules/storage/storage.module';

/**
 * Root module. Loads + validates config globally, configures rate limiting,
 * and wires feature modules. The ThrottlerGuard is applied app-wide.
 */
@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      load: [configuration],
      validate: validateEnv,
    }),
    ThrottlerModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const rl = config.get<AppConfig['rateLimit']>('app.rateLimit');
        return {
          throttlers: [
            {
              ttl: (rl?.ttlSeconds ?? 60) * 1000,
              limit: rl?.limit ?? 30,
            },
          ],
        };
      },
    }),
    HealthModule,
    AnalysisModule,
    AiModule,
    BoardModule,
    EngineModule,
    StorageModule,
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
