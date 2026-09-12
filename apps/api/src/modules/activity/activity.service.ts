import { BadRequestException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, desc, eq, gte, inArray, isNull, lt, lte, or, sql } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { activityLog, boards, columns, groups, items, userProfiles } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardContextService } from '../access/board-context.service';
import { BoardWritesService } from '../boards/board-writes.service';
import { ItemWritesService } from '../boards/item-writes.service';

export const UNDO_WINDOW_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Events the 7-day undo knows how to invert. */
export const UNDOABLE_EVENTS = new Set([
  'column_value_changed',
  'item_renamed',
  'item_moved',
  'item_archived',
  'item_trashed',
  'group_renamed',
  'board_renamed',
  'column_renamed',
]);

export interface ActivityEntry {
  id: string;
  event: string;
  payload: unknown;
  actor: { userId: string; fullName: string; avatarUrl: string | null } | null;
  item: { id: string; name: string } | null;
  column: { id: string; title: string; type: string } | null;
  createdAt: string;
  undoable: boolean;
  undoneAt: string | null;
}

export interface ActivityFilter {
  event?: string;
  actorId?: string;
  itemId?: string;
  from?: string;
  to?: string;
  cursor?: string;
  limit?: number;
}

/**
 * Board-level activity feed with filters, keyset pagination and undo. Undo
 * runs the inverse operation through the normal write services so it logs,
 * emits realtime events and notifies exactly like a manual change would.
 */
