import { Module } from '@nestjs/common';
import { StorageService } from './storage.service';

/**
 * Storage module: privacy-preserving handling of uploaded image buffers.
 * Never persists screenshots by default.
 */
@Module({
  providers: [StorageService],
  exports: [StorageService],
})
export class StorageModule {}
