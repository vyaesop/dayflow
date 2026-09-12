import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import type { Express } from 'express';
import { AppModule } from './app.module';
import { configureApp } from './app-setup';

/**
 * Serverless entry: boots the Nest app once per instance and hands back the
 * underlying Express handler. No listen() — the platform owns the socket —
 * and no WebSocket gateway, since serverless functions cannot hold an
 * upgraded connection; realtime publish() degrades to a no-op with zero
 * subscribers (clients fall back to polling).
 */
let cached: Promise<Express> | undefined;

async function build(): Promise<Express> {
  const app = await NestFactory.create(AppModule);
  configureApp(app);
  await app.init();
  return app.getHttpAdapter().getInstance() as Express;
}

export function getApp(): Promise<Express> {
  cached ??= build();
  return cached;
}
