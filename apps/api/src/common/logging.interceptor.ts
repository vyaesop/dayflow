import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import type { Response } from 'express';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import type { AuthedRequest } from './jwt-auth.guard';

/** One line per request: method, path, status, duration, and the acting user when known. */
@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('Http');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<AuthedRequest>();
    const response = context.switchToHttp().getResponse<Response>();
    if (request.url === '/healthz') return next.handle();

    const startedAt = Date.now();
    const who = (): string => (request.auth ? ` user=${request.auth.userId}` : '');
    return next.handle().pipe(
      tap({
        next: () =>
          this.logger.log(`${request.method} ${request.url} ${response.statusCode} ${Date.now() - startedAt}ms${who()}`),
        error: (err: unknown) => {
          const status = err instanceof Error && 'getStatus' in err ? (err as { getStatus(): number }).getStatus() : 500;
          this.logger.warn(`${request.method} ${request.url} ${status} ${Date.now() - startedAt}ms${who()}`);
        },
      }),
    );
  }
}
