import { Module } from '@nestjs/common';
import { MulterModule } from '@nestjs/platform-express';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { memoryStorage } from 'multer';
import { AppConfig } from '../../config/configuration';
import { AiModule } from '../ai/ai.module';
import { BoardModule } from '../board/board.module';
import { EngineModule } from '../engine/engine.module';
import { StorageModule } from '../storage/storage.module';
import { AnalysisController } from './analysis.controller';
import { AnalysisService } from './analysis.service';

/**
 * Analysis module: wires vision + board + engine into the orchestration
 * service and exposes the two HTTP endpoints. Uploads use in-memory storage
 * (never written to disk) with a hard size limit from config.
 */
@Module({
  imports: [
    AiModule,
    BoardModule,
    EngineModule,
    StorageModule,
    MulterModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        storage: memoryStorage(),
        limits: {
          fileSize: config.get<AppConfig['upload']>('app.upload')?.maxBytes ?? 8_388_608,
          files: 1,
        },
      }),
    }),
  ],
  controllers: [AnalysisController],
  providers: [AnalysisService],
})
export class AnalysisModule {}
