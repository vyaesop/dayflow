import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, eq, inArray, isNull, sql } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { itemIsLive } from '../../db/live';
import {
  accountMembers,
  activityLog,
  boards,
  columns,
  columnValues,
  files,
  groups,
  items,
  updates,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardContextService, type ItemRow } from '../access/board-context.service';
import { NotifierService } from '../notifications/notifier.service';
import { RealtimeGateway, type BoardEvent } from '../realtime/realtime.gateway';
import { planColumnMapping, remapCellValue } from './board-transfer';
import { assignedUserIds, defaultSettingsFor, normalizeColumnValue, type ColumnSettings } from './column-values';
import { neighboursFor, needsRebalance, positionAtEnd, positionBetween, rebalanced } from './positioning';
import { presentItem, type ItemPayload } from './presenters';

type Executor = Database | Parameters<Parameters<Database['transaction']>[0]>[0];

export type BatchAction = 'archive' | 'trash' | 'restore' | 'duplicate' | 'move' | 'set_cell' | 'delete_permanent';

/** Default column set created with a board's first subitem, as on monday. */
const DEFAULT_SUBITEM_COLUMNS = [
  { type: 'status', title: 'Status' },
  { type: 'people', title: 'Owner' },
  { type: 'date', title: 'Date' },
] as const;

/**
 * Item-level writes: items and subitems, cells, archive/trash/restore,
 * duplicate, batch actions and moving items between boards.
 */
