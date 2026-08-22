import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import type { Server as HttpServer } from 'node:http';
import { AppModule } from './app.module';
import { RealtimeGateway } from './modules/realtime/realtime.gateway';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  app.use(helmet());
  app.setGlobalPrefix('v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.enableShutdownHooks();

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
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);

  const port = Number(process.env.PORT ?? 4000);
  await app.listen(port);

  // The WebSocket server shares the HTTP listener, so it must attach after
  // listen() has created it.
  app.get(RealtimeGateway).attach(app.getHttpServer() as HttpServer);

  console.log(`Dayflow API ready on http://localhost:${port} (docs at /docs)`);
}

void bootstrap();
