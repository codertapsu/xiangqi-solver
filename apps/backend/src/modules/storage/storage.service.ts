import { randomUUID } from 'node:crypto';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Injectable, Logger } from '@nestjs/common';

/**
 * Handles uploaded image buffers WITHOUT persisting them by default.
 *
 * Privacy guarantees:
 *  - Screenshots are kept in memory and never written to disk unless a caller
 *    explicitly requests a temp path (e.g. for a tool that needs a file).
 *  - Any temp file written is deleted immediately after use.
 *  - Raw image bytes are NEVER logged (only sizes / mime types).
 */
@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);

  /**
   * Run a callback that needs a temp file path for the given buffer, then
   * guarantee the temp file (and its directory) are removed afterward.
   * Use only when a downstream tool truly requires a filesystem path.
   */
  async withTempFile<T>(
    buffer: Buffer,
    extension: string,
    fn: (path: string) => Promise<T>,
  ): Promise<T> {
    const dir = await mkdtemp(join(tmpdir(), 'xiangqi-'));
    const safeExt = extension.replace(/[^a-z0-9]/gi, '').slice(0, 8) || 'bin';
    const filePath = join(dir, `${randomUUID()}.${safeExt}`);
    try {
      await writeFile(filePath, buffer, { mode: 0o600 });
      this.logger.debug(`Wrote temp upload (${buffer.byteLength} bytes) to a temp file.`);
      return await fn(filePath);
    } finally {
      await rm(dir, { recursive: true, force: true }).catch((err) =>
        this.logger.warn(`Failed to clean up temp dir: ${(err as Error).message}`),
      );
    }
  }
}
