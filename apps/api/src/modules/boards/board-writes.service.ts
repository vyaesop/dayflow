import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, eq, inArray, isNull } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import {
  accountMembers,
  activityLog,
  boardMembers,
  boards,
  boardViews,
  columns,
  columnValues,
  groups,
  items,
  notifications,
  workspaces,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import {
  assignedUserIds,
  defaultSettingsFor,
  normalizeColumnValue,
  type ColumnSettings,
} from './column-values';
import { neighboursFor, needsRebalance, positionAtEnd, positionBetween, rebalanced } from './positioning';
import { findTemplate } from './templates.catalog';
import { RealtimeGateway, type BoardEvent } from '../realtime/realtime.gateway';

const GROUP_COLORS = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo'];

/** Column types a client may create. Mirrors the `column_type` enum. */
const CREATABLE_COLUMN_TYPES = [
  'status',
  'people',
  'date',
  'text',
  'number',
  'tags',
  'dropdown',
  'checkbox',
  'timeline',
  'vote',
  'location',
  'link',
] as const;

export interface ItemPayload {
  id: string;
  name: string;
  groupId: string;
  position: number;
  updatesCount: number;
  values: Record<string, unknown>;
}

/**
 * All mutating board operations. Reads live in BoardsService; keeping writes
 * separate keeps the transactional/authorisation logic in one place.
 */
@Injectable()
export class BoardWritesService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly realtime: RealtimeGateway,
  ) {}

  /**
   * Fans an event out to other viewers of the board. The actor is excluded —
   * their own client already applied the change optimistically.
   */
  private emit(auth: AuthContext, event: BoardEvent): void {
    this.realtime.publish(event, { accountId: auth.accountId, exceptUserId: auth.userId });
  }

  // ---------------------------------------------------------------- workspaces

  async createWorkspace(auth: AuthContext, name: string) {
    const [workspace] = await this.db
      .insert(workspaces)
      .values({ accountId: auth.accountId, name: name.trim(), createdByUserId: auth.userId })
      .returning();
    return { id: workspace.id, name: workspace.name, boards: [] };
  }

  // -------------------------------------------------------------------- boards

  /** Creates a board from a template blueprint (defaults to `blank`). */
  async createBoard(
    auth: AuthContext,
    dto: {
      name: string;
      workspaceId?: string;
      description?: string;
      type?: 'main' | 'shareable' | 'private';
      template?: string;
    },
  ) {
    const workspaceId = dto.workspaceId ?? (await this.defaultWorkspaceId(auth));
    await this.assertWorkspaceInAccount(auth, workspaceId);

    const templateKey = dto.template ?? 'blank';
    const template = findTemplate(templateKey);
    if (!template) throw new BadRequestException(`Unknown template "${templateKey}"`);

    return this.db.transaction(async (tx) => {
      const [board] = await tx
        .insert(boards)
        .values({
          accountId: auth.accountId,
          workspaceId,
          name: dto.name.trim(),
          description: dto.description?.trim() || null,
          type: dto.type ?? 'main',
          createdByUserId: auth.userId,
        })
        .returning();

      await tx.insert(boardMembers).values({ boardId: board.id, userId: auth.userId, role: 'owner' });
      await tx.insert(boardViews).values({
        boardId: board.id,
        type: 'table',
        name: 'Main Table',
        isDefault: true,
        position: 1,
        createdByUserId: auth.userId,
      });

      // Columns, keyed by title so template cell values can find them.
      const columnIdByTitle = new Map<string, { id: string; type: string; settings: ColumnSettings }>();
      for (const [index, spec] of template.columns.entries()) {
        const [column] = await tx
          .insert(columns)
          .values({
            boardId: board.id,
            type: spec.type as typeof columns.$inferInsert.type,
            title: spec.title,
            settings: spec.settings ?? defaultSettingsFor(spec.type),
            position: index + 1,
          })
          .returning({ id: columns.id, settings: columns.settings });
        columnIdByTitle.set(spec.title, {
          id: column.id,
          type: spec.type,
          settings: (column.settings ?? {}) as ColumnSettings,
        });
      }

      const groupIds: string[] = [];
      for (const [index, spec] of template.groups.entries()) {
        const [group] = await tx
          .insert(groups)
          .values({ boardId: board.id, title: spec.title, color: spec.color, position: index + 1 })
          .returning({ id: groups.id });
        groupIds.push(group.id);
      }

      for (const [index, spec] of template.items.entries()) {
        const groupId = groupIds[spec.group] ?? groupIds[0];
        const [item] = await tx
          .insert(items)
          .values({
            boardId: board.id,
            groupId,
            name: spec.name,
            position: index + 1,
            createdByUserId: auth.userId,
          })
          .returning({ id: items.id });

        for (const [columnTitle, raw] of Object.entries(spec.cells ?? {})) {
          const column = columnIdByTitle.get(columnTitle);
          if (!column) continue;
          const value = normalizeColumnValue(column.type, column.settings, raw);
          if (value === null) continue;
          await tx.insert(columnValues).values({
            itemId: item.id,
            columnId: column.id,
            value,
            updatedByUserId: auth.userId,
          });
        }
      }

      await tx.insert(activityLog).values({
        boardId: board.id,
        actorUserId: auth.userId,
        event: 'board_created',
        payload: { name: board.name, template: templateKey },
      });

      return { id: board.id, name: board.name, workspaceId };
    });
  }

  async updateBoard(auth: AuthContext, boardId: string, dto: { name?: string; description?: string }) {
    await this.assertBoardWritable(auth, boardId);
    const patch: Record<string, unknown> = { updatedAt: new Date() };
    if (dto.name !== undefined) patch.name = dto.name.trim();
    if (dto.description !== undefined) patch.description = dto.description.trim() || null;

    const [board] = await this.db.update(boards).set(patch).where(eq(boards.id, boardId)).returning();
    if (dto.name !== undefined) {
      await this.db.insert(activityLog).values({
        boardId,
        actorUserId: auth.userId,
        event: 'board_renamed',
        payload: { name: board.name },
      });
    }
    this.emit(auth, { type: 'board.updated', boardId, patch: dto });
    return { id: board.id, name: board.name, description: board.description };
  }

  /** Soft-archives the board; it disappears from lists but rows are retained. */
  async archiveBoard(auth: AuthContext, boardId: string) {
    await this.assertBoardWritable(auth, boardId);
    await this.db.update(boards).set({ archivedAt: new Date() }).where(eq(boards.id, boardId));
    return { ok: true };
  }

  // -------------------------------------------------------------------- groups

  async createGroup(auth: AuthContext, boardId: string, dto: { title: string; color?: string }) {
    await this.assertBoardWritable(auth, boardId);
    const existing = await this.db
      .select({ id: groups.id, position: groups.position })
      .from(groups)
      .where(eq(groups.boardId, boardId));

    const color = dto.color ?? GROUP_COLORS[existing.length % GROUP_COLORS.length];
    if (!GROUP_COLORS.includes(color)) {
      throw new BadRequestException(`color must be one of: ${GROUP_COLORS.join(', ')}`);
    }

    const [group] = await this.db
      .insert(groups)
      .values({
        boardId,
        title: dto.title.trim(),
        color,
        position: positionAtEnd(existing.map((g) => g.position)),
      })
      .returning();

    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'group_created',
      payload: { groupId: group.id, title: group.title },
    });
    const payload = this.presentGroup(group);
    this.emit(auth, { type: 'group.created', boardId, group: payload });
    return payload;
  }

  async updateGroup(
    auth: AuthContext,
    groupId: string,
    dto: { title?: string; color?: string; collapsed?: boolean },
  ) {
    const group = await this.groupInAccount(auth, groupId);
    if (dto.color !== undefined && !GROUP_COLORS.includes(dto.color)) {
      throw new BadRequestException(`color must be one of: ${GROUP_COLORS.join(', ')}`);
    }

    const patch: Record<string, unknown> = {};
    if (dto.title !== undefined) patch.title = dto.title.trim();
    if (dto.color !== undefined) patch.color = dto.color;
    if (dto.collapsed !== undefined) patch.collapsed = dto.collapsed;
    if (Object.keys(patch).length === 0) return this.presentGroup(group);

    const [updated] = await this.db.update(groups).set(patch).where(eq(groups.id, groupId)).returning();
    if (dto.title !== undefined) {
      await this.db.insert(activityLog).values({
        boardId: group.boardId,
        actorUserId: auth.userId,
        event: 'group_renamed',
        payload: { groupId, title: updated.title },
      });
    }
    this.emit(auth, { type: 'group.updated', boardId: group.boardId, groupId, patch: dto });
    return this.presentGroup(updated);
  }

  /** Deletes a group and, by cascade, its items. Refuses the last group. */
  async deleteGroup(auth: AuthContext, groupId: string) {
    const group = await this.groupInAccount(auth, groupId);
    const siblings = await this.db.select({ id: groups.id }).from(groups).where(eq(groups.boardId, group.boardId));
    if (siblings.length <= 1) {
      throw new BadRequestException('A board must keep at least one group');
    }

    await this.db.delete(groups).where(eq(groups.id, groupId));
    await this.db.insert(activityLog).values({
      boardId: group.boardId,
      actorUserId: auth.userId,
      event: 'group_deleted',
      payload: { groupId, title: group.title },
    });
    this.emit(auth, { type: 'group.deleted', boardId: group.boardId, groupId });
    return { ok: true };
  }

  async moveGroup(auth: AuthContext, groupId: string, afterGroupId: string | null) {
    const group = await this.groupInAccount(auth, groupId);
    const ordered = await this.db
      .select({ id: groups.id, position: groups.position })
      .from(groups)
      .where(eq(groups.boardId, group.boardId))
      .orderBy(asc(groups.position));

    const { before, after } = neighboursFor(ordered, afterGroupId, groupId);
    if (needsRebalance(before, after)) {
      await this.rebalanceGroups(group.boardId, groupId, afterGroupId);
    } else {
      await this.db.update(groups).set({ position: positionBetween(before, after) }).where(eq(groups.id, groupId));
    }
    return { ok: true };
  }

  // --------------------------------------------------------------------- items

  async createItem(auth: AuthContext, boardId: string, dto: { groupId: string; name: string; afterItemId?: string | null }) {
    await this.assertBoardWritable(auth, boardId);
    const [group] = await this.db
      .select({ id: groups.id })
      .from(groups)
      .where(and(eq(groups.id, dto.groupId), eq(groups.boardId, boardId)))
      .limit(1);
    if (!group) throw new NotFoundException('Group not found on this board');

    const ordered = await this.db
      .select({ id: items.id, position: items.position })
      .from(items)
      .where(and(eq(items.groupId, dto.groupId), isNull(items.archivedAt)))
      .orderBy(asc(items.position));

    // Undefined afterItemId means append; explicit null means put it on top.
    const position =
      dto.afterItemId === undefined
        ? positionAtEnd(ordered.map((i) => i.position))
        : (() => {
            const { before, after } = neighboursFor(ordered, dto.afterItemId);
            return positionBetween(before, after);
          })();

    const [item] = await this.db
      .insert(items)
      .values({
        boardId,
        groupId: dto.groupId,
        name: dto.name.trim(),
        position,
        createdByUserId: auth.userId,
      })
      .returning();

    await this.db.insert(activityLog).values({
      boardId,
      itemId: item.id,
      actorUserId: auth.userId,
      event: 'item_created',
      payload: { name: item.name, groupId: dto.groupId },
    });
    await this.touchBoard(boardId);

    const payload: ItemPayload = {
      id: item.id,
      name: item.name,
      groupId: item.groupId,
      position: item.position,
      updatesCount: 0,
      values: {},
    };
    this.emit(auth, { type: 'item.created', boardId, groupId: dto.groupId, item: payload });
    return payload;
  }

  async renameItem(auth: AuthContext, itemId: string, name: string) {
    const item = await this.itemInAccount(auth, itemId);
    const [updated] = await this.db
      .update(items)
      .set({ name: name.trim(), updatedAt: new Date() })
      .where(eq(items.id, itemId))
      .returning();

    await this.db.insert(activityLog).values({
      boardId: item.boardId,
      itemId,
      actorUserId: auth.userId,
      event: 'item_renamed',
      payload: { from: item.name, to: updated.name },
    });
    await this.touchBoard(item.boardId);
    this.emit(auth, {
      type: 'item.updated',
      boardId: item.boardId,
      itemId,
      patch: { name: updated.name },
    });
    return { id: updated.id, name: updated.name };
  }

  /** Moves an item within or between groups on the same board. */
  async moveItem(auth: AuthContext, itemId: string, dto: { groupId?: string; afterItemId?: string | null }) {
    const item = await this.itemInAccount(auth, itemId);
    const targetGroupId = dto.groupId ?? item.groupId;

    if (targetGroupId !== item.groupId) {
      const [group] = await this.db
        .select({ id: groups.id })
        .from(groups)
        .where(and(eq(groups.id, targetGroupId), eq(groups.boardId, item.boardId)))
        .limit(1);
      if (!group) throw new NotFoundException('Target group is not on this board');
    }

    const ordered = await this.db
      .select({ id: items.id, position: items.position })
      .from(items)
      .where(and(eq(items.groupId, targetGroupId), isNull(items.archivedAt)))
      .orderBy(asc(items.position));

    const afterItemId = dto.afterItemId === undefined ? null : dto.afterItemId;
    const { before, after } = neighboursFor(ordered, afterItemId, itemId);

    if (needsRebalance(before, after)) {
      await this.rebalanceItems(targetGroupId, itemId, afterItemId);
      await this.db.update(items).set({ groupId: targetGroupId, updatedAt: new Date() }).where(eq(items.id, itemId));
    } else {
      await this.db
        .update(items)
        .set({ groupId: targetGroupId, position: positionBetween(before, after), updatedAt: new Date() })
        .where(eq(items.id, itemId));
    }

    if (targetGroupId !== item.groupId) {
      await this.db.insert(activityLog).values({
        boardId: item.boardId,
        itemId,
        actorUserId: auth.userId,
        event: 'item_moved',
        payload: { from: item.groupId, to: targetGroupId },
      });
    }
    await this.touchBoard(item.boardId);
    this.emit(auth, { type: 'item.moved', boardId: item.boardId, itemId, groupId: targetGroupId });
    return { ok: true };
  }

  async archiveItem(auth: AuthContext, itemId: string) {
    const item = await this.itemInAccount(auth, itemId);
    await this.db.update(items).set({ archivedAt: new Date() }).where(eq(items.id, itemId));
    await this.db.insert(activityLog).values({
      boardId: item.boardId,
      itemId,
      actorUserId: auth.userId,
      event: 'item_archived',
      payload: { name: item.name },
    });
    await this.touchBoard(item.boardId);
    this.emit(auth, { type: 'item.deleted', boardId: item.boardId, itemId });
    return { ok: true };
  }

  /** Copies an item and its cell values directly below the original. */
  async duplicateItem(auth: AuthContext, itemId: string): Promise<ItemPayload> {
    const item = await this.itemInAccount(auth, itemId);
    const ordered = await this.db
      .select({ id: items.id, position: items.position })
      .from(items)
      .where(and(eq(items.groupId, item.groupId), isNull(items.archivedAt)))
      .orderBy(asc(items.position));
    const { before, after } = neighboursFor(ordered, itemId);

    const sourceValues = await this.db.select().from(columnValues).where(eq(columnValues.itemId, itemId));

    return this.db.transaction(async (tx) => {
      const [copy] = await tx
        .insert(items)
        .values({
          boardId: item.boardId,
          groupId: item.groupId,
          name: `${item.name} (copy)`,
          position: positionBetween(before, after),
          createdByUserId: auth.userId,
        })
        .returning();

      if (sourceValues.length) {
        await tx.insert(columnValues).values(
          sourceValues.map((v) => ({
            itemId: copy.id,
            columnId: v.columnId,
            value: v.value,
            updatedByUserId: auth.userId,
          })),
        );
      }
      await tx.insert(activityLog).values({
        boardId: item.boardId,
        itemId: copy.id,
        actorUserId: auth.userId,
        event: 'item_duplicated',
        payload: { sourceItemId: itemId },
      });

      const values: Record<string, unknown> = {};
      for (const v of sourceValues) values[v.columnId] = v.value;
      const payload: ItemPayload = {
        id: copy.id,
        name: copy.name,
        groupId: copy.groupId,
        position: copy.position,
        updatesCount: 0,
        values,
      };
      this.emit(auth, {
        type: 'item.created',
        boardId: item.boardId,
        groupId: copy.groupId,
        item: payload,
      });
      return payload;
    });
  }

  // ------------------------------------------------------------- cell values

  /**
   * Sets or clears one cell. The value shape is validated against the column
   * type, and assigning a person notifies them.
   */
  async setCellValue(auth: AuthContext, itemId: string, columnId: string, raw: unknown) {
    const item = await this.itemInAccount(auth, itemId);
    const [column] = await this.db
      .select()
      .from(columns)
      .where(and(eq(columns.id, columnId), eq(columns.boardId, item.boardId)))
      .limit(1);
    if (!column) throw new NotFoundException('Column not found on this board');

    const normalized = normalizeColumnValue(column.type, (column.settings ?? {}) as ColumnSettings, raw);

    const [previous] = await this.db
      .select({ value: columnValues.value })
      .from(columnValues)
      .where(and(eq(columnValues.itemId, itemId), eq(columnValues.columnId, columnId)))
      .limit(1);

    if (normalized === null) {
      await this.db
        .delete(columnValues)
        .where(and(eq(columnValues.itemId, itemId), eq(columnValues.columnId, columnId)));
    } else {
      await this.db
        .insert(columnValues)
        .values({ itemId, columnId, value: normalized, updatedByUserId: auth.userId })
        .onConflictDoUpdate({
          target: [columnValues.itemId, columnValues.columnId],
          set: { value: normalized, updatedByUserId: auth.userId, updatedAt: new Date() },
        });
    }

    await this.db.insert(activityLog).values({
      boardId: item.boardId,
      itemId,
      actorUserId: auth.userId,
      event: 'column_value_changed',
      payload: { columnId, from: previous?.value ?? null, to: normalized },
    });
    await this.touchBoard(item.boardId);
    await this.notifyNewAssignees(auth, {
      boardId: item.boardId,
      itemId,
      itemName: item.name,
      columnType: column.type,
      previous: (previous?.value ?? null) as Record<string, unknown> | null,
      next: normalized,
    });

    this.emit(auth, {
      type: 'cell.changed',
      boardId: item.boardId,
      itemId,
      columnId,
      value: normalized,
    });
    return { columnId, value: normalized };
  }

  // ------------------------------------------------------------------ columns

  async createColumn(
    auth: AuthContext,
    boardId: string,
    dto: { type: string; title: string; settings?: Record<string, unknown> },
  ) {
    await this.assertBoardWritable(auth, boardId);
    if (!CREATABLE_COLUMN_TYPES.includes(dto.type as (typeof CREATABLE_COLUMN_TYPES)[number])) {
      throw new BadRequestException(`type must be one of: ${CREATABLE_COLUMN_TYPES.join(', ')}`);
    }

    const existing = await this.db
      .select({ position: columns.position })
      .from(columns)
      .where(eq(columns.boardId, boardId));

    const [column] = await this.db
      .insert(columns)
      .values({
        boardId,
        type: dto.type as (typeof CREATABLE_COLUMN_TYPES)[number],
        title: dto.title.trim(),
        settings: dto.settings ?? defaultSettingsFor(dto.type),
        position: positionAtEnd(existing.map((c) => c.position)),
      })
      .returning();

    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'column_created',
      payload: { columnId: column.id, type: column.type, title: column.title },
    });
    const payload = this.presentColumn(column);
    this.emit(auth, { type: 'column.created', boardId, column: payload });
    return payload;
  }

  async updateColumn(
    auth: AuthContext,
    columnId: string,
    dto: { title?: string; settings?: Record<string, unknown>; width?: number },
  ) {
    const column = await this.columnInAccount(auth, columnId);
    const patch: Record<string, unknown> = {};
    if (dto.title !== undefined) patch.title = dto.title.trim();
    if (dto.settings !== undefined) patch.settings = dto.settings;
    if (dto.width !== undefined) patch.width = dto.width;
    if (Object.keys(patch).length === 0) return this.presentColumn(column);

    const [updated] = await this.db.update(columns).set(patch).where(eq(columns.id, columnId)).returning();
    if (dto.title !== undefined) {
      await this.db.insert(activityLog).values({
        boardId: column.boardId,
        actorUserId: auth.userId,
        event: 'column_renamed',
        payload: { columnId, title: updated.title },
      });
    }
    this.emit(auth, { type: 'column.updated', boardId: column.boardId, columnId, patch: dto });
    return this.presentColumn(updated);
  }

  async deleteColumn(auth: AuthContext, columnId: string) {
    const column = await this.columnInAccount(auth, columnId);
    await this.db.delete(columns).where(eq(columns.id, columnId));
    await this.db.insert(activityLog).values({
      boardId: column.boardId,
      actorUserId: auth.userId,
      event: 'column_deleted',
      payload: { columnId, title: column.title },
    });
    this.emit(auth, { type: 'column.deleted', boardId: column.boardId, columnId });
    return { ok: true };
  }

  // ------------------------------------------------------------------ helpers

  private presentGroup(group: typeof groups.$inferSelect) {
    return {
      id: group.id,
      title: group.title,
      color: group.color,
      position: group.position,
      collapsed: group.collapsed,
      items: [] as ItemPayload[],
    };
  }

  private presentColumn(column: typeof columns.$inferSelect) {
    return {
      id: column.id,
      type: column.type,
      title: column.title,
      settings: column.settings,
      position: column.position,
      width: column.width,
    };
  }

  /** Keeps `boards.updatedAt` meaningful — it orders the board lists. */
  private async touchBoard(boardId: string): Promise<void> {
    await this.db.update(boards).set({ updatedAt: new Date() }).where(eq(boards.id, boardId));
  }

  private async defaultWorkspaceId(auth: AuthContext): Promise<string> {
    const [workspace] = await this.db
      .select({ id: workspaces.id })
      .from(workspaces)
      .where(eq(workspaces.accountId, auth.accountId))
      .orderBy(asc(workspaces.createdAt))
      .limit(1);
    if (!workspace) throw new NotFoundException('This account has no workspace yet');
    return workspace.id;
  }

  private async assertWorkspaceInAccount(auth: AuthContext, workspaceId: string): Promise<void> {
    const [workspace] = await this.db
      .select({ id: workspaces.id })
      .from(workspaces)
      .where(and(eq(workspaces.id, workspaceId), eq(workspaces.accountId, auth.accountId)))
      .limit(1);
    if (!workspace) throw new NotFoundException('Workspace not found');
  }

  /** Board must be in the caller's account, not archived, and the caller not a viewer. */
  private async assertBoardWritable(auth: AuthContext, boardId: string): Promise<void> {
    const [board] = await this.db
      .select({ id: boards.id })
      .from(boards)
      .where(and(eq(boards.id, boardId), eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)))
      .limit(1);
    if (!board) throw new NotFoundException('Board not found');
    if (auth.role === 'viewer' || auth.role === 'guest') {
      throw new ForbiddenException('Your role cannot modify boards');
    }
  }

  private async groupInAccount(auth: AuthContext, groupId: string) {
    const [row] = await this.db
      .select({
        id: groups.id,
        boardId: groups.boardId,
        title: groups.title,
        color: groups.color,
        position: groups.position,
        collapsed: groups.collapsed,
        createdAt: groups.createdAt,
      })
      .from(groups)
      .innerJoin(boards, eq(groups.boardId, boards.id))
      .where(and(eq(groups.id, groupId), eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)))
      .limit(1);
    if (!row) throw new NotFoundException('Group not found');
    if (auth.role === 'viewer' || auth.role === 'guest') {
      throw new ForbiddenException('Your role cannot modify boards');
    }
    return row;
  }

  private async itemInAccount(auth: AuthContext, itemId: string) {
    const [row] = await this.db
      .select({
        id: items.id,
        boardId: items.boardId,
        groupId: items.groupId,
        name: items.name,
        position: items.position,
      })
      .from(items)
      .innerJoin(boards, eq(items.boardId, boards.id))
      .where(
        and(
          eq(items.id, itemId),
          eq(boards.accountId, auth.accountId),
          isNull(items.archivedAt),
          isNull(boards.archivedAt),
        ),
      )
      .limit(1);
    if (!row) throw new NotFoundException('Item not found');
    if (auth.role === 'viewer' || auth.role === 'guest') {
      throw new ForbiddenException('Your role cannot modify boards');
    }
    return row;
  }

  private async columnInAccount(auth: AuthContext, columnId: string) {
    const [row] = await this.db
      .select({
        id: columns.id,
        boardId: columns.boardId,
        type: columns.type,
        title: columns.title,
        settings: columns.settings,
        position: columns.position,
        width: columns.width,
        createdAt: columns.createdAt,
      })
      .from(columns)
      .innerJoin(boards, eq(columns.boardId, boards.id))
      .where(and(eq(columns.id, columnId), eq(boards.accountId, auth.accountId), isNull(boards.archivedAt)))
      .limit(1);
    if (!row) throw new NotFoundException('Column not found');
    if (auth.role === 'viewer' || auth.role === 'guest') {
      throw new ForbiddenException('Your role cannot modify boards');
    }
    return row;
  }

  /** Notifies people newly added to a people cell (never the actor themselves). */
  private async notifyNewAssignees(
    auth: AuthContext,
    ctx: {
      boardId: string;
      itemId: string;
      itemName: string;
      columnType: string;
      previous: Record<string, unknown> | null;
      next: Record<string, unknown> | null;
    },
  ): Promise<void> {
    const was = new Set(assignedUserIds(ctx.columnType, ctx.previous));
    const added = assignedUserIds(ctx.columnType, ctx.next).filter((id) => !was.has(id) && id !== auth.userId);
    if (added.length === 0) return;

    // Only notify people who are actually in this account.
    const members = await this.db
      .select({ userId: accountMembers.userId })
      .from(accountMembers)
      .where(and(eq(accountMembers.accountId, auth.accountId), inArray(accountMembers.userId, added)));
    if (members.length === 0) return;

    const [board] = await this.db
      .select({ name: boards.name })
      .from(boards)
      .where(eq(boards.id, ctx.boardId))
      .limit(1);

    await this.db.insert(notifications).values(
      members.map((m) => ({
        accountId: auth.accountId,
        userId: m.userId,
        type: 'assigned' as const,
        actorUserId: auth.userId,
        payload: {
          boardId: ctx.boardId,
          boardName: board?.name ?? '',
          itemId: ctx.itemId,
          itemName: ctx.itemName,
        },
      })),
    );
  }

  /**
   * Renumbers a group's items evenly, placing `movedId` after `afterId`.
   * Only runs when midpoints have exhausted float precision.
   */
  private async rebalanceItems(groupId: string, movedId: string, afterId: string | null): Promise<void> {
    const ordered = await this.db
      .select({ id: items.id })
      .from(items)
      .where(and(eq(items.groupId, groupId), isNull(items.archivedAt)))
      .orderBy(asc(items.position));

    const ids = ordered.map((r) => r.id).filter((id) => id !== movedId);
    const insertAt = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    ids.splice(insertAt, 0, movedId);

    const positions = rebalanced(ids.length);
    await this.db.transaction(async (tx) => {
      for (const [index, id] of ids.entries()) {
        await tx.update(items).set({ position: positions[index] }).where(eq(items.id, id));
      }
    });
  }

  private async rebalanceGroups(boardId: string, movedId: string, afterId: string | null): Promise<void> {
    const ordered = await this.db
      .select({ id: groups.id })
      .from(groups)
      .where(eq(groups.boardId, boardId))
      .orderBy(asc(groups.position));

    const ids = ordered.map((r) => r.id).filter((id) => id !== movedId);
    const insertAt = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    ids.splice(insertAt, 0, movedId);

    const positions = rebalanced(ids.length);
    await this.db.transaction(async (tx) => {
      for (const [index, id] of ids.entries()) {
        await tx.update(groups).set({ position: positions[index] }).where(eq(groups.id, id));
      }
    });
  }
}