@Injectable()
export class ActivityService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly ctx: BoardContextService,
    private readonly boardWrites: BoardWritesService,
    private readonly itemWrites: ItemWritesService,
  ) {}

  async list(auth: AuthContext, boardId: string, filter: ActivityFilter): Promise<{ entries: ActivityEntry[]; nextCursor: string | null }> {
    await this.ctx.visibleBoard(auth, boardId, { includeInactive: true });
    const limit = Math.min(Math.max(filter.limit ?? 50, 1), 200);
    const conditions = [eq(activityLog.boardId, boardId)];
    if (filter.event) conditions.push(eq(activityLog.event, filter.event as typeof activityLog.$inferSelect.event));
    if (filter.actorId) conditions.push(eq(activityLog.actorUserId, filter.actorId));
    if (filter.itemId) conditions.push(eq(activityLog.itemId, filter.itemId));
    if (filter.from) conditions.push(gte(activityLog.createdAt, parseDate(filter.from, 'from')));
    if (filter.to) conditions.push(lte(activityLog.createdAt, endOfDay(parseDate(filter.to, 'to'))));
    if (filter.cursor) {
      // The cursor carries the row's own microsecond timestamp, so the
      // comparison never loses precision the way a JS Date (ms) would.
      const { createdAt, id } = decodeCursor(filter.cursor);
      const stamp = sql`${createdAt}::timestamptz`;
      conditions.push(
        or(lt(activityLog.createdAt, stamp), and(eq(activityLog.createdAt, stamp), lt(activityLog.id, id)))!,
      );
    }

    const rows = await this.db
      .select({
        entry: activityLog,
        createdAtExact: sql<string>`to_json(${activityLog.createdAt})#>>'{}'`,
        actorName: userProfiles.fullName,
        actorAvatar: userProfiles.avatarUrl,
        itemName: items.name,
      })
      .from(activityLog)
      .leftJoin(userProfiles, eq(activityLog.actorUserId, userProfiles.userId))
      .leftJoin(items, eq(activityLog.itemId, items.id))
      .where(and(...conditions))
      .orderBy(desc(activityLog.createdAt), desc(activityLog.id))
      .limit(limit + 1);

    const page = rows.slice(0, limit);
    const columnIds = [
      ...new Set(page.map((r) => (r.entry.payload as { columnId?: string })?.columnId).filter((id): id is string => !!id)),
    ];
    const columnRows = columnIds.length
      ? await this.db.select({ id: columns.id, title: columns.title, type: columns.type }).from(columns).where(inArray(columns.id, columnIds))
      : [];
    const columnById = new Map(columnRows.map((c) => [c.id, c]));

    const entries = page.map((r) => this.present(r.entry, r.actorName, r.actorAvatar, r.itemName, columnById));
    const last = page.at(-1);
    return {
      entries,
      nextCursor: rows.length > limit && last ? encodeCursor(last.createdAtExact, last.entry.id) : null,
    };
  }

  /** Reverts one entry within the undo window. */
  async undo(auth: AuthContext, entryId: string): Promise<{ ok: true; event: string }> {
    const [row] = await this.db
      .select({ entry: activityLog })
      .from(activityLog)
      .innerJoin(boards, eq(activityLog.boardId, boards.id))
      .where(and(eq(activityLog.id, entryId), eq(boards.accountId, auth.accountId)))
      .limit(1);
    if (!row) throw new NotFoundException('Activity entry not found');
    const entry = row.entry;
    await this.ctx.writableBoard(auth, entry.boardId);

    if (!UNDOABLE_EVENTS.has(entry.event)) throw new BadRequestException('This kind of change cannot be undone');
    if (entry.undoneAt) throw new BadRequestException('This change was already undone');
    if (Date.now() - entry.createdAt.getTime() > UNDO_WINDOW_DAYS * DAY_MS) {
      throw new BadRequestException(`Changes can only be undone within ${UNDO_WINDOW_DAYS} days`);
    }
    // Only the most recent change to the same target may be undone, otherwise
    // an older undo would silently clobber newer edits.
    await this.assertLatestForTarget(entry);

    const payload = (entry.payload ?? {}) as Record<string, unknown>;
    switch (entry.event) {
      case 'column_value_changed': {
        if (!entry.itemId || typeof payload.columnId !== 'string') throw new BadRequestException('Nothing to undo');
        await this.itemWrites.setCellValue(auth, entry.itemId, payload.columnId, payload.from ?? null);
        break;
      }
      case 'item_renamed': {
        if (!entry.itemId || typeof payload.from !== 'string') throw new BadRequestException('Nothing to undo');
        await this.itemWrites.renameItem(auth, entry.itemId, payload.from);
        break;
      }
      case 'item_moved': {
        if (!entry.itemId || typeof payload.from !== 'string') throw new BadRequestException('Nothing to undo');
        const [group] = await this.db.select({ id: groups.id }).from(groups).where(eq(groups.id, payload.from)).limit(1);
        if (!group) throw new BadRequestException('The original group no longer exists');
        await this.itemWrites.moveItem(auth, entry.itemId, { groupId: payload.from });
        break;
      }
      case 'item_archived':
      case 'item_trashed': {
        if (!entry.itemId) throw new BadRequestException('Nothing to undo');
        await this.itemWrites.restoreItem(auth, entry.itemId);
        break;
      }
      case 'group_renamed': {
        if (typeof payload.groupId !== 'string' || typeof payload.from !== 'string') throw new BadRequestException('Nothing to undo');
        await this.boardWrites.updateGroup(auth, payload.groupId, { title: payload.from });
        break;
      }
      case 'board_renamed': {
        if (typeof payload.from !== 'string') throw new BadRequestException('Nothing to undo');
        await this.boardWrites.updateBoard(auth, entry.boardId, { name: payload.from });
        break;
      }
      case 'column_renamed': {
        if (typeof payload.columnId !== 'string' || typeof payload.from !== 'string') throw new BadRequestException('Nothing to undo');
        await this.boardWrites.updateColumn(auth, payload.columnId, { title: payload.from });
        break;
      }
    }

    await this.db
      .update(activityLog)
      .set({ undoneAt: new Date(), undoneByUserId: auth.userId })
      .where(eq(activityLog.id, entryId));
    await this.db.insert(activityLog).values({
      boardId: entry.boardId,
      itemId: entry.itemId,
      actorUserId: auth.userId,
      event: 'activity_undone',
      payload: { entryId, event: entry.event, ...('columnId' in payload ? { columnId: payload.columnId } : {}) },
    });
    return { ok: true, event: entry.event };
  }

  /** Item-scoped feed for the item card, same shape as the board feed. */
  async forItem(itemId: string, limit = 50): Promise<ActivityEntry[]> {
    const rows = await this.db
      .select({
        entry: activityLog,
        actorName: userProfiles.fullName,
        actorAvatar: userProfiles.avatarUrl,
        itemName: items.name,
      })
      .from(activityLog)
      .leftJoin(userProfiles, eq(activityLog.actorUserId, userProfiles.userId))
      .leftJoin(items, eq(activityLog.itemId, items.id))
      .where(eq(activityLog.itemId, itemId))
      .orderBy(desc(activityLog.createdAt), desc(activityLog.id))
      .limit(limit);
    const columnIds = [
      ...new Set(rows.map((r) => (r.entry.payload as { columnId?: string })?.columnId).filter((id): id is string => !!id)),
    ];
    const columnRows = columnIds.length
      ? await this.db.select({ id: columns.id, title: columns.title, type: columns.type }).from(columns).where(inArray(columns.id, columnIds))
      : [];
    const columnById = new Map(columnRows.map((c) => [c.id, c]));
    return rows.map((r) => this.present(r.entry, r.actorName, r.actorAvatar, r.itemName, columnById));
  }

  private present(
    entry: typeof activityLog.$inferSelect,
    actorName: string | null,
    actorAvatar: string | null,
    itemName: string | null,
    columnById: Map<string, { id: string; title: string; type: string }>,
  ): ActivityEntry {
    const payload = (entry.payload ?? {}) as Record<string, unknown>;
    const column = typeof payload.columnId === 'string' ? columnById.get(payload.columnId) ?? null : null;
    return {
      id: entry.id,
      event: entry.event,
      payload,
      actor: entry.actorUserId ? { userId: entry.actorUserId, fullName: actorName ?? '', avatarUrl: actorAvatar } : null,
      item: entry.itemId ? { id: entry.itemId, name: itemName ?? (payload.name as string) ?? '' } : null,
      column,
      createdAt: entry.createdAt.toISOString(),
      undoable:
        UNDOABLE_EVENTS.has(entry.event) &&
        !entry.undoneAt &&
        Date.now() - entry.createdAt.getTime() <= UNDO_WINDOW_DAYS * DAY_MS,
      undoneAt: entry.undoneAt?.toISOString() ?? null,
    };
  }

  /** A newer, not-undone change to the same target blocks undoing an older one. */
  private async assertLatestForTarget(entry: typeof activityLog.$inferSelect): Promise<void> {
    const payload = (entry.payload ?? {}) as Record<string, unknown>;
    const sameTarget = (() => {
      switch (entry.event) {
        case 'column_value_changed':
          return and(
            eq(activityLog.itemId, entry.itemId!),
            eq(activityLog.event, 'column_value_changed'),
            sql`${activityLog.payload}->>'columnId' = ${payload.columnId as string}`,
          );
        case 'item_renamed':
        case 'item_moved':
          return and(eq(activityLog.itemId, entry.itemId!), eq(activityLog.event, entry.event));
        case 'group_renamed':
          return and(eq(activityLog.event, 'group_renamed'), sql`${activityLog.payload}->>'groupId' = ${payload.groupId as string}`);
        case 'column_renamed':
          return and(eq(activityLog.event, 'column_renamed'), sql`${activityLog.payload}->>'columnId' = ${payload.columnId as string}`);
        case 'board_renamed':
          return eq(activityLog.event, 'board_renamed');
        default:
          return null;
      }
    })();
    if (!sameTarget) return;
    // Compare against the row's own stored timestamp (microseconds) rather
    // than the JS Date, which would truncate to milliseconds and match itself.
    const own = sql`(select created_at from activity_log where id = ${entry.id})`;
    const [newer] = await this.db
      .select({ id: activityLog.id })
      .from(activityLog)
      .where(
        and(
          eq(activityLog.boardId, entry.boardId),
          sameTarget,
          isNull(activityLog.undoneAt),
          sql`${activityLog.id} <> ${entry.id}`,
          or(
            sql`${activityLog.createdAt} > ${own}`,
            and(sql`${activityLog.createdAt} = ${own}`, sql`${activityLog.id} > ${entry.id}`),
          ),
        ),
      )
      .limit(1);
    if (newer) throw new BadRequestException('A newer change to the same field exists; undo that one first');
  }
}

function parseDate(value: string, field: string): Date {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new BadRequestException(`${field} must be an ISO date`);
  return date;
}

function endOfDay(date: Date): Date {
  // A bare date means "through the end of that day".
  if (date.getUTCHours() === 0 && date.getUTCMinutes() === 0 && date.getUTCSeconds() === 0 && date.getUTCMilliseconds() === 0) {
    return new Date(date.getTime() + DAY_MS - 1);
  }
  return date;
}

function encodeCursor(createdAtExact: string, id: string): string {
  return Buffer.from(`${createdAtExact}|${id}`).toString('base64url');
}

function decodeCursor(cursor: string): { createdAt: string; id: string } {
  const raw = Buffer.from(cursor, 'base64url').toString('utf8');
  const [iso, id] = raw.split('|');
  if (!id || !iso || Number.isNaN(new Date(iso).getTime())) throw new BadRequestException('Invalid cursor');
  return { createdAt: iso, id };
}
