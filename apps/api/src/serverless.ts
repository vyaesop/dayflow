import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import type { Express } from 'express';
import { AppModule } from './app.module';

/**
 * Serverless entry: boots the Nest app once per instance and hands back the
 * underlying Express handler. No listen() — the platform owns the socket —
 * and no WebSocket gateway, since serverless functions cannot hold an
 * upgraded connection; realtime publish() degrades to a no-op with zero
 * subscribers.
 */
let cached: Promise<Express> | undefined;

async function build(): Promise<Express> {
  const app = await NestFactory.create(AppModule);

  app.use(helmet());
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));

  const corsOrigins = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  app.enableCors({ origin: corsOrigins.length ? corsOrigins : true });

  const swaggerConfig = new DocumentBuilder()
    .setTitle('Dayflow API')
    .setDescription('Work management platform — boards, items, collaboration.')
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  SwaggerModule.setup('docs', app, SwaggerModule.createDocument(app, swaggerConfig));

  await app.init();
  return app.getHttpAdapter().getInstance() as Express;
}

export function getApp(): Promise<Express> {
  cached ??= build();
  return cached;
}
