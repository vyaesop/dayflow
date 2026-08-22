import { drizzle } from 'drizzle-orm/node-postgres';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import { Pool } from 'pg';
import { join } from 'node:path';

async function main(): Promise<void> {
  const url =
    process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL ?? 'postgres://dayflow:dayflow@127.0.0.1:5433/dayflow';
  const pool = new Pool({ connectionString: url, max: 1 });
  const db = drizzle(pool);
  console.log('Running migrations ...');
  await migrate(db, { migrationsFolder: join(__dirname, '..', 'drizzle') });
  await pool.end();
  console.log('Migrations complete.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
