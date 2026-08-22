import { Global, Module, OnApplicationShutdown } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { drizzle as drizzleNode, NodePgDatabase } from 'drizzle-orm/node-postgres';
import { drizzle as drizzleNeon } from 'drizzle-orm/neon-serverless';
import { neonConfig, Pool as NeonPool } from '@neondatabase/serverless';
import { Pool } from 'pg';
import ws from 'ws';
import * as schema from './schema';
import type { Env } from '../config/env';

export const DRIZZLE = Symbol('DRIZZLE');

export type Database = NodePgDatabase<typeof schema>;

function isNeonUrl(url: string): boolean {
  return /neon\.tech/i.test(url);
}

@Global()
@Module({
  providers: [
    {
      provide: DRIZZLE,
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>): Database => {
        const liveUrl: string | undefined = config.get('DB_LIVE_URL', { infer: true });
        const url = liveUrl ?? config.getOrThrow('DATABASE_URL', { infer: true });
        if (isNeonUrl(url)) {
          neonConfig.webSocketConstructor = ws;
          const pool = new NeonPool({ connectionString: url });
          // The neon-serverless drizzle instance is API-compatible with node-postgres for our usage.
          return drizzleNeon(pool, { schema }) as unknown as Database;
        }
        const pool = new Pool({ connectionString: url, max: 10 });
        return drizzleNode(pool, { schema });
      },
    },
  ],
  exports: [DRIZZLE],
})
export class DbModule implements OnApplicationShutdown {
  onApplicationShutdown(): void {
    // Pools are closed with the process; explicit teardown is handled by Nest's shutdown hooks upstream.
  }
}
