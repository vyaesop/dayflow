import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, asc, count, desc, eq, inArray, isNull, ne, or, type SQL } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardIsLive, itemIsLive } from '../../db/live';
import {
  accountMembers,
  boardMembers,
  boards,
  columns,
  columnValues,
  groups,
  items,
  updateBookmarks,
  updateReactions,
  updates,
  userProfiles,
  workspaces,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardAccessService } from '../access/board-access.service';
import { BoardContextService } from '../access/board-context.service';
import { ActivityService, type ActivityEntry } from '../activity/activity.service';
import { presentColumn, presentItem, type ColumnPayload, type ItemPayload } from '../boards/presenters';
import { FilesService, type FilePayload } from '../files/files.service';
import { NotifierService } from '../notifications/notifier.service';
import { docToPlainText, mentionsIn, normalizeStoredDoc, parseMarkdownLite, serializeDoc, type Doc } from './rich-text';

/** Emoji the API accepts as reactions, in picker order. */
export const REACTION_EMOJIS = ['👍', '❤️', '🎉', '😂', '😮', '😢', '🙏', '👀', '🔥', '✅'] as const;
const LIKE_EMOJI = '👍';

export interface ItemDetailPayload {
  id: string;
  name: string;
  board: { id: string; name: string };
  group: { id: string; title: string; color: string };
  workspaceName: string;
  createdAt: string;
  updatedAt: string;
  createdByUserId: string | null;
  updatedByUserId: string | null;
  serial: number;
  parent: { id: string; name: string } | null;
  values: Record<string, unknown>;
  /** Columns of this item's level (item columns, or the subitem set for a subitem). */
  columns: ColumnPayload[];
  subitemColumns: ColumnPayload[];
  subitems: ItemPayload[];
  updates: UpdatePayload[];
  activity: ActivityEntry[];
  canEdit: boolean;
}

export interface ReactionPayload {
  emoji: string;
  count: number;
  reactedByMe: boolean;
}

export interface UpdatePayload {
  id: string;
  /** Plain text (legacy clients). */
  body: string;
  /** Canonical markdown-lite for editing. */
  markdown: string;
  doc: Doc;
  author: { userId: string; fullName: string; avatarUrl: string | null };
  createdAt: string;
  editedAt: string | null;
  reactions: ReactionPayload[];
  likesCount: number;
  likedByMe: boolean;
  bookmarkedByMe: boolean;
  files: FilePayload[];
  replies: UpdatePayload[];
}

export interface FeedEntry extends UpdatePayload {
  boardId: string;
  boardName: string;
  itemId: string | null;
  itemName: string | null;
}

interface UpdateRow {
  id: string;
  body: unknown;
  bodyText: string;
  createdAt: Date;
  editedAt: Date | null;
  parentId: string | null;
  authorUserId: string;
  authorName: string;
  authorAvatar: string | null;
}

