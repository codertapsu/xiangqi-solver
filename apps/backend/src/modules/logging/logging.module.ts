import { Global, Module } from '@nestjs/common';
import { ErrorLogService } from './error-log.service';

/**
 * Global logging module: provides the date-grouped {@link ErrorLogService} to
 * the whole app (the exception filter + providers) without per-module imports.
 */
@Global()
@Module({
  providers: [ErrorLogService],
  exports: [ErrorLogService],
})
export class LoggingModule {}
