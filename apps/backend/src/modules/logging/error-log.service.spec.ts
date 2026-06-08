import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConfigService } from '@nestjs/config';
import { ErrorLogService } from './error-log.service';

/** ConfigService stub that returns the given logs dir for `app.logging`. */
function configWithDir(dir: string): ConfigService {
  return {
    get: (key: string) => (key === 'app.logging' ? { dir } : undefined),
  } as unknown as ConfigService;
}

function todayFile(dir: string): string {
  return join(dir, `${new Date().toISOString().slice(0, 10)}.log`);
}

describe('ErrorLogService', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'xiangqi-logs-'));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('appends a JSON line to <date>.log with ts + category + fields', async () => {
    const service = new ErrorLogService(configWithDir(dir));

    service.log('openai', { message: 'OpenAI request failed', model: 'gpt-5.4', status: 503 });
    await service.flush();

    const content = await readFile(todayFile(dir), 'utf8');
    expect(content.endsWith('\n')).toBe(true);

    const entry = JSON.parse(content.trim()) as Record<string, unknown>;
    expect(entry.category).toBe('openai');
    expect(entry.message).toBe('OpenAI request failed');
    expect(entry.model).toBe('gpt-5.4');
    expect(entry.status).toBe(503);
    // ts is a valid ISO timestamp.
    expect(typeof entry.ts).toBe('string');
    expect(Number.isNaN(Date.parse(entry.ts as string))).toBe(false);
  });

  it('writes one line per event (newline-delimited JSON, grouped in one file)', async () => {
    const service = new ErrorLogService(configWithDir(dir));

    service.log('request', { message: 'a', status: 500 });
    service.log('vision-invalid', { message: 'b', model: 'gpt-5.4' });
    await service.flush();

    const lines = (await readFile(todayFile(dir), 'utf8')).trim().split('\n');
    expect(lines).toHaveLength(2);
    expect((JSON.parse(lines[0]) as { category: string }).category).toBe('request');
    expect((JSON.parse(lines[1]) as { category: string }).category).toBe('vision-invalid');
  });

  it('creates the logs directory on first write', async () => {
    const nested = join(dir, 'deep', 'logs');
    const service = new ErrorLogService(configWithDir(nested));

    service.log('request', { message: 'created on demand' });
    await service.flush();

    const content = await readFile(todayFile(nested), 'utf8');
    expect(content).toContain('created on demand');
  });

  it('never throws from log() even if the directory is unwritable', async () => {
    // Point at a path under a regular file so mkdir/appendFile fail.
    const service = new ErrorLogService(configWithDir('/dev/null/cannot'));
    expect(() => service.log('request', { message: 'swallowed' })).not.toThrow();
    await expect(service.flush()).resolves.toBeUndefined();
  });
});
