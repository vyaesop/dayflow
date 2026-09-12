import { ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, eq } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardIsLive, itemIsLive } from '../../db/live';
import { boardMembers, boards, columns, groups, items } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardAccessService } from './board-access.service';

export interface BoardRow {
  id: string;
  accountId: string;
  workspaceId: string;
  name: string;
  type: 'main' | 'shareable' | 'private';
  archivedAt: Date | null;
  trashedAt: Date | null;
}

export interface ItemRow {
  id: string;
  boardId: string;
  groupId: string;
  name: string;
  position: number;
  serial: number;
  parentItemId: string | null;
  archivedAt: Date | null;
  trashedAt: Date | null;
}

export type ColumnRow = typeof columns.$inferSelect;
export type GroupRow = typeof groups.$inferSelect;

/**
 * Resolves boards, groups, items and columns for write paths with every check
 * applied in one place: tenancy, board visibility, live (not archived/trashed),
 * and the caller's ability to edit. Shared by the boards, items, views and
 * activity modules so the rules cannot drift between them.
 */
@Injectable()
export class BoardContextService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly boardAccess: BoardAccessService,
  ) {}

  /** Viewers and guests never write. */
  assertEditorRole(auth: AuthContext): void {
    if (auth.role === 'viewer' || auth.role === 'guest') {
      throw new ForbiddenException('Your role cannot modify boards');
    }
  }

  /** A visible board in the caller's account, live unless `includeInactive`. */
  async visibleBoard(auth: AuthContext, boardId: string, options?: { includeInactive?: boolean }): Promise<BoardRow> {
    const [board] = await this.db
      .select({
        id: boards.id,
        accountId: boards.accountId,
        workspaceId: boards.workspaceId,
        name: boards.name,
        type: boards.type,
        archivedAt: boards.archivedAt,
        trashedAt: boards.trashedAt,
      })
      .from(boards)
      .where(
        and(
          eq(boards.id, boardId),
          eq(boards.accountId, auth.accountId),
          options?.includeInactive ? undefined : boardIsLive(),
          this.boardAccess.visibleTo(auth),
        ),
      )
      .limit(1);
    if (!board) throw new NotFoundException('Board not found');
    return board;
  }

  /** Visible + live + editable by the caller. */
  async writableBoard(auth: AuthContext, boardId: string, options?: { includeInactive?: boolean }): Promise<BoardRow> {
    const board = await this.visibleBoard(auth, boardId, options);
    this.assertEditorRole(auth);
    await this.boardAccess.assertBoardEditable(auth, boardId);
    return board;
  }

  /** Board owners and account admins. */
  async isBoardManager(auth: AuthContext, boardId: string): Promise<boolean> {
    if (auth.role === 'admin') return true;
    const [membership] = await this.db
      .select({ role: boardMembers.role })
      .from(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, auth.userId)))
      .limit(1);
    return membership?.role === 'owner';
  }

  async canEdit(auth: AuthContext, boardId: string): Promise<boolean> {
    if (auth.role === 'viewer' || auth.role === 'guest') return false;
    if (auth.role === 'admin') return true;
    const [membership] = await this.db
      .select({ role: boardMembers.role })
      .from(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, auth.userId)))
      .limit(1);
    return membership?.role !== 'viewer';
  }

  async writableGroup(auth: AuthContext, groupId: string): Promise<GroupRow> {
    const [row] = await this.db
      .select({ group: groups })
      .from(groups)
      .innerJoin(boards, eq(groups.boardId, boards.id))
      .where(
        and(
          eq(groups.id, groupId),
          eq(boards.accountId, auth.accountId),
          boardIsLive(),
          this.boardAccess.visibleTo(auth),
        ),
      )
      .limit(1);
    if (!row) throw new NotFoundException('Group not found');
    this.assertEditorRole(auth);
    await this.boardAccess.assertBoardEditable(auth, row.group.boardId);
    return row.group;
  }

  /**
   * An item the caller may modify. Live by default; `includeInactive` admits
   * archived/trashed items (restore, permanent delete), while the board itself
   * must always be live.
   */
  async writableItem(auth: AuthContext, itemId: string, options?: { includeInactive?: boolean }): Promise<ItemRow> {
    const row = await this.visibleItem(auth, itemId, options);
    this.assertEditorRole(auth);
    await this.boardAccess.assertBoardEditable(auth, row.boardId);
    return row;
  }

  async visibleItem(auth: AuthContext, itemId: string, options?: { includeInactive?: boolean }): Promise<ItemRow> {
    const [row] = await this.db
      .select({
        id: items.id,
        boardId: items.boardId,
        groupId: items.groupId,
        name: items.name,
        position: items.position,
        serial: items.serial,
        parentItemId: items.parentItemId,
        archivedAt: items.archivedAt,
        trashedAt: items.trashedAt,
      })
      .from(items)
      .innerJoin(boards, eq(items.boardId, boards.id))
      .where(
        and(
          eq(items.id, itemId),
          eq(boards.accountId, auth.accountId),
          options?.includeInactive ? undefined : itemIsLive(),
          boardIsLive(),
          this.boardAccess.visibleTo(auth),
        ),
      )
      .limit(1);
    if (!row) throw new NotFoundException('Item not found');
    return row;
  }

  async writableColumn(auth: AuthContext, columnId: string): Promise<ColumnRow> {
    const [row] = await this.db
      .select({ column: columns })
      .from(columns)
      .innerJoin(boards, eq(columns.boardId, boards.id))
      .where(
        and(
          eq(columns.id, columnId),
          eq(boards.accountId, auth.accountId),
          boardIsLive(),
          this.boardAccess.visibleTo(auth),
        ),
      )
      .limit(1);
    if (!row) throw new NotFoundException('Column not found');
    this.assertEditorRole(auth);
    await this.boardAccess.assertBoardEditable(auth, row.column.boardId);
    return row.column;
  }
}
