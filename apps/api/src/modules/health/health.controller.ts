import { Controller, Get, Inject, ServiceUnavailableException } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { sql } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';

const startedAt = Date.now();

@ApiTags('health')
@Controller()
export class HealthController {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  /** Liveness + readiness: proves the process is up and the database answers. */
  @Get('healthz')
  @ApiOperation({ summary: 'Health check (unauthenticated)' })
  async health(): Promise<{ ok: true; uptimeSec: number }> {
    try {
      await Promise.race([
        this.db.execute(sql`select 1`),
        new Promise((_, reject) => setTimeout(() => reject(new Error('db timeout')), 5_000)),
      ]);
    } catch {
      throw new ServiceUnavailableException({ ok: false, message: 'Database is unreachable' });
    }
    return { ok: true, uptimeSec: Math.round((Date.now() - startedAt) / 1000) };
  }
}
