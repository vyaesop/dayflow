import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, desc, eq, inArray, isNull } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import {
  boardFavorites,
  boardMembers,
  boards,
  columns,
  columnValues,
  groups,
  items,
  recentVisits,
  updates,
  userProfiles,
  workspaces,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

export interface BoardPayload {
  id: string;
  name: string;
  description: string | null;
  type: string;
  workspace: { id: string; name: string };
  isFavorite: boolean;
  columns: Array<{ id: string; type: string; title: string; settings: unknown; position: number; width: number | null }>;
  groups: Array<{
    id: string;
    title: string;
    color: string;
    position: number;
    collapsed: boolean;
    items: Array<{
      id: string;
      name: string;
      position: number;
      updatesCount: number;
      values: Record<string, unknown>;
    }>;
  }>;
  members: Array<{ userId: string; fullName: string; avatarUrl: string | null; role: string }>;
}

@Injectable()
export class BoardsService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

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
      .where(and(eq(boards.id, boardId), eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)))
      .limit(1);
    if (!board) throw new NotFoundException('Board not found');

    const [cols, groupRows, itemRows, memberRows, favorite] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, boardId)).orderBy(asc(columns.position)),
      this.db.select().from(groups).where(eq(groups.boardId, boardId)).orderBy(asc(groups.position)),
      this.db
        .select()
        .from(items)
        .where(and(eq(items.boardId, boardId), isNull(items.archivedAt)))
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
    ]);

    const itemIds = itemRows.map((i) => i.id);
    const [valueRows, updateCounts] = await Promise.all([
      itemIds.length
        ? this.db.select().from(columnValues).where(inArray(columnValues.itemId, itemIds))
        : Promise.resolve([]),
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
    for (const u of updateCounts) {
      if (u.itemId) updatesByItem.set(u.itemId, Number(u.n));
    }

    return {
      id: board.id,
      name: board.name,
      description: board.description,
      type: board.type,
      workspace: { id: board.workspaceId, name: board.workspaceName },
      isFavorite: favorite.length > 0,
      columns: cols.map((c) => ({
        id: c.id,
        type: c.type,
        title: c.title,
        settings: c.settings,
        position: c.position,
        width: c.width,
      })),
      groups: groupRows.map((g) => ({
        id: g.id,
        title: g.title,
        color: g.color,
        position: g.position,
        collapsed: g.collapsed,
        items: itemRows
          .filter((i) => i.groupId === g.id)
          .map((i) => ({
            id: i.id,
            name: i.name,
            position: i.position,
            updatesCount: updatesByItem.get(i.id) ?? 0,
            values: valuesByItem.get(i.id) ?? {},
          })),
      })),
      members: memberRows,
    };
  }

  async visit(auth: AuthContext, boardId: string): Promise<void> {
    await this.assertBoardInAccount(auth, boardId);
    await this.db
      .insert(recentVisits)
      .values({ boardId, userId: auth.userId })
      .onConflictDoUpdate({
        target: [recentVisits.boardId, recentVisits.userId],
        set: { visitedAt: new Date() },
      });
  }

  async toggleFavorite(auth: AuthContext, boardId: string): Promise<{ isFavorite: boolean }> {
    await this.assertBoardInAccount(auth, boardId);
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
        updatedAt: boards.updatedAt,
      })
      .from(boards)
      .where(and(eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)))
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
          updatedAt: b.updatedAt.toISOString(),
          isFavorite: favs.has(b.id),
        })),
    }));
  }

  private async assertBoardInAccount(auth: AuthContext, boardId: string): Promise<void> {
    const [board] = await this.db
      .select({ id: boards.id })
      .from(boards)
      .where(and(eq(boards.id, boardId), eq(boards.accountId, auth.accountId)))
      .limit(1);
    if (!board) throw new NotFoundException('Board not found');
  }
}
