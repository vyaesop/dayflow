import { and, isNull, type SQL } from 'drizzle-orm';
import { boards, items } from './schema';

/**
 * Rows in the archive or the trash are hidden from every ordinary read.
 * Archive keeps content indefinitely; trash is purged 30 days after `trashedAt`.
 */
export function boardIsLive(): SQL {
  return and(isNull(boards.archivedAt), isNull(boards.trashedAt))!;
}

export function itemIsLive(): SQL {
  return and(isNull(items.archivedAt), isNull(items.trashedAt))!;
}
