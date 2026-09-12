import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, eq, inArray, isNotNull, isNull, sql } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardIsLive, itemIsLive } from '../../db/live';
import {
  activityLog,
  boardMembers,
  boards,
  boardViews,
  columns,
  columnValues,
  groups,
  items,
  templates,
  updates,
  workspaces,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardAccessService } from '../access/board-access.service';
import { BoardContextService } from '../access/board-context.service';
import { RealtimeGateway, type BoardEvent } from '../realtime/realtime.gateway';
import {
  ALL_COLUMN_TYPES,
  defaultSettingsFor,
  normalizeColumnSettings,
  normalizeColumnValue,
  type ColumnSettings,
} from './column-values';
import { neighboursFor, needsRebalance, positionAtEnd, positionBetween, rebalanced } from './positioning';
import { presentColumn, presentGroup } from './presenters';
import { findTemplate, type BoardTemplate, type TemplateColumn } from './templates.catalog';

const GROUP_COLORS = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo'];
const TEMPLATE_ICONS = ['grid', 'check', 'calendar', 'briefcase', 'event', 'inbox', 'star', 'flag'];

export type BoardType = 'main' | 'shareable' | 'private';
export type ColumnScope = 'items' | 'subitems';
export type DuplicateMode = 'structure' | 'items' | 'items_and_updates';

export interface TemplateSummary {
  key: string;
  name: string;
  description: string;
  icon: string;
  accentColor: string;
  columnCount: number;
  groupCount: number;
  itemCount: number;
  isCustom: boolean;
  id?: string;
  createdByName?: string;
  createdAt?: string;
}

/**
 * Board-, group- and column-level writes: create (from built-in or account
 * templates), rename, archive/trash/restore, duplicate, save as template.
 * Item-level writes live in ItemWritesService.
 */
