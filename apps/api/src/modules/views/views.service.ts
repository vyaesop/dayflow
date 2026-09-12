import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, eq, ne } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardIsLive } from '../../db/live';
import { boards, boardViews, columns, groups } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardContextService } from '../access/board-context.service';
import { neighboursFor, needsRebalance, positionAtEnd, positionBetween, rebalanced } from '../boards/positioning';
import { presentView, type ViewPayload } from '../boards/boards.service';
import { validateViewConfig, type ViewConfig } from '../boards/view-query';
import { RealtimeGateway } from '../realtime/realtime.gateway';

export type ViewType = 'table' | 'list' | 'kanban' | 'calendar' | 'dashboard';

/**
 * Saved views: named, per-board, shared by everyone on the board. Each view
 * stores its filters, sort, hidden columns, conditional colors and the
 * type-specific settings (kanban lane column, calendar date column).
 */
@Injectable()
export class ViewsService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly ctx: BoardContextService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async list(auth: AuthContext, boardId: string): Promise<ViewPayload[]> {
    await this.ctx.visibleBoard(auth, boardId);
    const rows = await this.db
      .select()
      .from(boardViews)
      .where(eq(boardViews.boardId, boardId))
      .orderBy(asc(boardViews.position));
    return rows.map(presentView);
  }

  async create(
    auth: AuthContext,
    boardId: string,
    dto: { type: ViewType; name: string; config?: unknown; isDefault?: boolean },
  ): Promise<ViewPayload> {
    await this.ctx.writableBoard(auth, boardId);
    const config = await this.validated(boardId, dto.config ?? {});
    const existing = await this.db
      .select({ position: boardViews.position })
      .from(boardViews)
      .where(eq(boardViews.boardId, boardId));

    const view = await this.db.transaction(async (tx) => {
      if (dto.isDefault) {
        await tx.update(boardViews).set({ isDefault: false }).where(eq(boardViews.boardId, boardId));
      }
      const [row] = await tx
        .insert(boardViews)
        .values({
          boardId,
          type: dto.type,
          name: dto.name.trim(),
          config,
          isDefault: dto.isDefault ?? existing.length === 0,
          position: positionAtEnd(existing.map((v) => v.position)),
          createdByUserId: auth.userId,
        })
        .returning();
      return row;
    });
    this.changed(auth, boardId);
    return presentView(view);
  }

  async update(
    auth: AuthContext,
    viewId: string,
    dto: { name?: string; config?: unknown; isDefault?: boolean },
  ): Promise<ViewPayload> {
    const view = await this.writableView(auth, viewId);
    const patch: Partial<typeof boardViews.$inferInsert> = { updatedAt: new Date() };
    if (dto.name !== undefined) patch.name = dto.name.trim();
    if (dto.config !== undefined) patch.config = await this.validated(view.boardId, dto.config);
    if (dto.isDefault === false && view.isDefault) {
      throw new BadRequestException('Pick another view as the default instead of unsetting this one');
    }

    const updated = await this.db.transaction(async (tx) => {
      if (dto.isDefault === true) {
        await tx.update(boardViews).set({ isDefault: false }).where(and(eq(boardViews.boardId, view.boardId), ne(boardViews.id, viewId)));
        patch.isDefault = true;
      }
      const [row] = await tx.update(boardViews).set(patch).where(eq(boardViews.id, viewId)).returning();
      return row;
    });
    this.changed(auth, view.boardId);
    return presentView(updated);
  }

  async move(auth: AuthContext, viewId: string, afterViewId: string | null): Promise<{ ok: true }> {
    const view = await this.writableView(auth, viewId);
    const ordered = await this.db
      .select({ id: boardViews.id, position: boardViews.position })
      .from(boardViews)
      .where(eq(boardViews.boardId, view.boardId))
      .orderBy(asc(boardViews.position));
    if (afterViewId && !ordered.some((v) => v.id === afterViewId)) {
      throw new NotFoundException('afterViewId is not a view of this board');
    }
    const { before, after } = neighboursFor(ordered, afterViewId, viewId);
    if (needsRebalance(before, after)) {
      const ids = ordered.map((v) => v.id).filter((id) => id !== viewId);
      ids.splice(afterViewId === null ? 0 : ids.indexOf(afterViewId) + 1, 0, viewId);
      const positions = rebalanced(ids.length);
      await this.db.transaction(async (tx) => {
        for (const [index, id] of ids.entries()) {
          await tx.update(boardViews).set({ position: positions[index] }).where(eq(boardViews.id, id));
        }
      });
    } else {
      await this.db.update(boardViews).set({ position: positionBetween(before, after) }).where(eq(boardViews.id, viewId));
    }
    this.changed(auth, view.boardId);
    return { ok: true };
  }

  async duplicate(auth: AuthContext, viewId: string): Promise<ViewPayload> {
    const view = await this.writableView(auth, viewId);
    const ordered = await this.db
      .select({ id: boardViews.id, position: boardViews.position })
      .from(boardViews)
      .where(eq(boardViews.boardId, view.boardId))
      .orderBy(asc(boardViews.position));
    const { before, after } = neighboursFor(ordered, viewId);
    const [copy] = await this.db
      .insert(boardViews)
      .values({
        boardId: view.boardId,
        type: view.type,
        name: `${view.name} (copy)`.slice(0, 120),
        config: view.config,
        isDefault: false,
        position: positionBetween(before, after),
        createdByUserId: auth.userId,
      })
      .returning();
    this.changed(auth, view.boardId);
    return presentView(copy);
  }

  /** Refuses the last view; deleting the default promotes the first remaining one. */
  async remove(auth: AuthContext, viewId: string): Promise<{ ok: true }> {
    const view = await this.writableView(auth, viewId);
    const siblings = await this.db
      .select({ id: boardViews.id })
      .from(boardViews)
      .where(eq(boardViews.boardId, view.boardId))
      .orderBy(asc(boardViews.position));
    if (siblings.length <= 1) throw new BadRequestException('A board must keep at least one view');

    await this.db.transaction(async (tx) => {
      await tx.delete(boardViews).where(eq(boardViews.id, viewId));
      if (view.isDefault) {
        const next = siblings.find((v) => v.id !== viewId)!;
        await tx.update(boardViews).set({ isDefault: true }).where(eq(boardViews.id, next.id));
      }
    });
    this.changed(auth, view.boardId);
    return { ok: true };
  }

  /** The stored config with its column references validated against the board. */
  async configFor(boardId: string, viewId: string): Promise<ViewConfig> {
    const [view] = await this.db
      .select({ config: boardViews.config, boardId: boardViews.boardId })
      .from(boardViews)
      .where(eq(boardViews.id, viewId))
      .limit(1);
    if (!view || view.boardId !== boardId) throw new NotFoundException('View not found on this board');
    return this.validated(boardId, view.config ?? {});
  }

  private async validated(boardId: string, config: unknown): Promise<ViewConfig> {
    const [cols, groupRows] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, boardId)),
      this.db.select({ id: groups.id }).from(groups).where(eq(groups.boardId, boardId)),
    ]);
    return validateViewConfig(
      config,
      cols.map((c) => ({ id: c.id, type: c.type, title: c.title, settings: c.settings, position: c.position, scope: c.scope })),
      groupRows.map((g) => g.id),
    );
  }

  private async writableView(auth: AuthContext, viewId: string) {
    const [row] = await this.db
      .select({ view: boardViews })
      .from(boardViews)
      .innerJoin(boards, eq(boardViews.boardId, boards.id))
      .where(and(eq(boardViews.id, viewId), eq(boards.accountId, auth.accountId), boardIsLive()))
      .limit(1);
    if (!row) throw new NotFoundException('View not found');
    await this.ctx.writableBoard(auth, row.view.boardId);
    return row.view;
  }

  private changed(auth: AuthContext, boardId: string): void {
    this.realtime.publish({ type: 'views.changed', boardId }, { accountId: auth.accountId, exceptUserId: auth.userId });
  }
}
