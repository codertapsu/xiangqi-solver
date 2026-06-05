import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory, Reflector } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { AppConfig } from './config/configuration';
import { ResponseInterceptor } from './common/interceptors/response.interceptor';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';

/**
 * Application bootstrap. Binds 0.0.0.0:PORT, sets the /api prefix, enables
 * permissive CORS for development, and installs the global validation pipe,
 * response envelope interceptor, exception filter, and Swagger docs.
 */
async function bootstrap(): Promise<void> {
  const logger = new Logger('Bootstrap');
  const app = await NestFactory.create(AppModule, { bufferLogs: false });

  const config = app.get(ConfigService);
  const appConfig = config.get<AppConfig>('app');
  const port = appConfig?.port ?? 3000;

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

  // Global success envelope + error envelope.
  app.useGlobalInterceptors(new ResponseInterceptor(app.get(Reflector)));
  app.useGlobalFilters(new AllExceptionsFilter());

  // OpenAPI docs at /api/docs.
  const swaggerConfig = new DocumentBuilder()
    .setTitle('Xiangqi Solver API')
    .setDescription('Screenshot -> board -> FEN -> engine best move.')
    .setVersion('0.1.0')
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, document);

  const aiModel =
    appConfig?.ai.provider === 'gemini' ? appConfig.ai.geminiModel : appConfig?.ai.openaiModel;

  await app.listen(port, '0.0.0.0');
  logger.log(`Backend listening on http://0.0.0.0:${port}/api`);
  logger.log(`Swagger docs at http://0.0.0.0:${port}/api/docs`);
  logger.log(
    `Providers -> AI: ${appConfig?.ai.provider ?? 'mock'} - Model: ${aiModel ?? 'mock'}, Engine: ${appConfig?.engine.provider ?? 'mock'}`,
  );
}

void bootstrap();
