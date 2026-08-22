import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, desc, eq, inArray, isNull } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import {
  accountMembers,
  activityLog,
  boards,
  columns,
  columnValues,
  groups,
  items,
  notifications,
  updateBookmarks,
  updateLikes,
  updates,
  userProfiles,
  workspaces,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

export interface ItemDetailPayload {
  id: string;
  name: string;
  board: { id: string; name: string };
  group: { id: string; title: string; color: string };
  workspaceName: string;
  createdAt: string;
  values: Record<string, unknown>;
  columns: Array<{ id: string; type: string; title: string; settings: unknown; position: number }>;
  updates: UpdatePayload[];
  activity: ActivityPayload[];
}

export interface UpdatePayload {
  id: string;
  body: string;
  author: { userId: string; fullName: string; avatarUrl: string | null };
  createdAt: string;
  editedAt: string | null;
  likesCount: number;
  likedByMe: boolean;
  bookmarkedByMe: boolean;
  replies: UpdatePayload[];
}

export interface FeedEntry extends UpdatePayload {
  boardId: string;
  boardName: string;
  itemId: string | null;
  itemName: string | null;
}

export interface ActivityPayload {
  id: string;
  event: string;
  payload: unknown;
  actor: { userId: string; fullName: string } | null;
  createdAt: string;
}

@Injectable()
export class ItemsService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  async getItem(auth: AuthContext, itemId: string): Promise<ItemDetailPayload> {
    const [row] = await this.db
      .select({
        id: items.id,
        name: items.name,
        createdAt: items.createdAt,
        boardId: boards.id,
        boardName: boards.name,
        groupId: groups.id,
        groupTitle: groups.title,
        groupColor: groups.color,
        workspaceName: workspaces.name,
      })
      .from(items)
      .innerJoin(boards, eq(items.boardId, boards.id))
      .innerJoin(groups, eq(items.groupId, groups.id))
      .innerJoin(workspaces, eq(boards.workspaceId, workspaces.id))
      .where(and(eq(items.id, itemId), eq(boards.accountId, auth.accountId), isNull(items.archivedAt)))
      .limit(1);
    if (!row) throw new NotFoundException('Item not found');

    const [cols, valueRows, updateRows, activityRows] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, row.boardId)).orderBy(asc(columns.position)),
      this.db.select().from(columnValues).where(eq(columnValues.itemId, itemId)),
      this.hydratedUpdates(auth, eq(updates.itemId, itemId)),
      this.db
        .select({
          id: activityLog.id,
          event: activityLog.event,
          payload: activityLog.payload,
          createdAt: activityLog.createdAt,
          actorUserId: activityLog.actorUserId,
          actorName: userProfiles.fullName,
        })
        .from(activityLog)
        .leftJoin(userProfiles, eq(activityLog.actorUserId, userProfiles.userId))
        .where(eq(activityLog.itemId, itemId))
        .orderBy(desc(activityLog.createdAt))
        .limit(50),
    ]);

    const values: Record<string, unknown> = {};
    for (const v of valueRows) values[v.columnId] = v.value;

    return {
      id: row.id,
      name: row.name,
      board: { id: row.boardId, name: row.boardName },
      group: { id: row.groupId, title: row.groupTitle, color: row.groupColor },
      workspaceName: row.workspaceName,
      createdAt: row.createdAt.toISOString(),
      values,
      columns: cols.map((c) => ({
        id: c.id,
        type: c.type,
        title: c.title,
        settings: c.settings,
        position: c.position,
      })),
      updates: updateRows,
      activity: activityRows.map((a) => ({
        id: a.id,
        event: a.event,
        payload: a.payload,
        actor: a.actorUserId ? { userId: a.actorUserId, fullName: a.actorName ?? '' } : null,
        createdAt: a.createdAt.toISOString(),
      })),
    };
  }

  /**
   * Posts an update on an item. `@mentions` are resolved against account
   * members and notified.
   */
  async addUpdate(auth: AuthContext, itemId: string, body: string, parentId?: string): Promise<UpdatePayload> {
    const item = await this.itemForWrite(auth, itemId);
    const mentioned = await this.resolveMentions(auth, body);

    // A reply must target a top-level update on the same item.
    let parentAuthorId: string | null = null;
    if (parentId) {
      const [parent] = await this.db
        .select({ id: updates.id, itemId: updates.itemId, parentId: updates.parentId, authorUserId: updates.authorUserId })
        .from(updates)
        .where(eq(updates.id, parentId))
        .limit(1);
      if (!parent || parent.itemId !== itemId) throw new NotFoundException('Update to reply to not found');
      if (parent.parentId) throw new BadRequestException('Replies cannot be nested further');
      parentAuthorId = parent.authorUserId;
    }

    const [profile] = await this.db
      .select({ fullName: userProfiles.fullName, avatarUrl: userProfiles.avatarUrl })
      .from(userProfiles)
      .where(eq(userProfiles.userId, auth.userId))
      .limit(1);

    const [created] = await this.db
      .insert(updates)
      .values({
        boardId: item.boardId,
        itemId,
        authorUserId: auth.userId,
        parentId: parentId ?? null,
        // The rich-text editor is not built yet; store a single paragraph so the
        // document shape is already forward-compatible.
        body: { type: 'doc', content: [{ type: 'paragraph', text: body }] },
        bodyText: body,
        mentionedUserIds: mentioned,
      })
      .returning();

    // Replying notifies the parent author (never yourself).
    if (parentAuthorId && parentAuthorId !== auth.userId) {
      await this.db.insert(notifications).values({
        accountId: auth.accountId,
        userId: parentAuthorId,
        type: 'reply',
        actorUserId: auth.userId,
        payload: {
          boardId: item.boardId,
          itemId,
          itemName: item.name,
          updateId: created.id,
          snippet: body.slice(0, 140),
        },
      });
    }

    if (mentioned.length) {
      const [board] = await this.db
        .select({ name: boards.name })
        .from(boards)
        .where(eq(boards.id, item.boardId))
        .limit(1);
      await this.db.insert(notifications).values(
        mentioned.map((userId) => ({
          accountId: auth.accountId,
          userId,
          type: 'mention' as const,
          actorUserId: auth.userId,
          payload: {
            boardId: item.boardId,
            boardName: board?.name ?? '',
            itemId,
            itemName: item.name,
            updateId: created.id,
            snippet: body.slice(0, 140),
          },
        })),
      );
    }

    return {
      id: created.id,
      body: created.bodyText,
      author: {
        userId: auth.userId,
        fullName: profile?.fullName ?? '',
        avatarUrl: profile?.avatarUrl ?? null,
      },
      createdAt: created.createdAt.toISOString(),
      editedAt: null,
      likesCount: 0,
      likedByMe: false,
      bookmarkedByMe: false,
      replies: [],
    };
  }

  async editUpdate(auth: AuthContext, updateId: string, body: string): Promise<{ ok: true }> {
    const [row] = await this.db
      .select({ id: updates.id, authorUserId: updates.authorUserId })
      .from(updates)
      .innerJoin(boards, eq(updates.boardId, boards.id))
      .where(and(eq(updates.id, updateId), eq(boards.accountId, auth.accountId)))
      .limit(1);
    if (!row) throw new NotFoundException('Update not found');
    if (row.authorUserId !== auth.userId) {
      throw new ForbiddenException('You can only edit your own updates');
    }

    await this.db
      .update(updates)
      .set({
        body: { type: 'doc', content: [{ type: 'paragraph', text: body }] },
        bodyText: body,
        editedAt: new Date(),
      })
      .where(eq(updates.id, updateId));
    return { ok: true };
  }

  async toggleLike(auth: AuthContext, updateId: string): Promise<{ liked: boolean; likesCount: number }> {
    await this.updateInAccount(auth, updateId);
    const [existing] = await this.db
      .select({ id: updateLikes.id })
      .from(updateLikes)
      .where(and(eq(updateLikes.updateId, updateId), eq(updateLikes.userId, auth.userId)))
      .limit(1);

    if (existing) {
      await this.db.delete(updateLikes).where(eq(updateLikes.id, existing.id));
    } else {
      await this.db.insert(updateLikes).values({ updateId, userId: auth.userId });
    }

    const [likes] = await this.db
      .select({ n: count() })
      .from(updateLikes)
      .where(eq(updateLikes.updateId, updateId));
    return { liked: !existing, likesCount: Number(likes?.n ?? 0) };
  }

  async toggleBookmark(auth: AuthContext, updateId: string): Promise<{ bookmarked: boolean }> {
    await this.updateInAccount(auth, updateId);
    const [existing] = await this.db
      .select({ id: updateBookmarks.id })
      .from(updateBookmarks)
      .where(and(eq(updateBookmarks.updateId, updateId), eq(updateBookmarks.userId, auth.userId)))
      .limit(1);

    if (existing) {
      await this.db.delete(updateBookmarks).where(eq(updateBookmarks.id, existing.id));
      return { bookmarked: false };
    }
    await this.db.insert(updateBookmarks).values({ updateId, userId: auth.userId });
    return { bookmarked: true };
  }

  /**
   * Company-wide update feed: top-level updates across every board in the
   * account, optionally narrowed to one board or to bookmarks only.
   */
  async updateFeed(
    auth: AuthContext,
    filter: { boardId?: string; bookmarked?: boolean },
  ): Promise<FeedEntry[]> {
    const conditions = [eq(boards.accountId, auth.accountId), isNull(updates.parentId)];
    if (filter.boardId) conditions.push(eq(updates.boardId, filter.boardId));

    const rows = await this.db
      .select({
        update: updates,
        authorName: userProfiles.fullName,
        authorAvatar: userProfiles.avatarUrl,
        boardName: boards.name,
        itemName: items.name,
      })
      .from(updates)
      .innerJoin(boards, eq(updates.boardId, boards.id))
      .innerJoin(userProfiles, eq(updates.authorUserId, userProfiles.userId))
      .leftJoin(items, eq(updates.itemId, items.id))
      .where(and(...conditions))
      .orderBy(desc(updates.createdAt))
      .limit(50);

    const hydrated = await this.decorate(auth, rows.map((r) => ({
      id: r.update.id,
      bodyText: r.update.bodyText,
      createdAt: r.update.createdAt,
      editedAt: r.update.editedAt,
      parentId: r.update.parentId,
      authorUserId: r.update.authorUserId,
      authorName: r.authorName,
      authorAvatar: r.authorAvatar,
    })));

    const entries: FeedEntry[] = rows.map((r, index) => ({
      ...hydrated[index],
      boardId: r.update.boardId,
      boardName: r.boardName,
      itemId: r.update.itemId,
      itemName: r.itemName,
    }));

    return filter.bookmarked ? entries.filter((e) => e.bookmarkedByMe) : entries;
  }

  async deleteUpdate(auth: AuthContext, updateId: string): Promise<{ ok: true }> {
    const [row] = await this.db
      .select({ id: updates.id, authorUserId: updates.authorUserId })
      .from(updates)
      .innerJoin(boards, eq(updates.boardId, boards.id))
      .where(and(eq(updates.id, updateId), eq(boards.accountId, auth.accountId)))
      .limit(1);
    if (!row) throw new NotFoundException('Update not found');
    // Authors delete their own; admins can remove anyone's.
    if (row.authorUserId !== auth.userId && auth.role !== 'admin') {
      throw new ForbiddenException('You can only delete your own updates');
    }

    // Replies have no FK to their parent, so remove them explicitly.
    await this.db.delete(updates).where(eq(updates.parentId, updateId));
    await this.db.delete(updates).where(eq(updates.id, updateId));
    return { ok: true };
  }

  // ------------------------------------------------------------ update helpers

  private async updateInAccount(auth: AuthContext, updateId: string): Promise<void> {
    const [row] = await this.db
      .select({ id: updates.id })
      .from(updates)
      .innerJoin(boards, eq(updates.boardId, boards.id))
      .where(and(eq(updates.id, updateId), eq(boards.accountId, auth.accountId)))
      .limit(1);
    if (!row) throw new NotFoundException('Update not found');
  }

  private async hydratedUpdates(
    auth: AuthContext,
    where: ReturnType<typeof eq>,
  ): Promise<UpdatePayload[]> {
    const rows = await this.db
      .select({
        id: updates.id,
        bodyText: updates.bodyText,
        createdAt: updates.createdAt,
        editedAt: updates.editedAt,
        parentId: updates.parentId,
        authorUserId: updates.authorUserId,
        authorName: userProfiles.fullName,
        authorAvatar: userProfiles.avatarUrl,
      })
      .from(updates)
      .innerJoin(userProfiles, eq(updates.authorUserId, userProfiles.userId))
      .where(where)
      .orderBy(desc(updates.createdAt));

    const decorated = await this.decorate(auth, rows);
    const byId = new Map(rows.map((r, index) => [r.id, decorated[index]]));

    // Thread replies under their parents; replies read oldest-first.
    const parents: UpdatePayload[] = [];
    for (const [index, row] of rows.entries()) {
      if (!row.parentId) parents.push(decorated[index]);
    }
    for (const [index, row] of [...rows.entries()].reverse()) {
      if (row.parentId) byId.get(row.parentId)?.replies.push(decorated[index]);
    }
    return parents;
  }

  /** Attaches like counts and the caller's like/bookmark state. */
  private async decorate(
    auth: AuthContext,
    rows: Array<{
      id: string;
      bodyText: string;
      createdAt: Date;
      editedAt: Date | null;
      authorUserId: string;
      authorName: string;
      authorAvatar: string | null;
    }>,
  ): Promise<UpdatePayload[]> {
    if (rows.length === 0) return [];
    const ids = rows.map((r) => r.id);

    const [likeCounts, myLikes, myBookmarks] = await Promise.all([
      this.db
        .select({ updateId: updateLikes.updateId, n: count() })
        .from(updateLikes)
        .where(inArray(updateLikes.updateId, ids))
        .groupBy(updateLikes.updateId),
      this.db
        .select({ updateId: updateLikes.updateId })
        .from(updateLikes)
        .where(and(inArray(updateLikes.updateId, ids), eq(updateLikes.userId, auth.userId))),
      this.db
        .select({ updateId: updateBookmarks.updateId })
        .from(updateBookmarks)
        .where(and(inArray(updateBookmarks.updateId, ids), eq(updateBookmarks.userId, auth.userId))),
    ]);

    const counts = new Map(likeCounts.map((l) => [l.updateId, Number(l.n)]));
    const liked = new Set(myLikes.map((l) => l.updateId));
    const bookmarked = new Set(myBookmarks.map((b) => b.updateId));

    return rows.map((r) => ({
      id: r.id,
      body: r.bodyText,
      author: { userId: r.authorUserId, fullName: r.authorName, avatarUrl: r.authorAvatar },
      createdAt: r.createdAt.toISOString(),
      editedAt: r.editedAt?.toISOString() ?? null,
      likesCount: counts.get(r.id) ?? 0,
      likedByMe: liked.has(r.id),
      bookmarkedByMe: bookmarked.has(r.id),
      replies: [],
    }));
  }

  private async itemForWrite(auth: AuthContext, itemId: string) {
    const [row] = await this.db
      .select({ id: items.id, boardId: items.boardId, name: items.name })
      .from(items)
      .innerJoin(boards, eq(items.boardId, boards.id))
      .where(and(eq(items.id, itemId), eq(boards.accountId, auth.accountId), isNull(items.archivedAt)))
      .limit(1);
    if (!row) throw new NotFoundException('Item not found');
    if (auth.role === 'viewer' || auth.role === 'guest') {
      throw new ForbiddenException('Your role cannot post updates');
    }
    return row;
  }

  /**
   * Finds `@Full Name` mentions in the body and maps them to account members.
   * Longest names are matched first so "@Alex Smith" wins over "@Alex".
   */
  private async resolveMentions(auth: AuthContext, body: string): Promise<string[]> {
    if (!body.includes('@')) return [];

    const members = await this.db
      .select({ userId: accountMembers.userId, fullName: userProfiles.fullName })
      .from(accountMembers)
      .innerJoin(userProfiles, eq(accountMembers.userId, userProfiles.userId))
      .where(eq(accountMembers.accountId, auth.accountId));

    const lowerBody = body.toLowerCase();
    const matched = members
      .filter((m) => m.fullName && lowerBody.includes(`@${m.fullName.toLowerCase()}`))
      .sort((a, b) => b.fullName.length - a.fullName.length)
      .map((m) => m.userId)
      // Never notify yourself.
      .filter((userId) => userId !== auth.userId);

    return [...new Set(matched)];
  }

  /**
   * My Work: items assigned to the caller through any `people` column,
   * grouped by due date relative to today.
   */
  async myWork(
    auth: AuthContext,
    includeDone = false,
  ): Promise<{
    overdue: MyWorkItem[];
    today: MyWorkItem[];
    thisWeek: MyWorkItem[];
    later: MyWorkItem[];
    noDate: MyWorkItem[];
    done: MyWorkItem[];
    doneCount: number;
  }> {
    const peopleColumns = await this.db
      .select({ id: columns.id, boardId: columns.boardId })
      .from(columns)
      .innerJoin(boards, eq(columns.boardId, boards.id))
      .where(and(eq(boards.accountId, auth.accountId), eq(columns.type, 'people'), isNull(boards.archivedAt)));
    if (peopleColumns.length === 0) return this.emptyMyWork();

    const assignments = await this.db
      .select({ itemId: columnValues.itemId, value: columnValues.value })
      .from(columnValues)
      .where(
        inArray(
          columnValues.columnId,
          peopleColumns.map((c) => c.id),
        ),
      );

    const myItemIds = assignments
      .filter((a) => {
        const ids = (a.value as { userIds?: unknown })?.userIds;
        return Array.isArray(ids) && ids.includes(auth.userId);
      })
      .map((a) => a.itemId);
    if (myItemIds.length === 0) return this.emptyMyWork();

    const rows = await this.db
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
      .where(and(inArray(items.id, [...new Set(myItemIds)]), isNull(items.archivedAt)))
      .orderBy(asc(items.position));

    const allValues = await this.db
      .select()
      .from(columnValues)
      .where(
        inArray(
          columnValues.itemId,
          rows.map((r) => r.id),
        ),
      );

    const boardColumns = await this.db
      .select({ id: columns.id, boardId: columns.boardId, type: columns.type, settings: columns.settings })
      .from(columns)
      .where(
        inArray(
          columns.boardId,
          [...new Set(rows.map((r) => r.boardId))],
        ),
      );

    const valuesByItem = new Map<string, Map<string, unknown>>();
    for (const v of allValues) {
      const bag = valuesByItem.get(v.itemId) ?? new Map<string, unknown>();
      bag.set(v.columnId, v.value);
      valuesByItem.set(v.itemId, bag);
    }

    const buckets = this.emptyMyWork();
    const today = startOfDay(new Date());
    const weekEnd = new Date(today);
    weekEnd.setDate(weekEnd.getDate() + 7);

    for (const row of rows) {
      const values = valuesByItem.get(row.id) ?? new Map<string, unknown>();
      const cols = boardColumns.filter((c) => c.boardId === row.boardId);

      const dateColumn = cols.find((c) => c.type === 'date');
      const rawDate = dateColumn
        ? (values.get(dateColumn.id) as { date?: string } | undefined)?.date
        : undefined;

      const statusColumn = cols.find((c) => c.type === 'status');
      const statusValue = statusColumn
        ? (values.get(statusColumn.id) as { labelId?: string } | undefined)
        : undefined;
      const labels = (statusColumn?.settings as { labels?: Array<{ id: string; label: string; color: string; isDone: boolean }> })
        ?.labels ?? [];
      const label = labels.find((l) => l.id === statusValue?.labelId);

      const entry: MyWorkItem = {
        id: row.id,
        name: row.name,
        boardId: row.boardId,
        boardName: row.boardName,
        groupTitle: row.groupTitle,
        groupColor: row.groupColor,
        date: rawDate ?? null,
        status: label ? { label: label.label, color: label.color, isDone: label.isDone } : null,
      };

      // Completed work is counted and, when asked for, listed separately
      // rather than mixed into the date buckets.
      if (label?.isDone) {
        buckets.doneCount += 1;
        if (includeDone) buckets.done.push(entry);
        continue;
      }

      if (!rawDate) {
        buckets.noDate.push(entry);
        continue;
      }
      const due = startOfDay(new Date(`${rawDate}T00:00:00Z`));
      if (due < today) buckets.overdue.push(entry);
      else if (due.getTime() === today.getTime()) buckets.today.push(entry);
      else if (due < weekEnd) buckets.thisWeek.push(entry);
      else buckets.later.push(entry);
    }

    return buckets;
  }

  private emptyMyWork() {
    return {
      overdue: [] as MyWorkItem[],
      today: [] as MyWorkItem[],
      thisWeek: [] as MyWorkItem[],
      later: [] as MyWorkItem[],
      noDate: [] as MyWorkItem[],
      done: [] as MyWorkItem[],
      doneCount: 0,
    };
  }
}

export interface MyWorkItem {
  id: string;
  name: string;
  boardId: string;
  boardName: string;
  groupTitle: string;
  groupColor: string;
  date: string | null;
  status: { label: string; color: string; isDone: boolean } | null;
}

/** Midnight UTC, so date-only comparisons ignore the server's timezone. */
function startOfDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}