@Injectable()
export class BoardWritesService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly realtime: RealtimeGateway,
    private readonly boardAccess: BoardAccessService,
    private readonly ctx: BoardContextService,
  ) {}

  private emit(auth: AuthContext, event: BoardEvent): void {
    this.realtime.publish(event, { accountId: auth.accountId, exceptUserId: auth.userId });
  }

  // ---------------------------------------------------------------- workspaces

  async createWorkspace(auth: AuthContext, name: string) {
    this.ctx.assertEditorRole(auth);
    const [workspace] = await this.db
      .insert(workspaces)
      .values({ accountId: auth.accountId, name: name.trim(), createdByUserId: auth.userId })
      .returning();
    return { id: workspace.id, name: workspace.name, boards: [] };
  }

  // -------------------------------------------------------------------- boards

  /** Creates a board from a template blueprint — built-in or account-authored. */
  async createBoard(
    auth: AuthContext,
    dto: { name: string; workspaceId?: string; description?: string; type?: BoardType; template?: string },
  ) {
    this.ctx.assertEditorRole(auth);
    const workspaceId = dto.workspaceId ?? (await this.defaultWorkspaceId(auth));
    await this.assertWorkspaceInAccount(auth, workspaceId);

    const templateKey = dto.template ?? 'blank';
    const template = await this.resolveTemplate(auth, templateKey);
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

      await this.applyTemplate(tx, auth, board.id, template);

      await tx.insert(activityLog).values({
        boardId: board.id,
        actorUserId: auth.userId,
        event: 'board_created',
        payload: { name: board.name, template: templateKey },
      });

      return { id: board.id, name: board.name, workspaceId };
    });
  }

  async updateBoard(
    auth: AuthContext,
    boardId: string,
    dto: { name?: string; description?: string; type?: BoardType },
  ) {
    const board = await this.ctx.writableBoard(auth, boardId);
    // Changing who can see the board is a board-settings decision — owners
    // and account admins only (renaming stays open to any editor).
    if (dto.type !== undefined) {
      await this.boardAccess.assertCanManage(auth, boardId);
    }

    const patch: Record<string, unknown> = { updatedAt: new Date() };
    if (dto.name !== undefined) patch.name = dto.name.trim();
    if (dto.description !== undefined) patch.description = dto.description.trim() || null;
    if (dto.type !== undefined) patch.type = dto.type;

    const [updated] = await this.db.update(boards).set(patch).where(eq(boards.id, boardId)).returning();
    if (dto.name !== undefined && updated.name !== board.name) {
      await this.db.insert(activityLog).values({
        boardId,
        actorUserId: auth.userId,
        event: 'board_renamed',
        payload: { from: board.name, to: updated.name },
      });
    }
    this.emit(auth, { type: 'board.updated', boardId, patch: dto });
    return { id: updated.id, name: updated.name, description: updated.description, type: updated.type };
  }

  /** Archive: hidden from lists, kept indefinitely, restorable. */
  async archiveBoard(auth: AuthContext, boardId: string) {
    const board = await this.ctx.writableBoard(auth, boardId);
    await this.db.update(boards).set({ archivedAt: new Date() }).where(eq(boards.id, boardId));
    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'board_archived',
      payload: { name: board.name },
    });
    return { ok: true as const };
  }

  /** Trash: hidden, purged 30 days later unless restored. */
  async trashBoard(auth: AuthContext, boardId: string) {
    const board = await this.ctx.writableBoard(auth, boardId, { includeInactive: true });
    if (board.trashedAt) return { ok: true as const };
    await this.db.update(boards).set({ trashedAt: new Date() }).where(eq(boards.id, boardId));
    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'board_trashed',
      payload: { name: board.name },
    });
    return { ok: true as const };
  }

  async restoreBoard(auth: AuthContext, boardId: string) {
    const board = await this.ctx.writableBoard(auth, boardId, { includeInactive: true });
    if (!board.archivedAt && !board.trashedAt) return { ok: true as const };
    await this.db
      .update(boards)
      .set({ archivedAt: null, trashedAt: null, updatedAt: new Date() })
      .where(eq(boards.id, boardId));
    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'board_restored',
      payload: { name: board.name, from: board.trashedAt ? 'trash' : 'archive' },
    });
    return { ok: true as const };
  }

  /** Hard delete. Only from the trash, only by board owners / account admins. */
  async deleteBoardPermanently(auth: AuthContext, boardId: string) {
    const board = await this.ctx.writableBoard(auth, boardId, { includeInactive: true });
    if (!board.trashedAt) throw new BadRequestException('Move the board to the trash before deleting it permanently');
    if (!(await this.ctx.isBoardManager(auth, boardId))) {
      throw new ForbiddenException('Only board owners can permanently delete a board');
    }
    await this.db.delete(boards).where(eq(boards.id, boardId));
    return { ok: true as const };
  }

  /**
   * Copies a board's structure — and, by mode, its items, subitems and
   * updates — into a new board owned by the caller.
   */
  async duplicateBoard(
    auth: AuthContext,
    boardId: string,
    dto: { name?: string; mode: DuplicateMode; workspaceId?: string },
  ) {
    const source = await this.ctx.visibleBoard(auth, boardId);
    this.ctx.assertEditorRole(auth);
    const workspaceId = dto.workspaceId ?? source.workspaceId;
    await this.assertWorkspaceInAccount(auth, workspaceId);

    const [sourceBoard] = await this.db.select().from(boards).where(eq(boards.id, boardId)).limit(1);
    const [cols, groupRows, viewRows] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, boardId)).orderBy(asc(columns.position)),
      this.db.select().from(groups).where(eq(groups.boardId, boardId)).orderBy(asc(groups.position)),
      this.db.select().from(boardViews).where(eq(boardViews.boardId, boardId)).orderBy(asc(boardViews.position)),
    ]);

    return this.db.transaction(async (tx) => {
      const [copy] = await tx
        .insert(boards)
        .values({
          accountId: auth.accountId,
          workspaceId,
          name: (dto.name?.trim() || `${sourceBoard.name} (copy)`).slice(0, 200),
          description: sourceBoard.description,
          type: sourceBoard.type,
          createdByUserId: auth.userId,
        })
        .returning();
      await tx.insert(boardMembers).values({ boardId: copy.id, userId: auth.userId, role: 'owner' });

      const columnIdMap = new Map<string, string>();
      for (const column of cols) {
        const [created] = await tx
          .insert(columns)
          .values({
            boardId: copy.id,
            type: column.type,
            scope: column.scope,
            title: column.title,
            settings: column.settings,
            position: column.position,
            width: column.width,
          })
          .returning({ id: columns.id });
        columnIdMap.set(column.id, created.id);
      }

      const groupIdMap = new Map<string, string>();
      for (const group of groupRows) {
        const [created] = await tx
          .insert(groups)
          .values({ boardId: copy.id, title: group.title, color: group.color, position: group.position })
          .returning({ id: groups.id });
        groupIdMap.set(group.id, created.id);
      }

      for (const view of viewRows) {
        await tx.insert(boardViews).values({
          boardId: copy.id,
          type: view.type,
          name: view.name,
          config: remapViewConfig(view.config, columnIdMap, groupIdMap),
          isDefault: view.isDefault,
          position: view.position,
          createdByUserId: auth.userId,
        });
      }
      if (viewRows.length === 0) {
        await tx.insert(boardViews).values({
          boardId: copy.id,
          type: 'table',
          name: 'Main Table',
          isDefault: true,
          position: 1,
          createdByUserId: auth.userId,
        });
      }

      if (dto.mode !== 'structure') {
        const itemRows = await tx
          .select()
          .from(items)
          .where(and(eq(items.boardId, boardId), itemIsLive()))
          .orderBy(asc(items.position));
        const itemIds = itemRows.map((i) => i.id);
        const valueRows = itemIds.length
          ? await tx.select().from(columnValues).where(inArray(columnValues.itemId, itemIds))
          : [];

        const itemIdMap = new Map<string, string>();
        // Parents first so subitems can reference their new parent.
        const ordered = [...itemRows.filter((i) => !i.parentItemId), ...itemRows.filter((i) => i.parentItemId)];
        for (const item of ordered) {
          const parentId = item.parentItemId ? itemIdMap.get(item.parentItemId) : null;
          if (item.parentItemId && !parentId) continue; // orphaned subitem — skip
          const [created] = await tx
            .insert(items)
            .values({
              boardId: copy.id,
              groupId: groupIdMap.get(item.groupId)!,
              parentItemId: parentId ?? null,
              name: item.name,
              position: item.position,
              serial: item.serial,
              createdByUserId: auth.userId,
              updatedByUserId: auth.userId,
            })
            .returning({ id: items.id });
          itemIdMap.set(item.id, created.id);
        }

        const copiedValues = valueRows
          .filter((v) => itemIdMap.has(v.itemId) && columnIdMap.has(v.columnId))
          .map((v) => ({
            itemId: itemIdMap.get(v.itemId)!,
            columnId: columnIdMap.get(v.columnId)!,
            // Files columns reference file rows that stay with the source item.
            value: v.value,
            updatedByUserId: auth.userId,
          }));
        const filesColumnIds = new Set(cols.filter((c) => c.type === 'files').map((c) => columnIdMap.get(c.id)!));
        const insertable = copiedValues.filter((v) => !filesColumnIds.has(v.columnId));
        if (insertable.length) await tx.insert(columnValues).values(insertable);

        if (dto.mode === 'items_and_updates' && itemIds.length) {
          const updateRows = await tx
            .select()
            .from(updates)
            .where(eq(updates.boardId, boardId))
            .orderBy(asc(updates.createdAt));
          const updateIdMap = new Map<string, string>();
          for (const update of [...updateRows.filter((u) => !u.parentId), ...updateRows.filter((u) => u.parentId)]) {
            const itemId = update.itemId ? itemIdMap.get(update.itemId) : null;
            if (update.itemId && !itemId) continue;
            const parentId = update.parentId ? updateIdMap.get(update.parentId) : null;
            if (update.parentId && !parentId) continue;
            const [created] = await tx
              .insert(updates)
              .values({
                boardId: copy.id,
                itemId: itemId ?? null,
                authorUserId: update.authorUserId,
                parentId: parentId ?? null,
                body: update.body,
                bodyText: update.bodyText,
                mentionedUserIds: update.mentionedUserIds,
                createdAt: update.createdAt,
                editedAt: update.editedAt,
              })
              .returning({ id: updates.id });
            updateIdMap.set(update.id, created.id);
          }
        }
      }

      await tx.insert(activityLog).values({
        boardId: copy.id,
        actorUserId: auth.userId,
        event: 'board_created',
        payload: { name: copy.name, duplicatedFrom: boardId, mode: dto.mode },
      });
      return { id: copy.id, name: copy.name, workspaceId };
    });
  }

  // ----------------------------------------------------------------- templates

  /** Built-in catalog followed by the account's own templates. */
  async listTemplates(auth: AuthContext): Promise<TemplateSummary[]> {
    const { templateGallery } = await import('./templates.catalog');
    const builtIn: TemplateSummary[] = templateGallery().map((t) => ({ ...t, isCustom: false }));
    const custom = await this.db
      .select({ template: templates, createdByName: sql<string | null>`(select full_name from user_profiles where user_id = ${templates.createdByUserId})` })
      .from(templates)
      .where(eq(templates.accountId, auth.accountId))
      .orderBy(asc(templates.createdAt));
    return [
      ...builtIn,
      ...custom.map(({ template, createdByName }) => {
        const payload = template.payload as BoardTemplate;
        return {
          key: template.key,
          name: template.name,
          description: template.description,
          icon: template.icon,
          accentColor: template.accentColor,
          columnCount: payload.columns?.length ?? 0,
          groupCount: payload.groups?.length ?? 0,
          itemCount: payload.items?.length ?? 0,
          isCustom: true,
          id: template.id,
          createdByName: createdByName ?? '',
          createdAt: template.createdAt.toISOString(),
        };
      }),
    ];
  }

  /** Snapshots a board's structure (and optionally its items) as an account template. */
  async saveAsTemplate(
    auth: AuthContext,
    boardId: string,
    dto: { name: string; description?: string; includeItems: boolean },
  ): Promise<TemplateSummary> {
    await this.ctx.visibleBoard(auth, boardId);
    this.ctx.assertEditorRole(auth);

    const [cols, groupRows] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, boardId)).orderBy(asc(columns.position)),
      this.db.select().from(groups).where(eq(groups.boardId, boardId)).orderBy(asc(groups.position)),
    ]);
    const titleById = new Map(cols.map((c) => [c.id, c.title]));
    const filesColumnIds = new Set(cols.filter((c) => c.type === 'files').map((c) => c.id));

    const blueprintItems: BoardTemplate['items'] = [];
    if (dto.includeItems) {
      const itemRows = await this.db
        .select()
        .from(items)
        .where(and(eq(items.boardId, boardId), itemIsLive(), isNull(items.parentItemId)))
        .orderBy(asc(items.position));
      const valueRows = itemRows.length
        ? await this.db.select().from(columnValues).where(inArray(columnValues.itemId, itemRows.map((i) => i.id)))
        : [];
      const groupIndex = new Map(groupRows.map((g, index) => [g.id, index]));
      for (const item of itemRows) {
        const cells: Record<string, unknown> = {};
        for (const v of valueRows) {
          if (v.itemId !== item.id || filesColumnIds.has(v.columnId)) continue;
          const title = titleById.get(v.columnId);
          if (title && v.value !== null) cells[title] = v.value;
        }
        blueprintItems.push({ name: item.name, group: groupIndex.get(item.groupId) ?? 0, cells });
      }
    }

    const payload: BoardTemplate = {
      key: `custom_${randomUUID()}`,
      name: dto.name.trim().slice(0, 120),
      description: (dto.description ?? '').trim().slice(0, 500),
      icon: TEMPLATE_ICONS[Math.abs(hashCode(dto.name)) % TEMPLATE_ICONS.length],
      accentColor: GROUP_COLORS[Math.abs(hashCode(dto.name)) % GROUP_COLORS.length],
      columns: cols
        .filter((c) => c.scope === 'items' || c.scope === 'subitems')
        .map<TemplateColumn>((c) => ({
          type: c.type,
          title: c.title,
          settings: (c.settings ?? {}) as Record<string, unknown>,
          scope: c.scope,
        })),
      groups: groupRows.map((g) => ({ title: g.title, color: g.color })),
      items: blueprintItems,
    };

    const [row] = await this.db
      .insert(templates)
      .values({
        key: payload.key,
        accountId: auth.accountId,
        createdByUserId: auth.userId,
        name: payload.name,
        description: payload.description,
        icon: payload.icon,
        accentColor: payload.accentColor,
        payload,
      })
      .returning();

    return {
      key: row.key,
      name: row.name,
      description: row.description,
      icon: row.icon,
      accentColor: row.accentColor,
      columnCount: payload.columns.length,
      groupCount: payload.groups.length,
      itemCount: payload.items.length,
      isCustom: true,
      id: row.id,
      createdAt: row.createdAt.toISOString(),
    };
  }

  async deleteTemplate(auth: AuthContext, templateId: string) {
    const [row] = await this.db
      .select({ id: templates.id, createdByUserId: templates.createdByUserId })
      .from(templates)
      .where(and(eq(templates.id, templateId), eq(templates.accountId, auth.accountId)))
      .limit(1);
    if (!row) throw new NotFoundException('Template not found');
    if (row.createdByUserId !== auth.userId && auth.role !== 'admin') {
      throw new ForbiddenException('Only the template author or an admin can delete it');
    }
    await this.db.delete(templates).where(eq(templates.id, templateId));
    return { ok: true as const };
  }

  // -------------------------------------------------------------------- groups

  async createGroup(auth: AuthContext, boardId: string, dto: { title: string; color?: string }) {
    await this.ctx.writableBoard(auth, boardId);
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
      .values({ boardId, title: dto.title.trim(), color, position: positionAtEnd(existing.map((g) => g.position)) })
      .returning();

    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'group_created',
      payload: { groupId: group.id, title: group.title },
    });
    const payload = presentGroup(group);
    this.emit(auth, { type: 'group.created', boardId, group: payload });
    return payload;
  }

  async updateGroup(auth: AuthContext, groupId: string, dto: { title?: string; color?: string; collapsed?: boolean }) {
    const group = await this.ctx.writableGroup(auth, groupId);
    if (dto.color !== undefined && !GROUP_COLORS.includes(dto.color)) {
      throw new BadRequestException(`color must be one of: ${GROUP_COLORS.join(', ')}`);
    }

    const patch: Record<string, unknown> = {};
    if (dto.title !== undefined) patch.title = dto.title.trim();
    if (dto.color !== undefined) patch.color = dto.color;
    if (dto.collapsed !== undefined) patch.collapsed = dto.collapsed;
    if (Object.keys(patch).length === 0) return presentGroup(group);

    const [updated] = await this.db.update(groups).set(patch).where(eq(groups.id, groupId)).returning();
    if (dto.title !== undefined && updated.title !== group.title) {
      await this.db.insert(activityLog).values({
        boardId: group.boardId,
        actorUserId: auth.userId,
        event: 'group_renamed',
        payload: { groupId, from: group.title, to: updated.title },
      });
    }
    this.emit(auth, { type: 'group.updated', boardId: group.boardId, groupId, patch: dto });
    return presentGroup(updated);
  }

  /** Deletes a group and, by cascade, its items. Refuses the last group. */
  async deleteGroup(auth: AuthContext, groupId: string) {
    const group = await this.ctx.writableGroup(auth, groupId);
    const [siblings] = await this.db.select({ n: count() }).from(groups).where(eq(groups.boardId, group.boardId));
    if (Number(siblings?.n ?? 0) <= 1) {
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
    return { ok: true as const };
  }

  async moveGroup(auth: AuthContext, groupId: string, afterGroupId: string | null) {
    const group = await this.ctx.writableGroup(auth, groupId);
    const ordered = await this.db
      .select({ id: groups.id, position: groups.position })
      .from(groups)
      .where(eq(groups.boardId, group.boardId))
      .orderBy(asc(groups.position));
    if (afterGroupId && !ordered.some((g) => g.id === afterGroupId)) {
      throw new NotFoundException('afterGroupId is not on this board');
    }

    const { before, after } = neighboursFor(ordered, afterGroupId, groupId);
    if (needsRebalance(before, after)) {
      await this.rebalance(groups, eq(groups.boardId, group.boardId), groupId, afterGroupId);
    } else {
      await this.db.update(groups).set({ position: positionBetween(before, after) }).where(eq(groups.id, groupId));
    }
    this.emit(auth, { type: 'board.updated', boardId: group.boardId, patch: { groupMoved: groupId } });
    return { ok: true as const };
  }

  // ------------------------------------------------------------------- columns

  async createColumn(
    auth: AuthContext,
    boardId: string,
    dto: { type: string; title: string; settings?: Record<string, unknown>; scope?: ColumnScope },
  ) {
    await this.ctx.writableBoard(auth, boardId);
    if (!ALL_COLUMN_TYPES.includes(dto.type as (typeof ALL_COLUMN_TYPES)[number])) {
      throw new BadRequestException(`type must be one of: ${ALL_COLUMN_TYPES.join(', ')}`);
    }
    const scope: ColumnScope = dto.scope ?? 'items';
    const existing = await this.db
      .select({ position: columns.position })
      .from(columns)
      .where(and(eq(columns.boardId, boardId), eq(columns.scope, scope)));

    const settings = dto.settings ? normalizeColumnSettings(dto.type, dto.settings) : defaultSettingsFor(dto.type);
    const [column] = await this.db
      .insert(columns)
      .values({
        boardId,
        type: dto.type as (typeof ALL_COLUMN_TYPES)[number],
        scope,
        title: dto.title.trim(),
        settings,
        position: positionAtEnd(existing.map((c) => c.position)),
      })
      .returning();

    await this.db.insert(activityLog).values({
      boardId,
      actorUserId: auth.userId,
      event: 'column_created',
      payload: { columnId: column.id, type: column.type, title: column.title, scope },
    });
    const payload = presentColumn(column);
    this.emit(auth, { type: 'column.created', boardId, column: payload });
    return payload;
  }

  async updateColumn(
    auth: AuthContext,
    columnId: string,
    dto: { title?: string; settings?: Record<string, unknown>; width?: number },
  ) {
    const column = await this.ctx.writableColumn(auth, columnId);
    const patch: Record<string, unknown> = {};
    if (dto.title !== undefined) patch.title = dto.title.trim();
    if (dto.settings !== undefined) patch.settings = normalizeColumnSettings(column.type, dto.settings);
    if (dto.width !== undefined) patch.width = dto.width;
    if (Object.keys(patch).length === 0) return presentColumn(column);

    const [updated] = await this.db.update(columns).set(patch).where(eq(columns.id, columnId)).returning();
    if (dto.title !== undefined && updated.title !== column.title) {
      await this.db.insert(activityLog).values({
        boardId: column.boardId,
        actorUserId: auth.userId,
        event: 'column_renamed',
        payload: { columnId, from: column.title, to: updated.title },
      });
    }
    this.emit(auth, { type: 'column.updated', boardId: column.boardId, columnId, patch: dto });
    return presentColumn(updated);
  }

  async moveColumn(auth: AuthContext, columnId: string, afterColumnId: string | null) {
    const column = await this.ctx.writableColumn(auth, columnId);
    const ordered = await this.db
      .select({ id: columns.id, position: columns.position })
      .from(columns)
      .where(and(eq(columns.boardId, column.boardId), eq(columns.scope, column.scope)))
      .orderBy(asc(columns.position));
    if (afterColumnId && !ordered.some((c) => c.id === afterColumnId)) {
      throw new NotFoundException('afterColumnId is not a column of the same scope on this board');
    }

    const { before, after } = neighboursFor(ordered, afterColumnId, columnId);
    if (needsRebalance(before, after)) {
      await this.rebalance(columns, and(eq(columns.boardId, column.boardId), eq(columns.scope, column.scope))!, columnId, afterColumnId);
    } else {
      await this.db.update(columns).set({ position: positionBetween(before, after) }).where(eq(columns.id, columnId));
    }
    await this.db.insert(activityLog).values({
      boardId: column.boardId,
      actorUserId: auth.userId,
      event: 'column_moved',
      payload: { columnId, title: column.title, afterColumnId },
    });
    this.emit(auth, { type: 'column.moved', boardId: column.boardId, columnId });
    return { ok: true as const };
  }

  async deleteColumn(auth: AuthContext, columnId: string) {
    const column = await this.ctx.writableColumn(auth, columnId);
    await this.db.delete(columns).where(eq(columns.id, columnId));
    await this.db.insert(activityLog).values({
      boardId: column.boardId,
      actorUserId: auth.userId,
      event: 'column_deleted',
      payload: { columnId, title: column.title, type: column.type },
    });
    this.emit(auth, { type: 'column.deleted', boardId: column.boardId, columnId });
    return { ok: true as const };
  }

  // ------------------------------------------------------------------- helpers

  /** Looks a template key up in the built-in catalog, then in the account's templates. */
  private async resolveTemplate(auth: AuthContext, key: string): Promise<BoardTemplate | undefined> {
    const builtIn = findTemplate(key);
    if (builtIn) return builtIn;
    const [row] = await this.db
      .select({ payload: templates.payload })
      .from(templates)
      .where(and(eq(templates.key, key), eq(templates.accountId, auth.accountId)))
      .limit(1);
    return row ? (row.payload as BoardTemplate) : undefined;
  }

  /** Instantiates a blueprint's columns, groups and items into `boardId`. */
  private async applyTemplate(
    tx: Parameters<Parameters<Database['transaction']>[0]>[0],
    auth: AuthContext,
    boardId: string,
    template: BoardTemplate,
  ): Promise<void> {
    const columnByTitle = new Map<string, { id: string; type: string; settings: ColumnSettings }>();
    const positions: Record<string, number> = { items: 0, subitems: 0 };
    for (const spec of template.columns) {
      const scope: ColumnScope = spec.scope === 'subitems' ? 'subitems' : 'items';
      positions[scope] += 1;
      const settings = spec.settings ? normalizeColumnSettings(spec.type, spec.settings) : defaultSettingsFor(spec.type);
      const [column] = await tx
        .insert(columns)
        .values({
          boardId,
          type: spec.type as typeof columns.$inferInsert.type,
          scope,
          title: spec.title,
          settings,
          position: positions[scope],
        })
        .returning({ id: columns.id, settings: columns.settings });
      if (scope === 'items') {
        columnByTitle.set(spec.title, { id: column.id, type: spec.type, settings: (column.settings ?? {}) as ColumnSettings });
      }
    }

    const groupIds: string[] = [];
    for (const [index, spec] of template.groups.entries()) {
      const [group] = await tx
        .insert(groups)
        .values({ boardId, title: spec.title, color: spec.color, position: index + 1 })
        .returning({ id: groups.id });
      groupIds.push(group.id);
    }
    if (groupIds.length === 0) {
      const [group] = await tx
        .insert(groups)
        .values({ boardId, title: 'Group 1', color: 'blue', position: 1 })
        .returning({ id: groups.id });
      groupIds.push(group.id);
    }

    for (const [index, spec] of template.items.entries()) {
      const groupId = groupIds[spec.group] ?? groupIds[0];
      const [item] = await tx
        .insert(items)
        .values({
          boardId,
          groupId,
          name: spec.name,
          position: index + 1,
          serial: index + 1,
          createdByUserId: auth.userId,
          updatedByUserId: auth.userId,
        })
        .returning({ id: items.id });

      for (const [columnTitle, raw] of Object.entries(spec.cells ?? {})) {
        const column = columnByTitle.get(columnTitle);
        if (!column || column.type === 'files') continue;
        let value: Record<string, unknown> | null;
        try {
          value = normalizeColumnValue(column.type, column.settings, raw);
        } catch {
          continue; // a stale template cell must not block board creation
        }
        if (value === null) continue;
        await tx.insert(columnValues).values({ itemId: item.id, columnId: column.id, value, updatedByUserId: auth.userId });
      }
    }
  }

  /**
   * Renumbers rows of `table` matching `scope` evenly, placing `movedId` after
   * `afterId`. Only runs when midpoints have exhausted float precision.
   */
  private async rebalance(
    table: typeof groups | typeof columns,
    scope: ReturnType<typeof eq>,
    movedId: string,
    afterId: string | null,
  ): Promise<void> {
    const ordered = await this.db.select({ id: table.id }).from(table).where(scope).orderBy(asc(table.position));
    const ids = ordered.map((r) => r.id).filter((id) => id !== movedId);
    const insertAt = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    ids.splice(insertAt, 0, movedId);
    const positions = rebalanced(ids.length);
    await this.db.transaction(async (tx) => {
      for (const [index, id] of ids.entries()) {
        await tx.update(table).set({ position: positions[index] }).where(eq(table.id, id));
      }
    });
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
}

/** Rewrites column/group ids inside a duplicated view's config. */
export function remapViewConfig(
  config: unknown,
  columnIdMap: Map<string, string>,
  groupIdMap: Map<string, string>,
): Record<string, unknown> {
  if (typeof config !== 'object' || config === null) return {};
  const source = config as Record<string, unknown>;
  const mapField = (field: unknown) =>
    typeof field === 'string' ? (columnIdMap.get(field) ?? field) : field;
  const mapRule = (rule: unknown) => {
    if (typeof rule !== 'object' || rule === null) return rule;
    const r = { ...(rule as Record<string, unknown>) };
    r.field = mapField(r.field);
    if (r.field === 'group' && Array.isArray(r.value)) {
      r.value = r.value.map((id) => (typeof id === 'string' ? (groupIdMap.get(id) ?? id) : id));
    }
    return r;
  };
  const out: Record<string, unknown> = { ...source };
  if (typeof source.filters === 'object' && source.filters !== null) {
    const filters = source.filters as Record<string, unknown>;
    out.filters = { ...filters, rules: Array.isArray(filters.rules) ? filters.rules.map(mapRule) : [] };
  }
  if (Array.isArray(source.sort)) out.sort = source.sort.map(mapRule);
  if (Array.isArray(source.conditionalColors)) out.conditionalColors = source.conditionalColors.map(mapRule);
  if (Array.isArray(source.hiddenColumnIds)) out.hiddenColumnIds = source.hiddenColumnIds.map(mapField);
  if (Array.isArray(source.columnOrder)) out.columnOrder = source.columnOrder.map(mapField);
  if (typeof source.laneColumnId === 'string') out.laneColumnId = mapField(source.laneColumnId);
  if (typeof source.dateColumnId === 'string') out.dateColumnId = mapField(source.dateColumnId);
  return out;
}

function hashCode(input: string): number {
  let hash = 0;
  for (const ch of input) hash = (hash * 31 + ch.charCodeAt(0)) | 0;
  return hash;
}

/** Re-exported so callers that only need the live predicates import one module. */
export { boardIsLive, itemIsLive, isNotNull };
