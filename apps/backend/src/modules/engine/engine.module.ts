import { Module } from '@nestjs/common';
import { EngineService } from './engine.service';
import { MockEngineService } from './mock-engine.service';
import { PikafishEngineService } from './pikafish-engine.service';

/**
 * Engine module: exposes the EngineService facade and both concrete engine
 * implementations (mock + Pikafish). The facade selects per-request.
 */
@Module({
  providers: [EngineService, MockEngineService, PikafishEngineService],
  exports: [EngineService],
})
export class EngineModule {}
