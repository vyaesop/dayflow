import { index, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';
import { accounts } from './accounts';
import { users } from './auth';

/** Product feedback submitted from the app's feedback form. */
export const feedback = pgTable(
  'feedback',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    accountId: uuid('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    /** Kept (nulled) if the author is later deleted, so the feedback itself survives. */
    userId: uuid('user_id').references(() => users.id, { onDelete: 'set null' }),
    message: text('message').notNull(),
    userAgent: text('user_agent'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [index('feedback_account_idx').on(t.accountId, t.createdAt)],
);