@Injectable()
export class ItemWritesService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly realtime: RealtimeGateway,
    private readonly notifier: NotifierService,
    private readonly ctx: BoardContextService,
  ) {}

  private emit(auth: AuthContext, event: BoardEvent): void {
    this.realtime.publish(event, { accountId: auth.accountId, exceptUserId: auth.userId });
  }

  // --------------------------------------------------------------------- items

  async createItem(
    auth: AuthContext,
    boardId: string,
    dto: { groupId: string; name: string; afterItemId?: string | null },
  ): Promise<ItemPayload> {
    await this.ctx.writableBoard(auth, boardId);
    const [group] = await this.db
      .select({ id: groups.id })
      .from(groups)
      .where(and(eq(groups.id, dto.groupId), eq(groups.boardId, boardId)))
      .limit(1);
    if (!group) throw new NotFoundException('Group not found on this board');

    const item = await this.db.transaction(async (tx) => {
      const ordered = await this.siblings(tx, { groupId: dto.groupId, parentItemId: null });
      const position =
        dto.afterItemId === undefined
          ? positionAtEnd(ordered.map((i) => i.position))
          : positionBetween(...pair(neighboursFor(ordered, dto.afterItemId)));
      const [row] = await tx
        .insert(items)
        .values({
          boardId,
          groupId: dto.groupId,
          name: dto.name.trim(),
          position,
          serial: await this.nextSerial(tx, boardId),
          createdByUserId: auth.userId,
          updatedByUserId: auth.userId,
        })
        .returning();
      await tx.insert(activityLog).values({
        boardId,
        itemId: row.id,
        actorUserId: auth.userId,
        event: 'item_created',
        payload: { name: row.name, groupId: dto.groupId },
      });
      return row;
    });

    await this.touchBoard(boardId);
    const payload = presentItem(item, {}, 0);
    this.emit(auth, { type: 'item.created', boardId, groupId: dto.groupId, item: payload });
    return payload;
  }

  /** Adds a subitem under `parentId`, creating the board's subitem columns on first use. */
  async createSubitem(auth: AuthContext, parentId: string, dto: { name: string; afterItemId?: string | null }): Promise<ItemPayload> {
    const parent = await this.ctx.writableItem(auth, parentId);
    if (parent.parentItemId) throw new BadRequestException('Subitems cannot have subitems of their own');

    const item = await this.db.transaction(async (tx) => {
      await this.ensureSubitemColumns(tx, parent.boardId);
      const ordered = await this.siblings(tx, { groupId: parent.groupId, parentItemId: parent.id });
      const position =
        dto.afterItemId === undefined
          ? positionAtEnd(ordered.map((i) => i.position))
          : positionBetween(...pair(neighboursFor(ordered, dto.afterItemId)));
      const [row] = await tx
        .insert(items)
        .values({
          boardId: parent.boardId,
          groupId: parent.groupId,
          parentItemId: parent.id,
          name: dto.name.trim(),
          position,
          serial: await this.nextSerial(tx, parent.boardId),
          createdByUserId: auth.userId,
          updatedByUserId: auth.userId,
        })
        .returning();
      await tx.insert(activityLog).values({
        boardId: parent.boardId,
        itemId: row.id,
        actorUserId: auth.userId,
        event: 'item_created',
        payload: { name: row.name, groupId: parent.groupId, parentItemId: parent.id, parentName: parent.name },
      });
      await tx.update(items).set({ updatedAt: new Date(), updatedByUserId: auth.userId }).where(eq(items.id, parent.id));
      return row;
    });

    await this.touchBoard(parent.boardId);
    const payload = presentItem(item, {}, 0);
    this.emit(auth, { type: 'item.created', boardId: parent.boardId, groupId: parent.groupId, item: payload });
    // Columns may have just been created; other viewers need the new column set.
    this.emit(auth, { type: 'board.updated', boardId: parent.boardId, patch: { subitemColumns: true } });
    return payload;
  }

  async renameItem(auth: AuthContext, itemId: string, name: string) {
    const item = await this.ctx.writableItem(auth, itemId);
    const [updated] = await this.db
      .update(items)
      .set({ name: name.trim(), updatedAt: new Date(), updatedByUserId: auth.userId })
      .where(eq(items.id, itemId))
      .returning();
    if (updated.name !== item.name) {
      await this.db.insert(activityLog).values({
        boardId: item.boardId,
        itemId,
        actorUserId: auth.userId,
        event: 'item_renamed',
        payload: { from: item.name, to: updated.name },
      });
    }
    await this.touchBoard(item.boardId);
    this.emit(auth, {
      type: 'item.updated',
      boardId: item.boardId,
      itemId,
      patch: { name: updated.name, updatedAt: updated.updatedAt.toISOString(), updatedByUserId: auth.userId },
    });
    return { id: updated.id, name: updated.name };
  }

  /**
   * Moves an item within or between groups on the same board. Subitems only
   * reorder among their siblings; a parent carries its subitems along.
   */
  async moveItem(auth: AuthContext, itemId: string, dto: { groupId?: string; afterItemId?: string | null }) {
    const item = await this.ctx.writableItem(auth, itemId);
    if (item.parentItemId && dto.groupId && dto.groupId !== item.groupId) {
      throw new BadRequestException('Subitems move with their parent; reorder them among their siblings instead');
    }
    const targetGroupId = dto.groupId ?? item.groupId;
    if (targetGroupId !== item.groupId) {
      const [group] = await this.db
        .select({ id: groups.id })
        .from(groups)
        .where(and(eq(groups.id, targetGroupId), eq(groups.boardId, item.boardId)))
        .limit(1);
      if (!group) throw new NotFoundException('Target group is not on this board');
    }

    await this.db.transaction(async (tx) => {
      await this.place(tx, auth, item, targetGroupId, dto.afterItemId === undefined ? null : dto.afterItemId);
      if (targetGroupId !== item.groupId) {
        await tx.insert(activityLog).values({
          boardId: item.boardId,
          itemId,
          actorUserId: auth.userId,
          event: 'item_moved',
          payload: { from: item.groupId, to: targetGroupId, name: item.name },
        });
      }
    });
    await this.touchBoard(item.boardId);
    this.emit(auth, { type: 'item.moved', boardId: item.boardId, itemId, groupId: targetGroupId });
    return { ok: true as const };
  }

  async archiveItem(auth: AuthContext, itemId: string) {
    const item = await this.ctx.writableItem(auth, itemId);
    await this.db.transaction((tx) => this.archiveRows(tx, auth, [item], 'archive'));
    await this.touchBoard(item.boardId);
    this.emit(auth, { type: 'item.deleted', boardId: item.boardId, itemId });
    return { ok: true as const };
  }

  async trashItem(auth: AuthContext, itemId: string) {
    const item = await this.ctx.writableItem(auth, itemId, { includeInactive: true });
    if (item.trashedAt) return { ok: true as const };
    await this.db.transaction((tx) => this.archiveRows(tx, auth, [item], 'trash'));
    await this.touchBoard(item.boardId);
    this.emit(auth, { type: 'item.deleted', boardId: item.boardId, itemId });
    return { ok: true as const };
  }

  /** Restores from the archive or the trash, subitems included. */
  async restoreItem(auth: AuthContext, itemId: string): Promise<ItemPayload> {
    const item = await this.ctx.writableItem(auth, itemId, { includeInactive: true });
    if (!item.archivedAt && !item.trashedAt) return this.loadItemPayload(itemId);
    if (item.parentItemId) {
      const [parent] = await this.db
        .select({ archivedAt: items.archivedAt, trashedAt: items.trashedAt })
        .from(items)
        .where(eq(items.id, item.parentItemId))
        .limit(1);
      if (!parent || parent.archivedAt || parent.trashedAt) {
        throw new BadRequestException('Restore the parent item first');
      }
    }
    await this.db.transaction((tx) => this.restoreRows(tx, auth, [item]));
    await this.touchBoard(item.boardId);
    const payload = await this.loadItemPayload(itemId);
    this.emit(auth, { type: 'item.created', boardId: item.boardId, groupId: item.groupId, item: payload });
    return payload;
  }

  /** Hard delete from the trash — board owners and account admins only. */
  async deleteItemPermanently(auth: AuthContext, itemId: string) {
    const item = await this.ctx.writableItem(auth, itemId, { includeInactive: true });
    if (!item.trashedAt) throw new BadRequestException('Move the item to the trash before deleting it permanently');
    if (!(await this.ctx.isBoardManager(auth, item.boardId))) {
      throw new ForbiddenException('Only board owners can permanently delete items');
    }
    await this.db.delete(items).where(eq(items.id, itemId));
    return { ok: true as const };
  }

  /** Copies an item, its cell values and its subitems directly below the original. */
  async duplicateItem(auth: AuthContext, itemId: string): Promise<ItemPayload> {
    const item = await this.ctx.writableItem(auth, itemId);
    const copyId = await this.db.transaction((tx) => this.duplicateRow(tx, auth, item));
    await this.touchBoard(item.boardId);
    const payload = await this.loadItemPayload(copyId);
    this.emit(auth, { type: 'item.created', boardId: item.boardId, groupId: item.groupId, item: payload });
    return payload;
  }

  // --------------------------------------------------------------------- cells

  /**
   * Sets or clears one cell. The value shape is validated against the column
   * type, files columns are checked against the item's own files, and
   * assigning a person notifies them.
   */
  async setCellValue(auth: AuthContext, itemId: string, columnId: string, raw: unknown) {
    const item = await this.ctx.writableItem(auth, itemId);
    const [column] = await this.db
      .select()
      .from(columns)
      .where(and(eq(columns.id, columnId), eq(columns.boardId, item.boardId)))
      .limit(1);
    if (!column) throw new NotFoundException('Column not found on this board');
    const expectedScope = item.parentItemId ? 'subitems' : 'items';
    if (column.scope !== expectedScope) {
      throw new BadRequestException(`That column belongs to the board's ${column.scope}, not its ${expectedScope}`);
    }

    const result = await this.db.transaction((tx) => this.writeCell(tx, auth, item, column, raw));
    await this.touchBoard(item.boardId);
    await this.notifyNewAssignees(auth, {
      boardId: item.boardId,
      itemId,
      itemName: item.name,
      columnType: column.type,
      previous: result.previous,
      next: result.value,
    });
    this.emit(auth, { type: 'cell.changed', boardId: item.boardId, itemId, columnId, value: result.value });
    this.emit(auth, {
      type: 'item.updated',
      boardId: item.boardId,
      itemId,
      patch: { updatedAt: result.updatedAt.toISOString(), updatedByUserId: auth.userId },
    });
    return { columnId, value: result.value };
  }

  // --------------------------------------------------------------------- batch

  async batch(
    auth: AuthContext,
    boardId: string,
    dto: { itemIds: string[]; action: BatchAction; groupId?: string; columnId?: string; value?: unknown },
  ): Promise<{ affected: number; items?: ItemPayload[] }> {
    await this.ctx.writableBoard(auth, boardId);
    const ids = [...new Set(dto.itemIds)];
    const rows = await this.db
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
      .where(and(eq(items.boardId, boardId), inArray(items.id, ids)))
      .orderBy(asc(items.position));
    if (rows.length !== ids.length) throw new NotFoundException('Some items are not on this board');

    const live = rows.filter((r) => !r.archivedAt && !r.trashedAt);
    let produced: string[] = [];

    switch (dto.action) {
      case 'archive':
        await this.db.transaction((tx) => this.archiveRows(tx, auth, live, 'archive'));
        break;
      case 'trash':
        await this.db.transaction((tx) => this.archiveRows(tx, auth, rows.filter((r) => !r.trashedAt), 'trash'));
        break;
      case 'restore':
        await this.db.transaction((tx) => this.restoreRows(tx, auth, rows.filter((r) => r.archivedAt || r.trashedAt)));
        produced = rows.filter((r) => r.archivedAt || r.trashedAt).map((r) => r.id);
        break;
      case 'delete_permanent': {
        if (!(await this.ctx.isBoardManager(auth, boardId))) {
          throw new ForbiddenException('Only board owners can permanently delete items');
        }
        const trashed = rows.filter((r) => r.trashedAt).map((r) => r.id);
        if (trashed.length) await this.db.delete(items).where(inArray(items.id, trashed));
        break;
      }
      case 'duplicate':
        produced = await this.db.transaction(async (tx) => {
          const out: string[] = [];
          for (const row of live) out.push(await this.duplicateRow(tx, auth, row));
          return out;
        });
        break;
      case 'move': {
        if (!dto.groupId) throw new BadRequestException('groupId is required to move items');
        const [group] = await this.db
          .select({ id: groups.id })
          .from(groups)
          .where(and(eq(groups.id, dto.groupId), eq(groups.boardId, boardId)))
          .limit(1);
        if (!group) throw new NotFoundException('Target group is not on this board');
        const movable = live.filter((r) => !r.parentItemId);
        await this.db.transaction(async (tx) => {
          for (const row of movable) {
            if (row.groupId === dto.groupId) continue;
            await this.place(tx, auth, row, dto.groupId!, undefined);
            await tx.insert(activityLog).values({
              boardId,
              itemId: row.id,
              actorUserId: auth.userId,
              event: 'item_moved',
              payload: { from: row.groupId, to: dto.groupId, name: row.name },
            });
          }
        });
        break;
      }
      case 'set_cell': {
        if (!dto.columnId) throw new BadRequestException('columnId is required to set a cell');
        const [column] = await this.db
          .select()
          .from(columns)
          .where(and(eq(columns.id, dto.columnId), eq(columns.boardId, boardId)))
          .limit(1);
        if (!column) throw new NotFoundException('Column not found on this board');
        const scoped = live.filter((r) => (r.parentItemId ? 'subitems' : 'items') === column.scope);
        const results = await this.db.transaction(async (tx) => {
          const out = [];
          for (const row of scoped) out.push({ row, ...(await this.writeCell(tx, auth, row, column, dto.value ?? null)) });
          return out;
        });
        for (const r of results) {
          await this.notifyNewAssignees(auth, {
            boardId,
            itemId: r.row.id,
            itemName: r.row.name,
            columnType: column.type,
            previous: r.previous,
            next: r.value,
          });
        }
        break;
      }
    }

    await this.touchBoard(boardId);
    this.emit(auth, { type: 'board.updated', boardId, patch: { batch: dto.action } });
    const affected = dto.action === 'duplicate' || dto.action === 'restore' ? produced.length : rows.length;
    if (produced.length) {
      const payloads = await Promise.all(produced.map((id) => this.loadItemPayload(id)));
      return { affected, items: payloads };
    }
    return { affected };
  }

  // ------------------------------------------------------------- move to board

  async movePreview(auth: AuthContext, itemId: string, targetBoardId: string) {
    const item = await this.ctx.visibleItem(auth, itemId);
    if (item.parentItemId) throw new BadRequestException('Move the parent item instead');
    const target = await this.ctx.visibleBoard(auth, targetBoardId);
    if (target.id === item.boardId) throw new BadRequestException('The item is already on that board');

    const [sourceCols, targetCols, targetGroups, subitemCount] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, item.boardId)).orderBy(asc(columns.position)),
      this.db.select().from(columns).where(eq(columns.boardId, target.id)).orderBy(asc(columns.position)),
      this.db.select().from(groups).where(eq(groups.boardId, target.id)).orderBy(asc(groups.position)),
      this.db
        .select({ n: count() })
        .from(items)
        .where(and(eq(items.parentItemId, item.id), itemIsLive())),
    ]);
    const plan = planColumnMapping(sourceCols, targetCols);
    return {
      targetBoard: { id: target.id, name: target.name },
      groups: targetGroups.map((g) => ({ id: g.id, title: g.title, color: g.color })),
      mapping: plan.mapping,
      dropped: plan.dropped,
      subitemCount: Number(subitemCount[0]?.n ?? 0),
    };
  }

  /**
   * Moves an item (with its subitems, updates, files and activity) to another
   * board, translating cell values through the column mapping.
   */
  async moveToBoard(auth: AuthContext, itemId: string, dto: { boardId: string; groupId: string }) {
    const item = await this.ctx.writableItem(auth, itemId);
    if (item.parentItemId) throw new BadRequestException('Move the parent item instead');
    const target = await this.ctx.writableBoard(auth, dto.boardId);
    if (target.id === item.boardId) throw new BadRequestException('The item is already on that board');
    const [group] = await this.db
      .select({ id: groups.id })
      .from(groups)
      .where(and(eq(groups.id, dto.groupId), eq(groups.boardId, target.id)))
      .limit(1);
    if (!group) throw new NotFoundException('Target group is not on that board');

    const [sourceBoard] = await this.db.select({ name: boards.name }).from(boards).where(eq(boards.id, item.boardId)).limit(1);
    const sourceCols = await this.db.select().from(columns).where(eq(columns.boardId, item.boardId));
    const subitemRows = await this.db
      .select()
      .from(items)
      .where(and(eq(items.parentItemId, item.id), itemIsLive()))
      .orderBy(asc(items.position));

    await this.db.transaction(async (tx) => {
      if (subitemRows.length) await this.ensureSubitemColumns(tx, target.id);
      const targetCols = await tx.select().from(columns).where(eq(columns.boardId, target.id));
      const plan = planColumnMapping(sourceCols, targetCols);
      const sourceById = new Map(sourceCols.map((c) => [c.id, c]));
      const targetById = new Map(targetCols.map((c) => [c.id, c]));

      const movingIds = [item.id, ...subitemRows.map((s) => s.id)];
      const valueRows = await tx.select().from(columnValues).where(inArray(columnValues.itemId, movingIds));
      await tx.delete(columnValues).where(inArray(columnValues.itemId, movingIds));
      const translated = valueRows.flatMap((v) => {
        const mapping = plan.mapping.find((m) => m.sourceColumnId === v.columnId);
        const source = sourceById.get(v.columnId);
        if (!mapping?.targetColumnId || !source) return [];
        const targetColumn = targetById.get(mapping.targetColumnId)!;
        const value = remapCellValue(source.type, v.value as Record<string, unknown> | null, source.settings, targetColumn.settings);
        return value ? [{ itemId: v.itemId, columnId: targetColumn.id, value, updatedByUserId: auth.userId }] : [];
      });
      if (translated.length) await tx.insert(columnValues).values(translated);

      // New serials on the target board, keeping the parent before its subitems.
      const ordered = await this.siblings(tx, { groupId: dto.groupId, parentItemId: null });
      let serial = await this.nextSerial(tx, target.id);
      await tx
        .update(items)
        .set({
          boardId: target.id,
          groupId: dto.groupId,
          position: positionAtEnd(ordered.map((i) => i.position)),
          serial: serial++,
          updatedAt: new Date(),
          updatedByUserId: auth.userId,
        })
        .where(eq(items.id, item.id));
      for (const sub of subitemRows) {
        await tx
          .update(items)
          .set({ boardId: target.id, groupId: dto.groupId, serial: serial++, updatedAt: new Date(), updatedByUserId: auth.userId })
          .where(eq(items.id, sub.id));
      }

      await tx.update(updates).set({ boardId: target.id }).where(inArray(updates.itemId, movingIds));
      await tx.update(files).set({ boardId: target.id, columnId: null }).where(inArray(files.itemId, movingIds));
      // Files column cells cannot be re-homed (their column ids differ), so
      // moved files stay reachable from the item's Files tab instead.
      const fileColumnIds = targetCols.filter((c) => c.type === 'files').map((c) => c.id);
      if (fileColumnIds.length) {
        await tx
          .delete(columnValues)
          .where(and(inArray(columnValues.itemId, movingIds), inArray(columnValues.columnId, fileColumnIds)));
      }
      await tx.update(activityLog).set({ boardId: target.id }).where(inArray(activityLog.itemId, movingIds));

      await tx.insert(activityLog).values([
        {
          boardId: item.boardId,
          actorUserId: auth.userId,
          event: 'item_moved_to_board',
          payload: { itemId: item.id, itemName: item.name, fromBoardId: item.boardId, toBoardId: target.id, toBoardName: target.name },
        },
        {
          boardId: target.id,
          itemId: item.id,
          actorUserId: auth.userId,
          event: 'item_moved_to_board',
          payload: { itemName: item.name, fromBoardId: item.boardId, fromBoardName: sourceBoard?.name ?? '', toBoardId: target.id },
        },
      ]);
    });

    await Promise.all([this.touchBoard(item.boardId), this.touchBoard(target.id)]);
    this.emit(auth, { type: 'item.deleted', boardId: item.boardId, itemId: item.id });
    const payload = await this.loadItemPayload(item.id);
    this.emit(auth, { type: 'item.created', boardId: target.id, groupId: dto.groupId, item: payload });
    return { itemId: item.id, boardId: target.id };
  }

  // -------------------------------------------------------------------- shared

  /** Full item payload with values and subitems, for realtime and responses. */
  async loadItemPayload(itemId: string): Promise<ItemPayload> {
    const [row] = await this.db.select().from(items).where(eq(items.id, itemId)).limit(1);
    if (!row) throw new NotFoundException('Item not found');
    const subRows = row.parentItemId
      ? []
      : await this.db
          .select()
          .from(items)
          .where(and(eq(items.parentItemId, itemId), itemIsLive()))
          .orderBy(asc(items.position));
    const ids = [itemId, ...subRows.map((s) => s.id)];
    const [valueRows, updateCounts] = await Promise.all([
      this.db.select().from(columnValues).where(inArray(columnValues.itemId, ids)),
      this.db
        .select({ itemId: updates.itemId, n: count() })
        .from(updates)
        .where(inArray(updates.itemId, ids))
        .groupBy(updates.itemId),
    ]);
    const valuesFor = (id: string) => {
      const bag: Record<string, unknown> = {};
      for (const v of valueRows) if (v.itemId === id) bag[v.columnId] = v.value;
      return bag;
    };
    const countFor = (id: string) => Number(updateCounts.find((u) => u.itemId === id)?.n ?? 0);
    return presentItem(
      row,
      valuesFor(itemId),
      countFor(itemId),
      subRows.map((s) => presentItem(s, valuesFor(s.id), countFor(s.id))),
    );
  }

  /** Live siblings: items in a group (top level) or under one parent. */
  private siblings(exec: Executor, where: { groupId: string; parentItemId: string | null }) {
    return exec
      .select({ id: items.id, position: items.position })
      .from(items)
      .where(
        and(
          eq(items.groupId, where.groupId),
          where.parentItemId ? eq(items.parentItemId, where.parentItemId) : isNull(items.parentItemId),
          itemIsLive(),
        ),
      )
      .orderBy(asc(items.position));
  }

  private async nextSerial(exec: Executor, boardId: string): Promise<number> {
    const [row] = await exec
      .select({ next: sql<number>`coalesce(max(${items.serial}), 0) + 1` })
      .from(items)
      .where(eq(items.boardId, boardId));
    return Number(row?.next ?? 1);
  }

  /** Creates the default subitem columns when a board has none yet. */
  private async ensureSubitemColumns(exec: Executor, boardId: string): Promise<void> {
    const [existing] = await exec
      .select({ n: count() })
      .from(columns)
      .where(and(eq(columns.boardId, boardId), eq(columns.scope, 'subitems')));
    if (Number(existing?.n ?? 0) > 0) return;
    await exec.insert(columns).values(
      DEFAULT_SUBITEM_COLUMNS.map((spec, index) => ({
        boardId,
        type: spec.type,
        scope: 'subitems' as const,
        title: spec.title,
        settings: defaultSettingsFor(spec.type),
        position: index + 1,
      })),
    );
  }

  /**
   * Positions `item` in `targetGroupId` after `afterItemId` (null = first,
   * undefined = append) and carries subitems along on a group change.
   */
  private async place(
    exec: Executor,
    auth: AuthContext,
    item: ItemRow,
    targetGroupId: string,
    afterItemId: string | null | undefined,
  ): Promise<void> {
    const ordered = await this.siblings(exec, { groupId: targetGroupId, parentItemId: item.parentItemId });
    if (afterItemId && !ordered.some((i) => i.id === afterItemId)) {
      throw new NotFoundException('afterItemId is not among the target siblings');
    }
    const after = afterItemId === undefined ? (ordered.filter((i) => i.id !== item.id).at(-1)?.id ?? null) : afterItemId;
    const { before, after: next } = neighboursFor(ordered, after, item.id);
    const stamp = { updatedAt: new Date(), updatedByUserId: auth.userId };

    if (needsRebalance(before, next)) {
      const ids = ordered.map((r) => r.id).filter((id) => id !== item.id);
      ids.splice(after === null ? 0 : ids.indexOf(after) + 1, 0, item.id);
      const positions = rebalanced(ids.length);
      for (const [index, id] of ids.entries()) {
        await exec.update(items).set({ position: positions[index] }).where(eq(items.id, id));
      }
      await exec.update(items).set({ groupId: targetGroupId, ...stamp }).where(eq(items.id, item.id));
    } else {
      await exec
        .update(items)
        .set({ groupId: targetGroupId, position: positionBetween(before, next), ...stamp })
        .where(eq(items.id, item.id));
    }
    if (targetGroupId !== item.groupId && !item.parentItemId) {
      await exec.update(items).set({ groupId: targetGroupId }).where(eq(items.parentItemId, item.id));
    }
  }

  private async archiveRows(exec: Executor, auth: AuthContext, rows: ItemRow[], mode: 'archive' | 'trash'): Promise<void> {
    if (rows.length === 0) return;
    const ids = rows.map((r) => r.id);
    const parents = rows.filter((r) => !r.parentItemId).map((r) => r.id);
    const now = new Date();
    const patch = mode === 'archive' ? { archivedAt: now } : { trashedAt: now };
    await exec.update(items).set(patch).where(inArray(items.id, ids));
    if (parents.length) {
      // Subitems follow their parent; ones already in the same state stay put.
      await exec
        .update(items)
        .set(patch)
        .where(and(inArray(items.parentItemId, parents), isNull(mode === 'archive' ? items.archivedAt : items.trashedAt)));
    }
    await exec.insert(activityLog).values(
      rows.map((r) => ({
        boardId: r.boardId,
        itemId: r.id,
        actorUserId: auth.userId,
        event: (mode === 'archive' ? 'item_archived' : 'item_trashed') as 'item_archived' | 'item_trashed',
        payload: { name: r.name, groupId: r.groupId, parentItemId: r.parentItemId },
      })),
    );
  }

  private async restoreRows(exec: Executor, auth: AuthContext, rows: ItemRow[]): Promise<void> {
    if (rows.length === 0) return;
    const ids = rows.map((r) => r.id);
    const parents = rows.filter((r) => !r.parentItemId).map((r) => r.id);
    const patch = { archivedAt: null, trashedAt: null, updatedAt: new Date(), updatedByUserId: auth.userId };
    await exec.update(items).set(patch).where(inArray(items.id, ids));
    if (parents.length) await exec.update(items).set(patch).where(inArray(items.parentItemId, parents));
    await exec.insert(activityLog).values(
      rows.map((r) => ({
        boardId: r.boardId,
        itemId: r.id,
        actorUserId: auth.userId,
        event: 'item_restored' as const,
        payload: { name: r.name, from: r.trashedAt ? 'trash' : 'archive' },
      })),
    );
  }

  /** Copies one item (and its subitems) right after the source; returns the copy's id. */
  private async duplicateRow(exec: Executor, auth: AuthContext, item: ItemRow): Promise<string> {
    const ordered = await this.siblings(exec, { groupId: item.groupId, parentItemId: item.parentItemId });
    const { before, after } = neighboursFor(ordered, item.id);
    const [copy] = await exec
      .insert(items)
      .values({
        boardId: item.boardId,
        groupId: item.groupId,
        parentItemId: item.parentItemId,
        name: `${item.name} (copy)`,
        position: positionBetween(before, after),
        serial: await this.nextSerial(exec, item.boardId),
        createdByUserId: auth.userId,
        updatedByUserId: auth.userId,
      })
      .returning({ id: items.id });

    await this.copyValues(exec, auth, item.id, copy.id);

    if (!item.parentItemId) {
      const subRows = await exec
        .select()
        .from(items)
        .where(and(eq(items.parentItemId, item.id), itemIsLive()))
        .orderBy(asc(items.position));
      for (const sub of subRows) {
        const [subCopy] = await exec
          .insert(items)
          .values({
            boardId: item.boardId,
            groupId: item.groupId,
            parentItemId: copy.id,
            name: sub.name,
            position: sub.position,
            serial: await this.nextSerial(exec, item.boardId),
            createdByUserId: auth.userId,
            updatedByUserId: auth.userId,
          })
          .returning({ id: items.id });
        await this.copyValues(exec, auth, sub.id, subCopy.id);
      }
    }

    await exec.insert(activityLog).values({
      boardId: item.boardId,
      itemId: copy.id,
      actorUserId: auth.userId,
      event: 'item_duplicated',
      payload: { sourceItemId: item.id, name: item.name },
    });
    return copy.id;
  }

  /** Copies cell values except Files cells, whose file rows belong to the source item. */
  private async copyValues(exec: Executor, auth: AuthContext, fromItemId: string, toItemId: string): Promise<void> {
    const rows = await exec
      .select({ columnId: columnValues.columnId, value: columnValues.value, type: columns.type })
      .from(columnValues)
      .innerJoin(columns, eq(columnValues.columnId, columns.id))
      .where(eq(columnValues.itemId, fromItemId));
    const copyable = rows.filter((r) => r.type !== 'files');
    if (copyable.length) {
      await exec.insert(columnValues).values(
        copyable.map((v) => ({ itemId: toItemId, columnId: v.columnId, value: v.value, updatedByUserId: auth.userId })),
      );
    }
  }

  private async writeCell(
    exec: Executor,
    auth: AuthContext,
    item: ItemRow,
    column: typeof columns.$inferSelect,
    raw: unknown,
  ): Promise<{ previous: Record<string, unknown> | null; value: Record<string, unknown> | null; updatedAt: Date }> {
    const normalized = normalizeColumnValue(column.type, (column.settings ?? {}) as ColumnSettings, raw);
    if (column.type === 'files' && normalized) {
      const ids = normalized.fileIds as string[];
      const owned = await exec
        .select({ id: files.id })
        .from(files)
        .where(and(inArray(files.id, ids), eq(files.itemId, item.id)));
      if (owned.length !== ids.length) throw new BadRequestException('Files cells may only reference files uploaded to this item');
    }

    const [previous] = await exec
      .select({ value: columnValues.value })
      .from(columnValues)
      .where(and(eq(columnValues.itemId, item.id), eq(columnValues.columnId, column.id)))
      .limit(1);

    if (normalized === null) {
      await exec.delete(columnValues).where(and(eq(columnValues.itemId, item.id), eq(columnValues.columnId, column.id)));
    } else {
      await exec
        .insert(columnValues)
        .values({ itemId: item.id, columnId: column.id, value: normalized, updatedByUserId: auth.userId })
        .onConflictDoUpdate({
          target: [columnValues.itemId, columnValues.columnId],
          set: { value: normalized, updatedByUserId: auth.userId, updatedAt: new Date() },
        });
    }
    const updatedAt = new Date();
    await exec.update(items).set({ updatedAt, updatedByUserId: auth.userId }).where(eq(items.id, item.id));
    await exec.insert(activityLog).values({
      boardId: item.boardId,
      itemId: item.id,
      actorUserId: auth.userId,
      event: 'column_value_changed',
      payload: { columnId: column.id, columnTitle: column.title, from: previous?.value ?? null, to: normalized },
    });
    return { previous: (previous?.value ?? null) as Record<string, unknown> | null, value: normalized, updatedAt };
  }

  /** Keeps `boards.updatedAt` meaningful — it orders the board lists. */
  private async touchBoard(boardId: string): Promise<void> {
    await this.db.update(boards).set({ updatedAt: new Date() }).where(eq(boards.id, boardId));
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

    const members = await this.db
      .select({ userId: accountMembers.userId })
      .from(accountMembers)
      .where(
        and(
          eq(accountMembers.accountId, auth.accountId),
          eq(accountMembers.status, 'active'),
          inArray(accountMembers.userId, added),
        ),
      );
    if (members.length === 0) return;

    const [board] = await this.db.select({ name: boards.name }).from(boards).where(eq(boards.id, ctx.boardId)).limit(1);
    await this.notifier.dispatch(
      members.map((m) => ({
        accountId: auth.accountId,
        userId: m.userId,
        type: 'assigned' as const,
        actorUserId: auth.userId,
        payload: { boardId: ctx.boardId, boardName: board?.name ?? '', itemId: ctx.itemId, itemName: ctx.itemName },
      })),
    );
  }
}

function pair(n: { before: number | null; after: number | null }): [number | null, number | null] {
  return [n.before, n.after];
}

