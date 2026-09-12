import {
  BadRequestException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { and, asc, count, eq } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { accountMembers, boardMembers, boards, userProfiles, users } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import { BoardAccessService } from '../access/board-access.service';
import { NotifierService } from '../notifications/notifier.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';

export type BoardMemberRole = 'owner' | 'member' | 'viewer';

export interface BoardMemberList {
  members: BoardMemberPayload[];
  canManage: boolean;
}

export interface BoardMemberPayload {
  userId: string;
  fullName: string;
  email: string;
  avatarUrl: string | null;
  /** Role on this board (owner / member / viewer). */
  role: string;
  /** Role in the account, so clients can apply the ownership rules. */
  accountRole: string;
  isYou: boolean;
}

/**
 * Board membership management, monday-style: the creator is the first owner,
 * owners (and account admins) invite teammates with a role each, ownership is
 * limited to account admins/members, and guests may only be added to
 * shareable boards. A board always keeps at least one owner.
 */
@Injectable()
export class BoardMembersService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly boardAccess: BoardAccessService,
    private readonly notifier: NotifierService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async list(auth: AuthContext, boardId: string): Promise<BoardMemberList> {
    await this.boardAccess.assertVisible(auth, boardId);
    const members = await this.membersOf(auth, boardId);
    const canManage =
      auth.role === 'admin' || members.some((m) => m.userId === auth.userId && m.role === 'owner');
    return { members, canManage };
  }

  async add(
    auth: AuthContext,
    boardId: string,
    userId: string,
    role: BoardMemberRole,
  ): Promise<BoardMemberList> {
    const board = await this.boardForManage(auth, boardId);

    const [target] = await this.db
      .select({ accountRole: accountMembers.role, status: accountMembers.status })
      .from(accountMembers)
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.userId, userId)))
      .limit(1);
    if (!target || target.status !== 'active') {
      throw new NotFoundException('That person is not an active member of this account');
    }
    this.assertRoleAllowed(role, target.accountRole, board.type);

    const inserted = await this.db
      .insert(boardMembers)
      .values({ boardId, userId, role })
      .onConflictDoUpdate({ target: [boardMembers.boardId, boardMembers.userId], set: { role } })
      .returning({ createdAt: boardMembers.createdAt });

    // Only a genuinely new addition notifies — role tweaks don't re-ping.
    const isNew = inserted[0] && Date.now() - inserted[0].createdAt.getTime() < 5_000;
    if (isNew && userId !== auth.userId) {
      await this.notifier.dispatch([
        {
          accountId: auth.accountId,
          userId,
          type: 'board_invite',
          actorUserId: auth.userId,
          payload: { boardId, boardName: board.name },
        },
      ]);
    }

    this.emitMembersChanged(auth, boardId);
    return this.list(auth, boardId);
  }

  async changeRole(
    auth: AuthContext,
    boardId: string,
    userId: string,
    role: BoardMemberRole,
  ): Promise<BoardMemberList> {
    const board = await this.boardForManage(auth, boardId);

    const [existing] = await this.db
      .select({ role: boardMembers.role, accountRole: accountMembers.role })
      .from(boardMembers)
      .innerJoin(
        accountMembers,
        and(eq(accountMembers.userId, boardMembers.userId), eq(accountMembers.accountId, auth.accountId)),
      )
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, userId)))
      .limit(1);
    if (!existing) throw new NotFoundException('That person is not on this board');

    this.assertRoleAllowed(role, existing.accountRole, board.type);
    if (existing.role === 'owner' && role !== 'owner') {
      await this.assertNotLastOwner(boardId);
    }

    await this.db
      .update(boardMembers)
      .set({ role })
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, userId)));

    this.emitMembersChanged(auth, boardId);
    return this.list(auth, boardId);
  }

  /** Owners/admins remove anyone; anyone may remove themselves (leave the board). */
  async remove(auth: AuthContext, boardId: string, userId: string): Promise<BoardMemberList> {
    if (userId === auth.userId) {
      await this.boardAccess.assertVisible(auth, boardId);
    } else {
      await this.boardForManage(auth, boardId);
    }

    const [existing] = await this.db
      .select({ role: boardMembers.role })
      .from(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, userId)))
      .limit(1);
    if (!existing) throw new NotFoundException('That person is not on this board');
    if (existing.role === 'owner') {
      await this.assertNotLastOwner(boardId);
    }

    await this.db
      .delete(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, userId)));

    this.emitMembersChanged(auth, boardId);
    // Leaving a restricted board can end your own visibility of it.
    if (userId === auth.userId) return { members: [], canManage: false };
    return this.list(auth, boardId);
  }

  // ------------------------------------------------------------------ helpers

  private async membersOf(auth: AuthContext, boardId: string): Promise<BoardMemberPayload[]> {
    const rows = await this.db
      .select({
        userId: boardMembers.userId,
        role: boardMembers.role,
        accountRole: accountMembers.role,
        fullName: userProfiles.fullName,
        avatarUrl: userProfiles.avatarUrl,
        email: users.email,
      })
      .from(boardMembers)
      .innerJoin(users, eq(boardMembers.userId, users.id))
      .innerJoin(
        accountMembers,
        and(eq(accountMembers.userId, boardMembers.userId), eq(accountMembers.accountId, auth.accountId)),
      )
      .leftJoin(userProfiles, eq(boardMembers.userId, userProfiles.userId))
      .where(eq(boardMembers.boardId, boardId))
      .orderBy(asc(boardMembers.createdAt));

    return rows.map((r) => ({
      userId: r.userId,
      fullName: r.fullName ?? r.email,
      email: r.email,
      avatarUrl: r.avatarUrl,
      role: r.role,
      accountRole: r.accountRole,
      isYou: r.userId === auth.userId,
    }));
  }

  private async boardForManage(auth: AuthContext, boardId: string) {
    const [board] = await this.db
      .select({ id: boards.id, name: boards.name, type: boards.type })
      .from(boards)
      .where(and(eq(boards.id, boardId), eq(boards.accountId, auth.accountId), this.boardAccess.visibleTo(auth)))
      .limit(1);
    if (!board) throw new NotFoundException('Board not found');
    await this.boardAccess.assertCanManage(auth, boardId);
    return board;
  }

  /** The role matrix from the research: guests only on shareable boards; viewers/guests never own. */
  private assertRoleAllowed(role: BoardMemberRole, accountRole: string, boardType: string): void {
    if (accountRole === 'guest' && boardType !== 'shareable') {
      throw new BadRequestException('Guests can only be added to shareable boards');
    }
    if (role === 'owner' && (accountRole === 'viewer' || accountRole === 'guest')) {
      throw new ForbiddenException('Viewers and guests cannot be board owners');
    }
  }

  private async assertNotLastOwner(boardId: string): Promise<void> {
    const [owners] = await this.db
      .select({ n: count() })
      .from(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.role, 'owner')));
    if (Number(owners?.n ?? 0) <= 1) {
      throw new BadRequestException('A board must keep at least one owner');
    }
  }

  private emitMembersChanged(auth: AuthContext, boardId: string): void {
    // Other viewers refetch on board.updated; someone who just lost access
    // gets a 404 from that refetch and falls back gracefully.
    this.realtime.publish(
      { type: 'board.updated', boardId, patch: { membersChanged: true } },
      { accountId: auth.accountId, exceptUserId: auth.userId },
    );
  }
}
