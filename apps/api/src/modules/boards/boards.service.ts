import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, desc, eq, inArray } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardIsLive, itemIsLive } from '../../db/live';
import {
  boardFavorites,
  boardMembers,
  boards,
  boardViews,
  columns,
  columnValues,
  items,
  recentVisits,
  updates,
  userProfiles,
  workspaces,
  groups,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardAccessService } from '../access/board-access.service';
import { BoardContextService } from '../access/board-context.service';
import { presentColumn, presentGroup, presentItem, type ColumnPayload, type GroupPayload } from './presenters';

export interface ViewPayload {
  id: string;
  boardId: string;
  type: string;
  name: string;
  isDefault: boolean;
  position: number;
  config: Record<string, unknown>;
  createdByUserId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface BoardPayload {
  id: string;
  name: string;
  description: string | null;
  type: string;
  workspace: { id: string; name: string };
  isFavorite: boolean;
  columns: ColumnPayload[];
  groups: GroupPayload[];
  members: Array<{ userId: string; fullName: string; avatarUrl: string | null; role: string }>;
  views: ViewPayload[];
  me: { userId: string; canEdit: boolean; canManage: boolean };
}

export function presentView(view: typeof boardViews.$inferSelect): ViewPayload {
  return {
    id: view.id,
    boardId: view.boardId,
    type: view.type,
    name: view.name,
    isDefault: view.isDefault,
    position: view.position,
    config: (view.config ?? {}) as Record<string, unknown>,
    createdByUserId: view.createdByUserId,
    createdAt: view.createdAt.toISOString(),
    updatedAt: view.updatedAt.toISOString(),
  };
}

@Injectable()
export class BoardsService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly boardAccess: BoardAccessService,
    private readonly ctx: BoardContextService,
  ) {}

  async getBoard(auth: AuthContext, boardId: string): Promise<BoardPayload> {
    const [board] = await this.db
      .select({
        id: boards.id,
        name: boards.name,
        description: boards.description,
        type: boards.type,
        workspaceId: boards.workspaceId,
        workspaceName: workspaces.name,
      })
      .from(boards)
      .innerJoin(workspaces, eq(boards.workspaceId, workspaces.id))
      .where(and(eq(boards.id, boardId), eq(boards.accountId, auth.accountId), boardIsLive(), this.boardAccess.visibleTo(auth)))
      .limit(1);
    if (!board) throw new NotFoundException('Board not found');

    const [cols, groupRows, itemRows, memberRows, favorite, viewRows, canEdit, canManage] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, boardId)).orderBy(asc(columns.position)),
      this.db.select().from(groups).where(eq(groups.boardId, boardId)).orderBy(asc(groups.position)),
      this.db
        .select()
        .from(items)
        .where(and(eq(items.boardId, boardId), itemIsLive()))
        .orderBy(asc(items.position)),
      this.db
        .select({
          userId: boardMembers.userId,
          fullName: userProfiles.fullName,
          avatarUrl: userProfiles.avatarUrl,
          role: boardMembers.role,
        })
        .from(boardMembers)
        .innerJoin(userProfiles, eq(boardMembers.userId, userProfiles.userId))
        .where(eq(boardMembers.boardId, boardId)),
      this.db
        .select({ id: boardFavorites.id })
        .from(boardFavorites)
        .where(and(eq(boardFavorites.boardId, boardId), eq(boardFavorites.userId, auth.userId)))
        .limit(1),
      this.db.select().from(boardViews).where(eq(boardViews.boardId, boardId)).orderBy(asc(boardViews.position)),
      this.ctx.canEdit(auth, boardId),
      this.ctx.isBoardManager(auth, boardId),
    ]);

    const itemIds = itemRows.map((i) => i.id);
    const [valueRows, updateCounts] = await Promise.all([
      itemIds.length ? this.db.select().from(columnValues).where(inArray(columnValues.itemId, itemIds)) : Promise.resolve([]),
      itemIds.length
        ? this.db
            .select({ itemId: updates.itemId, n: count() })
            .from(updates)
            .where(inArray(updates.itemId, itemIds))
            .groupBy(updates.itemId)
        : Promise.resolve([] as Array<{ itemId: string | null; n: number }>),
    ]);

    const valuesByItem = new Map<string, Record<string, unknown>>();
    for (const v of valueRows) {
      const bag = valuesByItem.get(v.itemId) ?? {};
      bag[v.columnId] = v.value;
      valuesByItem.set(v.itemId, bag);
    }
    const updatesByItem = new Map<string, number>();
    for (const u of updateCounts) if (u.itemId) updatesByItem.set(u.itemId, Number(u.n));

    // Subitems nest under their parent; an orphaned subitem (parent archived
    // separately) is simply not shown.
    const subitemsByParent = new Map<string, typeof itemRows>();
    for (const row of itemRows) {
      if (!row.parentItemId) continue;
      const list = subitemsByParent.get(row.parentItemId) ?? [];
      list.push(row);
      subitemsByParent.set(row.parentItemId, list);
    }
    const present = (row: (typeof itemRows)[number]) =>
      presentItem(
        row,
        valuesByItem.get(row.id) ?? {},
        updatesByItem.get(row.id) ?? 0,
        (subitemsByParent.get(row.id) ?? []).map((s) => presentItem(s, valuesByItem.get(s.id) ?? {}, updatesByItem.get(s.id) ?? 0)),
      );

    return {
      id: board.id,
      name: board.name,
      description: board.description,
      type: board.type,
      workspace: { id: board.workspaceId, name: board.workspaceName },
      isFavorite: favorite.length > 0,
      columns: cols.map(presentColumn),
      groups: groupRows.map((g) =>
        presentGroup(
          g,
          itemRows.filter((i) => i.groupId === g.id && !i.parentItemId).map(present),
        ),
      ),
      members: memberRows,
      views: viewRows.map(presentView),
      me: { userId: auth.userId, canEdit, canManage },
    };
  }

  async visit(auth: AuthContext, boardId: string): Promise<void> {
    await this.ctx.visibleBoard(auth, boardId);
    await this.db
      .insert(recentVisits)
      .values({ boardId, userId: auth.userId })
      .onConflictDoUpdate({ target: [recentVisits.boardId, recentVisits.userId], set: { visitedAt: new Date() } });
  }

  async toggleFavorite(auth: AuthContext, boardId: string): Promise<{ isFavorite: boolean }> {
    await this.ctx.visibleBoard(auth, boardId);
    const [existing] = await this.db
      .select({ id: boardFavorites.id })
      .from(boardFavorites)
      .where(and(eq(boardFavorites.boardId, boardId), eq(boardFavorites.userId, auth.userId)))
      .limit(1);
    if (existing) {
      await this.db.delete(boardFavorites).where(eq(boardFavorites.id, existing.id));
      return { isFavorite: false };
    }
    await this.db.insert(boardFavorites).values({ boardId, userId: auth.userId });
    return { isFavorite: true };
  }

  async listWorkspaces(auth: AuthContext) {
    const wsRows = await this.db
      .select()
      .from(workspaces)
      .where(eq(workspaces.accountId, auth.accountId))
      .orderBy(asc(workspaces.createdAt));
    const boardRows = await this.db
      .select({
        id: boards.id,
        name: boards.name,
        workspaceId: boards.workspaceId,
        type: boards.type,
        updatedAt: boards.updatedAt,
      })
      .from(boards)
      .where(and(eq(boards.accountId, auth.accountId), boardIsLive(), this.boardAccess.visibleTo(auth)))
      .orderBy(desc(boards.updatedAt));
    const favRows = await this.db
      .select({ boardId: boardFavorites.boardId })
      .from(boardFavorites)
      .where(eq(boardFavorites.userId, auth.userId));
    const favs = new Set(favRows.map((f) => f.boardId));

    return wsRows.map((ws) => ({
      id: ws.id,
      name: ws.name,
      boards: boardRows
        .filter((b) => b.workspaceId === ws.id)
        .map((b) => ({
          id: b.id,
          name: b.name,
          type: b.type,
          updatedAt: b.updatedAt.toISOString(),
          isFavorite: favs.has(b.id),
        })),
    }));
  }
}