@Injectable()
export class ItemsService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly notifier: NotifierService,
    private readonly boardAccess: BoardAccessService,
    private readonly ctx: BoardContextService,
    private readonly activity: ActivityService,
    private readonly files: FilesService,
  ) {}

  async getItem(auth: AuthContext, itemId: string): Promise<ItemDetailPayload> {
    const [row] = await this.db
      .select({
        item: items,
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
      .where(
        and(
          eq(items.id, itemId),
          eq(boards.accountId, auth.accountId),
          itemIsLive(),
          boardIsLive(),
          this.boardAccess.visibleTo(auth),
        ),
      )
      .limit(1);
    if (!row) throw new NotFoundException('Item not found');
    const item = row.item;

    const [cols, valueRows, updateRows, activityRows, subRows, parentRow, canEdit] = await Promise.all([
      this.db.select().from(columns).where(eq(columns.boardId, row.boardId)).orderBy(asc(columns.position)),
      this.db.select().from(columnValues).where(eq(columnValues.itemId, itemId)),
      this.hydratedUpdates(auth, eq(updates.itemId, itemId)),
      this.activity.forItem(itemId),
      item.parentItemId
        ? Promise.resolve([])
        : this.db
            .select()
            .from(items)
            .where(and(eq(items.parentItemId, itemId), itemIsLive()))
            .orderBy(asc(items.position)),
      item.parentItemId
        ? this.db.select({ id: items.id, name: items.name }).from(items).where(eq(items.id, item.parentItemId)).limit(1)
        : Promise.resolve([]),
      this.ctx.canEdit(auth, row.boardId),
    ]);

    const values: Record<string, unknown> = {};
    for (const v of valueRows) values[v.columnId] = v.value;

    const subIds = subRows.map((s) => s.id);
    const [subValues, subUpdateCounts] = await Promise.all([
      subIds.length ? this.db.select().from(columnValues).where(inArray(columnValues.itemId, subIds)) : Promise.resolve([]),
      subIds.length
        ? this.db
            .select({ itemId: updates.itemId, n: count() })
            .from(updates)
            .where(inArray(updates.itemId, subIds))
            .groupBy(updates.itemId)
        : Promise.resolve([] as Array<{ itemId: string | null; n: number }>),
    ]);
    const subitems = subRows.map((s) => {
      const bag: Record<string, unknown> = {};
      for (const v of subValues) if (v.itemId === s.id) bag[v.columnId] = v.value;
      return presentItem(s, bag, Number(subUpdateCounts.find((u) => u.itemId === s.id)?.n ?? 0));
    });

    const ownScope = item.parentItemId ? 'subitems' : 'items';
    return {
      id: item.id,
      name: item.name,
      board: { id: row.boardId, name: row.boardName },
      group: { id: row.groupId, title: row.groupTitle, color: row.groupColor },
      workspaceName: row.workspaceName,
      createdAt: item.createdAt.toISOString(),
      updatedAt: item.updatedAt.toISOString(),
      createdByUserId: item.createdByUserId,
      updatedByUserId: item.updatedByUserId,
      serial: item.serial,
      parent: parentRow[0] ? { id: parentRow[0].id, name: parentRow[0].name } : null,
      values,
      columns: cols.filter((c) => c.scope === ownScope).map(presentColumn),
      subitemColumns: cols.filter((c) => c.scope === 'subitems').map(presentColumn),
      subitems,
      updates: updateRows,
      activity: activityRows,
      canEdit,
    };
  }

  // ------------------------------------------------------------------- updates

  /** Posts an update (or reply) on an item. */
  async addUpdate(auth: AuthContext, itemId: string, body: string, parentId?: string): Promise<UpdatePayload> {
    const item = await this.ctx.writableItem(auth, itemId);
    return this.postUpdate(auth, { boardId: item.boardId, itemId: item.id, itemName: item.name }, body, parentId);
  }

  /** Board discussion: updates that belong to the board rather than one item. */
  async addBoardUpdate(auth: AuthContext, boardId: string, body: string, parentId?: string): Promise<UpdatePayload> {
    const board = await this.ctx.writableBoard(auth, boardId);
    return this.postUpdate(auth, { boardId: board.id, itemId: null, itemName: null }, body, parentId);
  }

  async boardUpdates(auth: AuthContext, boardId: string): Promise<UpdatePayload[]> {
    await this.ctx.visibleBoard(auth, boardId);
    return this.hydratedUpdates(auth, and(eq(updates.boardId, boardId), isNull(updates.itemId))!);
  }

  private async postUpdate(
    auth: AuthContext,
    target: { boardId: string; itemId: string | null; itemName: string | null },
    body: string,
    parentId?: string,
  ): Promise<UpdatePayload> {
    const doc = parseMarkdownLite(body);
    const bodyText = docToPlainText(doc);
    if (!bodyText.trim()) throw new BadRequestException('An update needs some text');
    const { userIds: tokenMentions, everyone } = mentionsIn(doc);
    const legacyMentions = tokenMentions.length || everyone ? [] : await this.resolveLegacyMentions(auth, bodyText);

    // A reply must target a top-level update on the same item/board.
    let parentAuthorId: string | null = null;
    if (parentId) {
      const [parent] = await this.db
        .select({ id: updates.id, itemId: updates.itemId, boardId: updates.boardId, parentId: updates.parentId, authorUserId: updates.authorUserId })
        .from(updates)
        .where(eq(updates.id, parentId))
        .limit(1);
      if (!parent || parent.itemId !== target.itemId || parent.boardId !== target.boardId) {
        throw new NotFoundException('Update to reply to not found');
      }
      if (parent.parentId) throw new BadRequestException('Replies cannot be nested further');
      parentAuthorId = parent.authorUserId;
    }

    const mentioned = await this.activeMembers(auth, [...new Set([...tokenMentions, ...legacyMentions])]);
    const audience = everyone ? await this.boardAudience(auth, target.boardId) : [];
    const notifyMention = [...new Set([...mentioned, ...audience])].filter((id) => id !== auth.userId);

    const [profile] = await this.db
      .select({ fullName: userProfiles.fullName, avatarUrl: userProfiles.avatarUrl })
      .from(userProfiles)
      .where(eq(userProfiles.userId, auth.userId))
      .limit(1);

    const [created] = await this.db
      .insert(updates)
      .values({
        boardId: target.boardId,
        itemId: target.itemId,
        authorUserId: auth.userId,
        parentId: parentId ?? null,
        body: doc,
        bodyText,
        mentionedUserIds: notifyMention,
      })
      .returning();

    const [board] = await this.db.select({ name: boards.name }).from(boards).where(eq(boards.id, target.boardId)).limit(1);
    const snippet = bodyText.slice(0, 140);
    const basePayload = {
      boardId: target.boardId,
      boardName: board?.name ?? '',
      itemId: target.itemId ?? undefined,
      itemName: target.itemName ?? board?.name ?? '',
      updateId: created.id,
      snippet,
    };

    // Replying notifies the parent author (never yourself, never twice).
    if (parentAuthorId && parentAuthorId !== auth.userId && !notifyMention.includes(parentAuthorId)) {
      await this.notifier.dispatch([
        { accountId: auth.accountId, userId: parentAuthorId, type: 'reply', actorUserId: auth.userId, payload: basePayload },
      ]);
    }
    if (notifyMention.length) {
      await this.notifier.dispatch(
        notifyMention.map((userId) => ({
          accountId: auth.accountId,
          userId,
          type: 'mention' as const,
          actorUserId: auth.userId,
          payload: { ...basePayload, everyone: everyone && !mentioned.includes(userId) },
        })),
      );
    }

    return {
      id: created.id,
      body: bodyText,
      markdown: serializeDoc(doc),
      doc,
      author: { userId: auth.userId, fullName: profile?.fullName ?? '', avatarUrl: profile?.avatarUrl ?? null },
      createdAt: created.createdAt.toISOString(),
      editedAt: null,
      reactions: [],
      likesCount: 0,
      likedByMe: false,
      bookmarkedByMe: false,
      files: [],
      replies: [],
    };
  }

  async editUpdate(auth: AuthContext, updateId: string, body: string): Promise<UpdatePayload> {
    const row = await this.updateInAccount(auth, updateId);
    if (row.authorUserId !== auth.userId) {
      throw new ForbiddenException('You can only edit your own updates');
    }
    const doc = parseMarkdownLite(body);
    const bodyText = docToPlainText(doc);
    if (!bodyText.trim()) throw new BadRequestException('An update needs some text');
    const { userIds } = mentionsIn(doc);
    const mentioned = await this.activeMembers(auth, userIds);

    await this.db
      .update(updates)
      .set({ body: doc, bodyText, mentionedUserIds: mentioned, editedAt: new Date() })
      .where(eq(updates.id, updateId));
    const [hydrated] = await this.hydratedUpdates(auth, eq(updates.id, updateId), { includeReplies: false });
    return hydrated;
  }

  /** Toggles one emoji reaction and returns the update's reaction summary. */
  async toggleReaction(auth: AuthContext, updateId: string, emoji: string): Promise<{ reactions: ReactionPayload[] }> {
    if (!REACTION_EMOJIS.includes(emoji as (typeof REACTION_EMOJIS)[number])) {
      throw new BadRequestException(`emoji must be one of ${REACTION_EMOJIS.join(' ')}`);
    }
    await this.updateInAccount(auth, updateId);
    const [existing] = await this.db
      .select({ id: updateReactions.id })
      .from(updateReactions)
      .where(and(eq(updateReactions.updateId, updateId), eq(updateReactions.userId, auth.userId), eq(updateReactions.emoji, emoji)))
      .limit(1);
    if (existing) {
      await this.db.delete(updateReactions).where(eq(updateReactions.id, existing.id));
    } else {
      await this.db.insert(updateReactions).values({ updateId, userId: auth.userId, emoji });
    }
    const summary = await this.reactionSummary(auth, [updateId]);
    return { reactions: summary.get(updateId) ?? [] };
  }

  /** Legacy alias: a like is a 👍 reaction. */
  async toggleLike(auth: AuthContext, updateId: string): Promise<{ liked: boolean; likesCount: number }> {
    const { reactions } = await this.toggleReaction(auth, updateId, LIKE_EMOJI);
    const thumbs = reactions.find((r) => r.emoji === LIKE_EMOJI);
    return { liked: thumbs?.reactedByMe ?? false, likesCount: thumbs?.count ?? 0 };
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
  async updateFeed(auth: AuthContext, filter: { boardId?: string; bookmarked?: boolean }): Promise<FeedEntry[]> {
    const conditions: SQL[] = [eq(boards.accountId, auth.accountId), isNull(updates.parentId), boardIsLive()];
    const visibility = this.boardAccess.visibleTo(auth);
    if (visibility) conditions.push(visibility);
    if (filter.boardId) conditions.push(eq(updates.boardId, filter.boardId));
    // Updates on archived/trashed items stay out of the feed.
    conditions.push(or(isNull(updates.itemId), itemIsLive())!);

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

    const hydrated = await this.decorate(
      auth,
      rows.map((r) => ({
        id: r.update.id,
        body: r.update.body,
        bodyText: r.update.bodyText,
        createdAt: r.update.createdAt,
        editedAt: r.update.editedAt,
        parentId: r.update.parentId,
        authorUserId: r.update.authorUserId,
        authorName: r.authorName,
        authorAvatar: r.authorAvatar,
      })),
    );

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
    const row = await this.updateInAccount(auth, updateId);
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

  private async updateInAccount(auth: AuthContext, updateId: string) {
    const [row] = await this.db
      .select({ id: updates.id, authorUserId: updates.authorUserId, boardId: updates.boardId })
      .from(updates)
      .innerJoin(boards, eq(updates.boardId, boards.id))
      .where(and(eq(updates.id, updateId), eq(boards.accountId, auth.accountId), this.boardAccess.visibleTo(auth)))
      .limit(1);
    if (!row) throw new NotFoundException('Update not found');
    return row;
  }

  private async hydratedUpdates(auth: AuthContext, where: SQL, options?: { includeReplies?: boolean }): Promise<UpdatePayload[]> {
    const rows = await this.db
      .select({
        id: updates.id,
        body: updates.body,
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
    if (options?.includeReplies === false) return decorated;
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

  /** Attaches reactions, bookmark state and files to raw update rows. */
  private async decorate(auth: AuthContext, rows: UpdateRow[]): Promise<UpdatePayload[]> {
    if (rows.length === 0) return [];
    const ids = rows.map((r) => r.id);
    const [reactions, myBookmarks, filesByUpdate] = await Promise.all([
      this.reactionSummary(auth, ids),
      this.db
        .select({ updateId: updateBookmarks.updateId })
        .from(updateBookmarks)
        .where(and(inArray(updateBookmarks.updateId, ids), eq(updateBookmarks.userId, auth.userId))),
      this.files.listForUpdates(ids),
    ]);
    const bookmarked = new Set(myBookmarks.map((b) => b.updateId));

    return rows.map((r) => {
      const doc = normalizeStoredDoc(r.body ?? r.bodyText);
      const list = reactions.get(r.id) ?? [];
      const thumbs = list.find((x) => x.emoji === LIKE_EMOJI);
      return {
        id: r.id,
        body: r.bodyText,
        markdown: serializeDoc(doc),
        doc,
        author: { userId: r.authorUserId, fullName: r.authorName, avatarUrl: r.authorAvatar },
        createdAt: r.createdAt.toISOString(),
        editedAt: r.editedAt?.toISOString() ?? null,
        reactions: list,
        likesCount: thumbs?.count ?? 0,
        likedByMe: thumbs?.reactedByMe ?? false,
        bookmarkedByMe: bookmarked.has(r.id),
        files: filesByUpdate.get(r.id) ?? [],
        replies: [],
      };
    });
  }

  private async reactionSummary(auth: AuthContext, updateIds: string[]): Promise<Map<string, ReactionPayload[]>> {
    const rows = await this.db
      .select({ updateId: updateReactions.updateId, emoji: updateReactions.emoji, userId: updateReactions.userId })
      .from(updateReactions)
      .where(inArray(updateReactions.updateId, updateIds))
      .orderBy(asc(updateReactions.createdAt));
    const out = new Map<string, ReactionPayload[]>();
    for (const row of rows) {
      const list = out.get(row.updateId) ?? [];
      let entry = list.find((r) => r.emoji === row.emoji);
      if (!entry) {
        entry = { emoji: row.emoji, count: 0, reactedByMe: false };
        list.push(entry);
      }
      entry.count += 1;
      if (row.userId === auth.userId) entry.reactedByMe = true;
      out.set(row.updateId, list);
    }
    // Picker order keeps the pills stable between renders.
    for (const list of out.values()) {
      list.sort((a, b) => REACTION_EMOJIS.indexOf(a.emoji as never) - REACTION_EMOJIS.indexOf(b.emoji as never));
    }
    return out;
  }

  /** Keeps only ids that are active members of this account. */
  private async activeMembers(auth: AuthContext, userIds: string[]): Promise<string[]> {
    if (userIds.length === 0) return [];
    const rows = await this.db
      .select({ userId: accountMembers.userId })
      .from(accountMembers)
      .where(
        and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.status, 'active'), inArray(accountMembers.userId, userIds)),
      );
    return rows.map((r) => r.userId);
  }

  /** "Everyone on this board": board members, plus every active non-guest member for main boards. */
  private async boardAudience(auth: AuthContext, boardId: string): Promise<string[]> {
    const [board] = await this.db.select({ type: boards.type }).from(boards).where(eq(boards.id, boardId)).limit(1);
    const explicit = await this.db
      .select({ userId: boardMembers.userId })
      .from(boardMembers)
      .innerJoin(
        accountMembers,
        and(eq(accountMembers.userId, boardMembers.userId), eq(accountMembers.accountId, auth.accountId)),
      )
      .where(and(eq(boardMembers.boardId, boardId), eq(accountMembers.status, 'active')));
    const ids = new Set(explicit.map((r) => r.userId));
    if (board?.type === 'main') {
      const everyone = await this.db
        .select({ userId: accountMembers.userId })
        .from(accountMembers)
        .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.status, 'active'), ne(accountMembers.role, 'guest')));
      for (const r of everyone) ids.add(r.userId);
    }
    return [...ids];
  }

  /**
   * Legacy plain-text mentions (`@Full Name`) for clients that don't emit
   * mention tokens. Longest names are matched first so "@Alex Smith" wins
   * over "@Alex".
   */
  private async resolveLegacyMentions(auth: AuthContext, body: string): Promise<string[]> {
    if (!body.includes('@')) return [];
    const members = await this.db
      .select({ userId: accountMembers.userId, fullName: userProfiles.fullName })
      .from(accountMembers)
      .innerJoin(userProfiles, eq(accountMembers.userId, userProfiles.userId))
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.status, 'active')));
    const lowerBody = body.toLowerCase();
    return [
      ...new Set(
        members
          .filter((m) => m.fullName && lowerBody.includes(`@${m.fullName.toLowerCase()}`))
          .sort((a, b) => b.fullName.length - a.fullName.length)
          .map((m) => m.userId)
          .filter((userId) => userId !== auth.userId),
      ),
    ];
  }

  // ------------------------------------------------------------------- My Work

  /**
   * My Work: items (and subitems) assigned to the caller through any `people`
   * column, grouped by due date relative to today.
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
      .where(and(eq(boards.accountId, auth.accountId), eq(columns.type, 'people'), boardIsLive(), this.boardAccess.visibleTo(auth)));
    if (peopleColumns.length === 0) return this.emptyMyWork();

    const assignments = await this.db
      .select({ itemId: columnValues.itemId, value: columnValues.value })
      .from(columnValues)
      .where(inArray(columnValues.columnId, peopleColumns.map((c) => c.id)));

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
        parentItemId: items.parentItemId,
        boardId: boards.id,
        boardName: boards.name,
        groupTitle: groups.title,
        groupColor: groups.color,
      })
      .from(items)
      .innerJoin(boards, eq(items.boardId, boards.id))
      .innerJoin(groups, eq(items.groupId, groups.id))
      .where(and(inArray(items.id, [...new Set(myItemIds)]), itemIsLive()))
      .orderBy(asc(items.position));
    if (rows.length === 0) return this.emptyMyWork();

    const [allValues, boardColumns] = await Promise.all([
      this.db.select().from(columnValues).where(inArray(columnValues.itemId, rows.map((r) => r.id))),
      this.db
        .select({ id: columns.id, boardId: columns.boardId, type: columns.type, scope: columns.scope, settings: columns.settings })
        .from(columns)
        .where(inArray(columns.boardId, [...new Set(rows.map((r) => r.boardId))])),
    ]);

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
      const scope = row.parentItemId ? 'subitems' : 'items';
      const cols = boardColumns.filter((c) => c.boardId === row.boardId && c.scope === scope);

      const dateColumn = cols.find((c) => c.type === 'date');
      const rawDate = dateColumn ? (values.get(dateColumn.id) as { date?: string } | undefined)?.date : undefined;

      const statusColumn = cols.find((c) => c.type === 'status');
      const statusValue = statusColumn ? (values.get(statusColumn.id) as { labelId?: string } | undefined) : undefined;
      const labels =
        (statusColumn?.settings as { labels?: Array<{ id: string; label: string; color: string; isDone: boolean }> })?.labels ?? [];
      const label = labels.find((l) => l.id === statusValue?.labelId);

      const entry: MyWorkItem = {
        id: row.id,
        name: row.name,
        boardId: row.boardId,
        boardName: row.boardName,
        groupTitle: row.groupTitle,
        groupColor: row.groupColor,
        isSubitem: !!row.parentItemId,
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
  isSubitem: boolean;
  date: string | null;
  status: { label: string; color: string; isDone: boolean } | null;
}

/** Midnight UTC, so date-only comparisons ignore the server's timezone. */
function startOfDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}
