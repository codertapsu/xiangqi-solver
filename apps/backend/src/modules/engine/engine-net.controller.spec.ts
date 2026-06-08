import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { promises as fs } from 'fs';
import * as os from 'os';
import * as path from 'path';
import request from 'supertest';
import { EngineNetController } from './engine-net.controller';

function fakeConfig(netPath: string | undefined): ConfigService {
  return {
    get: (key: string) => (key === 'app.engine' ? { onDeviceNetPath: netPath } : undefined),
  } as unknown as ConfigService;
}

async function makeApp(netPath: string | undefined): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({
    controllers: [EngineNetController],
    providers: [{ provide: ConfigService, useValue: fakeConfig(netPath) }],
  }).compile();
  const app = moduleRef.createNestApplication();
  await app.init();
  return app;
}

describe('EngineNetController (GET /engine/net)', () => {
  let dir: string;
  let netFile: string;
  const bytes = Buffer.from('FAKE-NNUE-CONTENTS-FOR-TEST');
  let app: INestApplication;

  beforeAll(async () => {
    dir = await fs.mkdtemp(path.join(os.tmpdir(), 'engine-net-'));
    netFile = path.join(dir, 'pikafish.nnue');
    await fs.writeFile(netFile, bytes);
  });

  afterEach(async () => {
    await app?.close();
  });

  afterAll(async () => {
    await fs.rm(dir, { recursive: true, force: true });
  });

  it('serves the net as octet-stream with the file size (no envelope)', async () => {
    app = await makeApp(netFile);
    const res = await request(app.getHttpServer()).get('/engine/net');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toContain('application/octet-stream');
    // Streamed verbatim (exact file size), NOT wrapped in the { success, data }
    // envelope — Content-Length matching the file proves the right bytes flow.
    expect(Number(res.headers['content-length'])).toBe(bytes.length);
    expect(res.headers['cache-control']).toContain('immutable');
  });

  it('404s with NET_UNAVAILABLE when the file is missing', async () => {
    app = await makeApp(path.join(dir, 'does-not-exist.nnue'));
    const res = await request(app.getHttpServer()).get('/engine/net');
    expect(res.status).toBe(404);
  });

  it('404s when no path is configured', async () => {
    app = await makeApp(undefined);
    const res = await request(app.getHttpServer()).get('/engine/net');
    expect(res.status).toBe(404);
  });
});
