import { Inject, Injectable } from '@nestjs/common';
import { and, count, desc, eq, inArray, isNotNull, isNull, or } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';
import { Database, DRIZZLE } from '../../db/db.module';
import { boards, groups, items, workspaces } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardAccessService } from '../access/board-access.service';

export const TRASH_RETENTION_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;

export interface ArchivedBoard {
  id: string;
  name: string;
  type: string;
  workspaceName: string;
  itemCount: number;
  archivedAt: string | null;
  trashedAt: string | null;
  purgeAt: string | null;
}

export interface ArchivedItem {
  id: string;
  name: string;
  boardId: string;
  boardName: string;
  groupTitle: string;
  groupColor: string;
  parentItemName: string | null;
  archivedAt: string | null;
  trashedAt: string | null;
  purgeAt: string | null;
}

export interface ArchiveListing {
  boards: ArchivedBoard[];
  items: ArchivedItem[];
}

/**
 * Read side of Archive and Trash. Archive = boards/items with `archivedAt`
 * and no `trashedAt`; Trash = anything with `trashedAt`. Items whose whole
 * board is archived/trashed are listed under the board, not individually.
 */
@Injectable()
export class ArchiveService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly boardAccess: BoardAccessService,
  ) {}

  listArchive(auth: AuthContext, boardId?: string): Promise<ArchiveListing> {
    return this.listing(auth, 'archive', boardId);
  }

  listTrash(auth: AuthContext, boardId?: string): Promise<ArchiveListing> {
    return this.listing(auth, 'trash', boardId);
  }

  private async listing(auth: AuthContext, mode: 'archive' | 'trash', boardId?: string): Promise<ArchiveListing> {
    const boardState = mode === 'archive' ? and(isNotNull(boards.archivedAt), isNull(boards.trashedAt)) : isNotNull(boards.trashedAt);
    const itemState = mode === 'archive' ? and(isNotNull(items.archivedAt), isNull(items.trashedAt)) : isNotNull(items.trashedAt);

    const boardRows = boardId
      ? []
      : await this.db
          .select({
            id: boards.id,
            name: boards.name,
            type: boards.type,
            workspaceName: workspaces.name,
            archivedAt: boards.archivedAt,
            trashedAt: boards.trashedAt,
          })
          .from(boards)
          .innerJoin(workspaces, eq(boards.workspaceId, workspaces.id))
          .where(and(eq(boards.accountId, auth.accountId), boardState, this.boardAccess.visibleTo(auth)))
          .orderBy(desc(mode === 'archive' ? boards.archivedAt : boards.trashedAt));

    const boardIds = boardRows.map((b) => b.id);
    const counts = boardIds.length
      ? await this.db
          .select({ boardId: items.boardId, n: count() })
          .from(items)
          .where(and(inArray(items.boardId, boardIds), isNull(items.parentItemId)))
          .groupBy(items.boardId)
      : [];
    const countByBoard = new Map(counts.map((c) => [c.boardId, Number(c.n)]));

    const parent = alias(items, 'parent');
    const itemRows = await this.db
      .select({
        id: items.id,
        name: items.name,
        boardId: items.boardId,
        boardName: boards.name,
        groupTitle: groups.title,
        groupColor: groups.color,
        parentItemName: parent.name,
        archivedAt: items.archivedAt,
        trashedAt: items.trashedAt,
      })
      .from(items)
      .innerJoin(boards, eq(items.boardId, boards.id))
      .innerJoin(groups, eq(items.groupId, groups.id))
      .leftJoin(parent, eq(items.parentItemId, parent.id))
      .where(
        and(
          eq(boards.accountId, auth.accountId),
          // Only live boards: an archived board's items are listed via the board.
          isNull(boards.archivedAt),
          isNull(boards.trashedAt),
          itemState,
          boardId ? eq(items.boardId, boardId) : undefined,
          // Subitems archived together with their parent ride along with it.
          or(isNull(items.parentItemId), isNull(mode === 'archive' ? parent.archivedAt : parent.trashedAt)),
          this.boardAccess.visibleTo(auth),
        ),
      )
      .orderBy(desc(mode === 'archive' ? items.archivedAt : items.trashedAt))
      .limit(500);

    const purgeAt = (trashedAt: Date | null) =>
      trashedAt ? new Date(trashedAt.getTime() + TRASH_RETENTION_DAYS * DAY_MS).toISOString() : null;

    return {
      boards: boardRows.map((b) => ({
        id: b.id,
        name: b.name,
        type: b.type,
        workspaceName: b.workspaceName,
        itemCount: countByBoard.get(b.id) ?? 0,
        archivedAt: b.archivedAt?.toISOString() ?? null,
        trashedAt: b.trashedAt?.toISOString() ?? null,
        purgeAt: purgeAt(b.trashedAt),
      })),
      items: itemRows.map((i) => ({
        id: i.id,
        name: i.name,
        boardId: i.boardId,
        boardName: i.boardName,
        groupTitle: i.groupTitle,
        groupColor: i.groupColor,
        parentItemName: i.parentItemName ?? null,
        archivedAt: i.archivedAt?.toISOString() ?? null,
        trashedAt: i.trashedAt?.toISOString() ?? null,
        purgeAt: purgeAt(i.trashedAt),
      })),
    };
  }
}
