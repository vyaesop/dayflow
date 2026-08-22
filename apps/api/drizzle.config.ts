import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'postgresql',
  schema: './src/db/schema/index.ts',
  out: './drizzle',
  dbCredentials: {
    // Migrations always use the direct (non-pooled) connection string.
    url: process.env.DIRECT_DATABASE_URL ?? process.env.DATABASE_URL ?? 'postgres://dayflow:dayflow@127.0.0.1:5433/dayflow',
  },
  strict: true,
  verbose: true,
});
