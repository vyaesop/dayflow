import { index, integer, jsonb, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { accounts } from './accounts';
import { users } from './auth';

/**
 * Board templates. Rows with an `accountId` are account-authored ("Save board
 * as template"); the built-in gallery ships in code (`templates.catalog.ts`).
 */
export const templates = pgTable(
  'templates',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    key: text('key').notNull(),
    accountId: uuid('account_id').references(() => accounts.id, { onDelete: 'cascade' }),
    createdByUserId: uuid('created_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    name: text('name').notNull(),
    description: text('description').notNull(),
    /** Emoji-ish icon token + accent color for the gallery card. */
    icon: text('icon').notNull(),
    accentColor: text('accent_color').notNull(),
    usedByTeams: integer('used_by_teams').notNull().default(0),
    /** Blueprint in the `BoardTemplate` shape: columns (with settings), groups, items and cell values. */
    payload: jsonb('payload').notNull(),
    sortOrder: integer('sort_order').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('templates_key_uq').on(t.key), index('templates_account_idx').on(t.accountId)],
);
