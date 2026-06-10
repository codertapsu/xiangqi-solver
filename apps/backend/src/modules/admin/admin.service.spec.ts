import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConfigService } from '@nestjs/config';
import { AdminService } from './admin.service';

function config(dir: string, secret: string): ConfigService {
  return {
    get: (k: string) => {
      if (k === 'app.hints') return { dataDir: dir };
      if (k === 'app.admin') return { secret };
      return undefined;
    },
  } as unknown as ConfigService;
}

describe('AdminService', () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'xiangqi-admin-'));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('isAdmin reads admins.json and ignores _comment keys', async () => {
    await writeFile(
      join(dir, 'admins.json'),
      JSON.stringify({ _comment: 'note', 'dev-abc-123': 'me' }),
    );
    const svc = new AdminService(config(dir, 's3cret'));
    expect(await svc.isAdmin('dev-abc-123')).toBe(true);
    expect(await svc.isAdmin('_comment')).toBe(false);
    expect(await svc.isAdmin('someone-else')).toBe(false);
    expect(await svc.isAdmin('')).toBe(false);
  });

  it('isAdmin is false when admins.json is missing', async () => {
    const svc = new AdminService(config(dir, 's3cret'));
    expect(await svc.isAdmin('anyone')).toBe(false);
  });

  it('verifySecret matches the configured secret and rejects when none is set', () => {
    expect(new AdminService(config(dir, 's3cret')).verifySecret('s3cret')).toBe(true);
    expect(new AdminService(config(dir, 's3cret')).verifySecret('wrong')).toBe(false);
    expect(new AdminService(config(dir, 's3cret')).verifySecret(undefined)).toBe(false);
    // No secret configured → admin writes disabled (always false).
    expect(new AdminService(config(dir, '')).verifySecret('anything')).toBe(false);
    expect(new AdminService(config(dir, '')).verifySecret('')).toBe(false);
  });

  it('authorize requires BOTH an admin device AND a valid secret', async () => {
    await writeFile(join(dir, 'admins.json'), JSON.stringify({ 'dev-abc-123': 'me' }));
    const svc = new AdminService(config(dir, 's3cret'));
    expect(await svc.authorize('dev-abc-123', 's3cret')).toBe(true);
    expect(await svc.authorize('dev-abc-123', 'wrong')).toBe(false);
    expect(await svc.authorize('other-device', 's3cret')).toBe(false);
  });
});
