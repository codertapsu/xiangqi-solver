import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory, Reflector } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AppConfig } from './config/configuration';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { ErrorLogService } from './modules/logging/error-log.service';
import { parseTrustProxy } from './common/utils/trust-proxy.util';

// NOTE: Node's built-in `fetch` (the only outbound HTTP, used by the vision
// providers) already pools + keep-alives connections via its OWN bundled undici
// instance. Tuning it from a userland `undici` package's setGlobalDispatcher is
// unreliable across Node versions (separate global-dispatcher singleton), so we
// leave the default in place rather than ship a no-op.

/**
 * Application bootstrap. Binds 0.0.0.0:PORT, sets the /api prefix, enables
 * permissive CORS for development, and installs the global validation pipe,
 * response envelope interceptor, exception filter, and Swagger docs.
 */
async function bootstrap(): Promise<void> {
  const logger = new Logger('Bootstrap');
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: false });

  const config = app.get(ConfigService);
  const appConfig = config.get<AppConfig>('app');
  const port = appConfig?.port ?? 3000;

  // Client IP resolution. Both rate caps (the global throttle and the
  // per-source-IP analysis cap) key on req.ip, which is the SOCKET peer unless
  // we say which hops to trust — so behind a reverse proxy the whole fleet would
  // otherwise share one bucket. Off by default: trusting X-Forwarded-For when
  // nothing rewrites it would let any caller spoof its way past both caps.
  const trustProxy = parseTrustProxy(appConfig?.trustProxy ?? '');
  if (trustProxy !== undefined) {
    app.set('trust proxy', trustProxy);
    logger.log(`Trusting proxy hops: ${String(trustProxy)} (client IP from X-Forwarded-For)`);
  }

  // All routes under /api.
  app.setGlobalPrefix('api');

  // Permissive CORS for development (all origins).
  app.enableCors({ origin: true });

  // Strict request validation.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );

  // Global success envelope + error envelope. The filter also appends every
  // failed request to the date-grouped error log (see ErrorLogService).
  app.useGlobalInterceptors(new ResponseInterceptor(app.get(Reflector)));
  app.useGlobalFilters(new AllExceptionsFilter(app.get(ErrorLogService)));

  // OpenAPI docs at /api/docs.
  const swaggerConfig = new DocumentBuilder()
    .setTitle('Xiangqi Solver API')
    .setDescription('Screenshot -> board -> FEN -> engine best move.')
    .setVersion('0.1.0')
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, document);

  // A bridge is selected but no rollout token is set: the two-factor gate fails
  // closed, so every device silently uses the cloud provider. Say so once at
  // boot rather than leaving the operator to wonder why nothing routes.
  if (appConfig?.ai.localVisionProvider !== 'none' && !appConfig?.ai.localVisionRolloutToken) {
    logger.warn(
      `AI_LOCAL_VISION_PROVIDER=${appConfig?.ai.localVisionProvider ?? 'codex'} but ` +
        'LOCAL_VISION_ROLLOUT_TOKEN is empty - local vision is DISABLED for every device. ' +
        'Set the token here and have the client send it as x-local-vision-token.',
    );
  }

  const ai = appConfig?.ai;
  const aiModel =
    ai?.provider === 'gemini'
      ? ai.geminiModel
      : ai?.provider === 'apikeyfun'
        ? ai.apikeyfunModel
        : ai?.provider === 'mock'
          ? 'mock'
          : ai?.openaiModel;

  await app.listen(port, '0.0.0.0');
  logger.log(`Backend listening on http://0.0.0.0:${port}/api`);
  logger.log(`Swagger docs at http://0.0.0.0:${port}/api/docs`);
  logger.log(
    `Providers -> AI: ${appConfig?.ai.provider ?? 'mock'} - Model: ${aiModel ?? 'mock'}, Engine: ${appConfig?.engine.provider ?? 'mock'}`,
  );
}

void bootstrap();
