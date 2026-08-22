import { integer, jsonb, pgTable, text, uniqueIndex, uuid } from 'drizzle-orm/pg-core';

/** Board templates shown in the "Choose a template" gallery. */
export const templates = pgTable(
  'templates',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    key: text('key').notNull(),
    name: text('name').notNull(),
    description: text('description').notNull(),
    /** Emoji-ish icon token + accent color for the gallery card. */
    icon: text('icon').notNull(),
    accentColor: text('accent_color').notNull(),
    usedByTeams: integer('used_by_teams').notNull().default(0),
    /** Seed payload: groups, columns (with settings), items and cell values. */
    payload: jsonb('payload').notNull(),
    sortOrder: integer('sort_order').notNull().default(0),
  },
  (t) => [uniqueIndex('templates_key_uq').on(t.key)],
);
