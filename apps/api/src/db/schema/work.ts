import {
  type AnyPgColumn,
  boolean,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';
import { boardRole, boardType, columnScope, columnType, viewType } from './enums';
import { accounts } from './accounts';
import { users } from './auth';

export const workspaces = pgTable(
  'workspaces',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    accountId: uuid('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    createdByUserId: uuid('created_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('workspaces_account_idx').on(t.accountId)],
);

export const boards = pgTable(
  'boards',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    accountId: uuid('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    workspaceId: uuid('workspace_id')
      .notNull()
      .references(() => workspaces.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    description: text('description'),
    type: boardType('type').notNull().default('main'),
    createdByUserId: uuid('created_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    /** Archive keeps the board indefinitely; trash is purged 30 days after `trashedAt`. */
    archivedAt: timestamp('archived_at', { withTimezone: true }),
    trashedAt: timestamp('trashed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('boards_workspace_idx').on(t.workspaceId), index('boards_account_idx').on(t.accountId)],
);

export const boardMembers = pgTable(
  'board_members',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    role: boardRole('role').notNull().default('member'),
    /** Following a board surfaces its items in My Work "Following". */
    following: boolean('following').notNull().default(false),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('board_members_uq').on(t.boardId, t.userId), index('board_members_user_idx').on(t.userId)],
);

export const boardFavorites = pgTable(
  'board_favorites',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('board_favorites_uq').on(t.boardId, t.userId)],
);

export const recentVisits = pgTable(
  'recent_visits',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    visitedAt: timestamp('visited_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('recent_visits_uq').on(t.boardId, t.userId), index('recent_visits_user_idx').on(t.userId)],
);

export const groups = pgTable(
  'groups',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    title: text('title').notNull(),
    /** Token key from the muted group palette: blue | purple | green | pink | amber | red | teal | indigo */
    color: text('color').notNull().default('blue'),
    /** Fractional index for drag-reorder without renumbering. */
    position: doublePrecision('position').notNull(),
    collapsed: boolean('collapsed').notNull().default(false),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('groups_board_idx').on(t.boardId)],
);

export const items = pgTable(
  'items',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    groupId: uuid('group_id')
      .notNull()
      .references(() => groups.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    position: doublePrecision('position').notNull(),
    /** Set on subitems; they share their parent's board and group. One level only. */
    parentItemId: uuid('parent_item_id').references((): AnyPgColumn => items.id, { onDelete: 'cascade' }),
    /** Stable per-board sequence number, shown by the Item ID column. */
    serial: integer('serial').notNull(),
    createdByUserId: uuid('created_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    updatedByUserId: uuid('updated_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    /** Archive keeps the item indefinitely; trash is purged 30 days after `trashedAt`. */
    archivedAt: timestamp('archived_at', { withTimezone: true }),
    trashedAt: timestamp('trashed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('items_board_idx').on(t.boardId),
    index('items_group_idx').on(t.groupId),
    index('items_parent_idx').on(t.parentItemId),
    uniqueIndex('items_board_serial_uq').on(t.boardId, t.serial),
  ],
);

export const columns = pgTable(
  'columns',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    type: columnType('type').notNull(),
    /** Item-level columns vs. the board's subitem column set. */
    scope: columnScope('scope').notNull().default('items'),
    title: text('title').notNull(),
    /** Type-specific configuration, e.g. status labels [{id,label,color,isDone}] for status columns. */
    settings: jsonb('settings').notNull().default({}),
    position: doublePrecision('position').notNull(),
    width: doublePrecision('width'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('columns_board_idx').on(t.boardId)],
);

export const columnValues = pgTable(
  'column_values',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    itemId: uuid('item_id')
      .notNull()
      .references(() => items.id, { onDelete: 'cascade' }),
    columnId: uuid('column_id')
      .notNull()
      .references(() => columns.id, { onDelete: 'cascade' }),
    /** Shape is owned by the column-type registry, e.g. {labelId} for status, {userIds:[]} for people, {date,time?} for date. */
    value: jsonb('value'),
    updatedByUserId: uuid('updated_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('column_values_uq').on(t.itemId, t.columnId), index('column_values_column_idx').on(t.columnId)],
);

export const boardViews = pgTable(
  'board_views',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    boardId: uuid('board_id')
      .notNull()
      .references(() => boards.id, { onDelete: 'cascade' }),
    type: viewType('type').notNull(),
    name: text('name').notNull(),
    /** View configuration: filters, sort, kanban lane column, dashboard widgets, ... */
    config: jsonb('config').notNull().default({}),
    isDefault: boolean('is_default').notNull().default(false),
    position: doublePrecision('position').notNull(),
    createdByUserId: uuid('created_by_user_id').references(() => users.id, { onDelete: 'set null' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('board_views_board_idx').on(t.boardId)],
);
