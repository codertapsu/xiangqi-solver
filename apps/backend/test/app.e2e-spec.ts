import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Test, TestingModule } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { ResponseInterceptor } from '../src/common/interceptors/response.interceptor';
import { AllExceptionsFilter } from '../src/common/filters/all-exceptions.filter';

/**
 * A minimal valid 1x1 PNG, generated in-memory so the screenshot endpoint can
 * be exercised end-to-end without any fixture files on disk.
 */
const TINY_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64',
);

describe('Backend (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const moduleRef: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api');
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }),
    );
    app.useGlobalInterceptors(new ResponseInterceptor(app.get(Reflector)));
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  describe('GET /api/health', () => {
    it('returns an unwrapped health payload', async () => {
      const res = await request(app.getHttpServer()).get('/api/health').expect(200);
      expect(res.body.status).toBe('ok');
      expect(typeof res.body.timestamp).toBe('string');
      expect(typeof res.body.uptimeSeconds).toBe('number');
      expect(res.body).not.toHaveProperty('success');
    });
  });

  describe('POST /api/analysis/board', () => {
    it('returns a wrapped AnalysisResult for the start position (mock)', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/analysis/board')
        .send({
          engineProvider: 'mock',
          sideToMove: 'red',
          pieces: [
            { color: 'red', type: 'king', file: 4, rank: 0 },
            { color: 'black', type: 'king', file: 4, rank: 9 },
          ],
        })
        .expect(201);

      expect(res.body.success).toBe(true);
      expect(res.body.data.engine).toEqual({ provider: 'mock', ok: true });
      expect(res.body.data.bestMove.uci).toBe('b2e2');
      expect(res.body.data.board.fen).toContain(' w ');
    });

    it('rejects an invalid board with the error envelope', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/analysis/board')
        .send({ sideToMove: 'red', pieces: [{ color: 'red', type: 'king', file: 4, rank: 0 }] })
        .expect(400);

      expect(res.body.success).toBe(false);
      // The board validator throws an explicit, machine-readable code and
      // surfaces the specific reasons in details.
      expect(res.body.error.code).toBe('INVALID_BOARD');
      expect(Array.isArray(res.body.error.details)).toBe(true);
      expect(res.body.error.details.join(' ')).toMatch(/black king/i);
    });
  });

  describe('POST /api/analysis/screenshot', () => {
    it('analyzes a tiny PNG via the mock vision provider', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/analysis/screenshot')
        .attach('screenshot', TINY_PNG, { filename: 'board.png', contentType: 'image/png' })
        .field('provider', 'mock')
        .field('engineProvider', 'mock')
        .expect(201);

      expect(res.body.success).toBe(true);
      expect(res.body.data.vision).toEqual({ provider: 'mock', ok: true });
      expect(res.body.data.bestMove.uci).toBe('b2e2');
    });

    it('rejects a missing file with 400', async () => {
      const res = await request(app.getHttpServer()).post('/api/analysis/screenshot').expect(400);
      expect(res.body.success).toBe(false);
    });
  });

  describe('POST /api/analysis/extract', () => {
    it('returns the recognized board (vision-only) with no bestMove', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/analysis/extract')
        .attach('screenshot', TINY_PNG, { filename: 'board.png', contentType: 'image/png' })
        .field('provider', 'mock')
        .expect(201);

      expect(res.body.success).toBe(true);
      expect(res.body.data.vision).toEqual({ provider: 'mock', ok: true });
      expect(res.body.data.board.pieces.length).toBeGreaterThan(0);
      expect(res.body.data.bestMove).toBeUndefined();
      expect(res.body.data.engine).toBeUndefined();
    });
  });

  describe('POST /api/analysis/screenshot/stream', () => {
    it('streams received -> board -> done stages as NDJSON (mock)', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/analysis/screenshot/stream')
        .field('provider', 'mock')
        .field('engineProvider', 'mock')
        .field('sideToMove', 'red')
        .attach('screenshot', TINY_PNG, 'capture.png')
        .expect(200)
        .expect('Content-Type', /application\/x-ndjson/);

      const lines = res.text
        .trim()
        .split('\n')
        .map((l) => JSON.parse(l) as Record<string, any>);
      expect(lines[0]).toEqual({ stage: 'received' });
      expect(lines[1].stage).toBe('board');
      expect(typeof lines[1].board.fen).toBe('string');
      expect(Array.isArray(lines[1].board.pieces)).toBe(true);
      expect(lines[2].stage).toBe('done');
      expect(lines[2].data.bestMove.uci).toBe('b2e2');
      expect(lines[2].data.board.fen).toBe(lines[1].board.fen);
    });

    it('rejects a missing file with the standard envelope (no stream begun)', async () => {
      const res = await request(app.getHttpServer())
        .post('/api/analysis/screenshot/stream')
        .field('provider', 'mock')
        .expect(400);
      expect(res.body.success).toBe(false);
      expect(res.body.error.code).toBe('MISSING_FILE');
    });
  });
});
