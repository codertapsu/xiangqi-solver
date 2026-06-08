import { Module } from '@nestjs/common';
import { EngineNetController } from './engine-net.controller';
import { EngineService } from './engine.service';
import { MockEngineService } from './mock-engine.service';
import { PikafishEngineService } from './pikafish-engine.service';

/**
 * Engine module: exposes the EngineService facade and both concrete engine
 * implementations (mock + Pikafish). The facade selects per-request. Also serves
 * the on-device NNUE net (GET /api/engine/net) so the app downloads it from us.
 */
@Module({
  controllers: [EngineNetController],
  providers: [EngineService, MockEngineService, PikafishEngineService],
  exports: [EngineService],
})
export class EngineModule {}
