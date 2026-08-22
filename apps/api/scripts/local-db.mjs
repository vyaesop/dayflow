/**
 * Starts a project-local PostgreSQL instance (no Docker, no system service).
 * Data lives in <repo>/.pgdata. Connection: postgres://dayflow:dayflow@127.0.0.1:5433/dayflow
 */
import EmbeddedPostgres from 'embedded-postgres';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = resolve(join(here, '..', '..', '..', '.pgdata'));
const alreadyInitialised = existsSync(join(dataDir, 'PG_VERSION'));

const pg = new EmbeddedPostgres({
  databaseDir: dataDir,
  user: 'dayflow',
  password: 'dayflow',
  port: 5433,
  persistent: true,
});

if (!alreadyInitialised) {
  console.log(`Initialising local Postgres in ${dataDir} ...`);
  await pg.initialise();
}
await pg.start();
if (!alreadyInitialised) {
  await pg.createDatabase('dayflow');
}
console.log('Local Postgres ready on postgres://dayflow:dayflow@127.0.0.1:5433/dayflow');
console.log('Press Ctrl+C to stop.');

const shutdown = async () => {
  console.log('\nStopping local Postgres ...');
  await pg.stop();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
