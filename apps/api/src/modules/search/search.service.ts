import { Inject, Injectable } from '@nestjs/common';
import { and, eq, ilike, isNull, or, sql } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boards, groups, items, workspaces } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

export interface SearchResults {
  boards: Array<{ id: string; name: string; workspaceName: string }>;
  items: Array<{ id: string; name: string; boardId: string; boardName: string; groupTitle: string; groupColor: string }>;
}

@Injectable()
export class SearchService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  /**
   * Substring search across board and item names within the caller's account.
   * `%` and `_` are escaped so a query like "50%" is treated literally.
   */
  async search(auth: AuthContext, rawQuery: string, limit = 20): Promise<SearchResults> {
    const query = rawQuery.trim();
    if (query.length < 2) return { boards: [], items: [] };

    const pattern = `%${escapeLike(query)}%`;

    const [boardRows, itemRows] = await Promise.all([
      this.db
        .select({ id: boards.id, name: boards.name, workspaceName: workspaces.name })
        .from(boards)
        .innerJoin(workspaces, eq(boards.workspaceId, workspaces.id))
        .where(
          and(
            eq(boards.accountId, auth.accountId),
            isNull(boards.archivedAt),
            or(ilike(boards.name, pattern), ilike(boards.description, pattern)),
          ),
        )
        .limit(limit),
      this.db
        .select({
          id: items.id,
          name: items.name,
          boardId: boards.id,
          boardName: boards.name,
          groupTitle: groups.title,
          groupColor: groups.color,
        })
        .from(items)
        .innerJoin(boards, eq(items.boardId, boards.id))
        .innerJoin(groups, eq(items.groupId, groups.id))
        .where(
          and(
            eq(boards.accountId, auth.accountId),
            isNull(items.archivedAt),
            isNull(boards.archivedAt),
            ilike(items.name, pattern),
          ),
        )
        // Prefix matches first, then alphabetical — cheap relevance without FTS.
        .orderBy(sql`case when ${items.name} ilike ${escapeLike(query) + '%'} then 0 else 1 end`, items.name)
        .limit(limit),
    ]);

    return { boards: boardRows, items: itemRows };
  }
}

/** Escapes LIKE wildcards so user input matches literally. */
function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (match) => `\\${match}`);
}
