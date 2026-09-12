import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { Pool } from 'pg';
import { join } from 'node:path';

async function main(): Promise<void> {
  const url = process.env.DIRECT_DATABASE_URL ?? process.env.DB_LIVE_URL ?? process.env.DATABASE_URL;
  if (!url) {
    // No silent localhost fallback: a misconfigured environment must fail
    // loudly rather than migrate the wrong database.
    console.error(
      'No database URL configured. Set DIRECT_DATABASE_URL, DB_LIVE_URL, or DATABASE_URL before running migrations.',
    );
    process.exit(1);
  }

  const target = new URL(url);
  console.log(`Running migrations against ${target.hostname}${target.pathname} ...`);

  const pool = new Pool({ connectionString: url, max: 1 });
  const db = drizzle(pool);
  await migrate(db, { migrationsFolder: join(__dirname, '..', 'drizzle') });
  await pool.end();
  console.log('Migrations complete.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
