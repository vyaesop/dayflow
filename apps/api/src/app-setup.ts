import { INestApplication, ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule, type OpenAPIObject } from '@nestjs/swagger';
import helmet from 'helmet';

/**
 * Configuration shared by the long-running (`main.ts`) and serverless
 * (`serverless.ts`) entrypoints, so security posture can never drift between
 * the two.
 *
 * Returns the OpenAPI document in non-production (where /docs is mounted),
 * null in production (no public API explorer).
 */
export function configureApp(app: INestApplication): OpenAPIObject | null {
  const production = process.env.NODE_ENV === 'production';

  app.use(helmet());
  app.setGlobalPrefix('v1', { exclude: ['healthz', 'invite/:token'] });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));

  const corsOrigins = (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  // An empty list in production means "no browser origins" — never reflect-any.
  // (Native apps are unaffected: they don't send an Origin header.)
  app.enableCors({ origin: corsOrigins.length ? corsOrigins : production ? false : true });

  if (production) return null;

  const swaggerConfig = new DocumentBuilder()
    .setTitle('Dayflow API')
    .setDescription('Work management platform — boards, items, collaboration.')
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('docs', app, document);
  return document;
}
