import { appendFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppConfig } from '../../config/configuration';

/** Which kind of failure an entry records (for grep/filtering within a day's file). */
export type ErrorLogCategory = 'request' | 'openai' | 'vision-invalid';

export interface ErrorLogFields {
  /** Short human-readable summary. */
  message: string;
  /** Anything else useful — MUST NOT contain secrets or raw image bytes. */
  [key: string]: unknown;
}

/**
 * Best-effort, append-only error/failure log, grouped by DATE.
 *
 * Writes one JSON line per event to `<LOGS_DIR>/<YYYY-MM-DD>.log` (UTC date),
 * each carrying a full ISO `ts` and a `category`. Used by:
 *  - the global exception filter — every failed request, and
 *  - the OpenAI provider — request failures + unparseable ("can't extract the
 *    screenshot") responses, with diagnostic detail.
 *
 * Guarantees: it NEVER throws into the request path (a logging failure is
 * swallowed and surfaced to the console only), and callers MUST NOT pass secrets
 * (API keys) or raw image bytes.
 */
@Injectable()
export class ErrorLogService {
  private readonly logger = new Logger(ErrorLogService.name);
  private readonly dir: string;
  private ensured = false;
  /** Tail of the serialized write chain, so callers/tests/shutdown can await it. */
  private writeChain: Promise<void> = Promise.resolve();

  constructor(config: ConfigService) {
    this.dir = config.get<AppConfig['logging']>('app.logging')?.dir ?? './logs';
  }

  /** Append a structured entry to today's log file. Fire-and-forget. */
  log(category: ErrorLogCategory, fields: ErrorLogFields): void {
    const now = new Date();
    const line = `${JSON.stringify({ ts: now.toISOString(), category, ...fields })}\n`;
    const file = join(this.dir, `${now.toISOString().slice(0, 10)}.log`);
    // Serialize writes so lines land in call order and the first-write mkdir
    // isn't raced by a concurrent write. `append` never rejects (it swallows),
    // so the chain stays alive.
    this.writeChain = this.writeChain.then(() => this.append(file, line));
  }

  /** Await all queued writes (tests / graceful shutdown). */
  flush(): Promise<void> {
    return this.writeChain;
  }

  private async append(file: string, line: string): Promise<void> {
    try {
      if (!this.ensured) {
        await mkdir(this.dir, { recursive: true });
        this.ensured = true;
      }
      // 'a' flag → O_APPEND: concurrent small line writes don't interleave.
      await appendFile(file, line, 'utf8');
    } catch (err) {
      this.logger.warn(`Could not write error log: ${(err as Error).message}`);
    }
  }
}
