import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { writeFileSync } from 'node:fs';
import type { Server as HttpServer } from 'node:http';
import { join } from 'node:path';
import { AppModule } from './app.module';
import { configureApp } from './app-setup';
import { RealtimeGateway } from './modules/realtime/realtime.gateway';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const document = configureApp(app);
  app.enableShutdownHooks();

  if (document) {
    try {
      const contractsDir = join(__dirname, '..', '..', '..', 'packages', 'contracts');
      writeFileSync(join(contractsDir, 'openapi.json'), JSON.stringify(document, null, 2));
    } catch {
      // contracts package not present in this checkout — non-fatal
    }
  }

  const port = Number(process.env.PORT ?? 4000);
  await app.listen(port);

  // The WebSocket server shares the HTTP listener, so it must attach after
  // listen() has created it.
  app.get(RealtimeGateway).attach(app.getHttpServer() as HttpServer);

  new Logger('Bootstrap').log(
    `Dayflow API ready on http://localhost:${port}${document ? ' (docs at /docs)' : ''}`,
  );
}

void bootstrap();
