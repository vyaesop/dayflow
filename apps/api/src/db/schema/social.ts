import { index, integer, jsonb, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';
import { activityEvent } from './enums';
import { boards, columns, items } from './work';
import { users } from './auth';

/**
 * Updates live either on an item (item feed) or directly on a board (board discussion).
 * Exactly one of itemId | boardDiscussionId-style targets is set; both reference for cheap joins.
 */
export const updates = pgTable(
  'updates',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    itemId: uuid('item_id').references(() => items.id, { onDelete: 'cascade' }),
    authorUserId: uuid('author_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    /** Threaded replies reference their parent update. */
    parentId: uuid('parent_id'),
    /** Rich text stored as a portable JSON document (paragraphs, mentions, checklists). */
    body: jsonb('body').notNull(),
    bodyText: text('body_text').notNull(),
    mentionedUserIds: uuid('mentioned_user_ids').array().notNull().default([]),
    editedAt: timestamp('edited_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('updates_item_idx').on(t.itemId), index('updates_board_idx').on(t.boardId)],
);

/** Emoji reactions on updates; a 👍 reaction is what the legacy "like" maps to. */
export const updateReactions = pgTable(
  'update_reactions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    updateId: uuid('update_id')
      .notNull()
      .references(() => updates.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    emoji: text('emoji').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('update_reactions_uq').on(t.updateId, t.userId, t.emoji),
    index('update_reactions_update_idx').on(t.updateId),
  ],
);

export const updateBookmarks = pgTable(
  'update_bookmarks',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    updateId: uuid('update_id')
      .notNull()
      .references(() => updates.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('update_bookmarks_uq').on(t.updateId, t.userId)],
);

export const files = pgTable(
  'files',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id').references(() => boards.id, { onDelete: 'cascade' }),
    itemId: uuid('item_id').references(() => items.id, { onDelete: 'cascade' }),
    updateId: uuid('update_id').references(() => updates.id, { onDelete: 'cascade' }),
    /** Set when the file lives in a Files column cell (the cell's fileIds mirror it). */
    columnId: uuid('column_id').references(() => columns.id, { onDelete: 'set null' }),
    uploadedByUserId: uuid('uploaded_by_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    storageKey: text('storage_key').notNull(),
    fileName: text('file_name').notNull(),
    mimeType: text('mime_type').notNull(),
    sizeBytes: integer('size_bytes').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('files_item_idx').on(t.itemId)],
);

export const activityLog = pgTable(
  'activity_log',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    itemId: uuid('item_id').references(() => items.id, { onDelete: 'cascade' }),
    actorUserId: uuid('actor_user_id').references(() => users.id, { onDelete: 'set null' }),
    event: activityEvent('event').notNull(),
    /** Event payload, e.g. {columnId, from, to} for column_value_changed. */
    payload: jsonb('payload').notNull().default({}),
    /** Stamped when the entry was reverted through the 7-day undo. */
    undoneAt: timestamp('undone_at', { withTimezone: true }),
    undoneByUserId: uuid('undone_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('activity_log_board_idx').on(t.boardId, t.createdAt),
    index('activity_log_item_idx').on(t.itemId),
  ],
);
