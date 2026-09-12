import { ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, eq, exists, or, sql, type SQL } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { boardMembers, boards } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

/**
 * Board-level access control, following the monday.com model:
 *
 * - `main` boards are visible to every account member — except guests, who
 *   only ever see boards they were explicitly added to.
 * - `private` and `shareable` boards are visible only to their board members
 *   (shareable is the variant guests may be added to).
 * - Account admins see every board (the escape hatch that keeps boards
 *   reachable when their owners leave).
 * - Board membership carries a role: `owner` manages the board, `member`
 *   collaborates, `viewer` is read-only on that board.
 *
 * Account tenancy (`boards.accountId = auth.accountId`) is enforced by every
 * query already; this layer adds the rules above. Restricted boards answer
 * 404 (not 403) so their existence is not leaked.
 */
@Injectable()
export class BoardAccessService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  /**
   * WHERE fragment for queries that join `boards`, restricting rows to boards
   * the caller can see. Returns undefined for admins — drizzle's `and()`
   * skips undefined conditions.
   */
  visibleTo(auth: AuthContext): SQL | undefined {
    if (auth.role === 'admin') return undefined;
    const membership = exists(
      this.db
        .select({ one: sql`1` })
        .from(boardMembers)
        .where(and(eq(boardMembers.boardId, boards.id), eq(boardMembers.userId, auth.userId))),
    );
    // Guests never get account-wide visibility — explicit boards only.
    if (auth.role === 'guest') return membership;
    return or(eq(boards.type, 'main'), membership);
  }

  /** Throws NotFound when the board is outside the account or hidden from the caller. */
  async assertVisible(auth: AuthContext, boardId: string): Promise<void> {
    const [row] = await this.db
      .select({ id: boards.id })
      .from(boards)
      .where(and(eq(boards.id, boardId), eq(boards.accountId, auth.accountId), this.visibleTo(auth)))
      .limit(1);
    if (!row) throw new NotFoundException('Board not found');
  }

  /**
   * Someone added to a board as a `viewer` is read-only there, whatever their
   * account role allows elsewhere. Call after the usual visibility checks on
   * every mutation path. Account admins bypass, like board owners do on
   * monday.
   */
  async assertBoardEditable(auth: AuthContext, boardId: string): Promise<void> {
    if (auth.role === 'admin') return;
    const [membership] = await this.db
      .select({ role: boardMembers.role })
      .from(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, auth.userId)))
      .limit(1);
    if (membership?.role === 'viewer') {
      throw new ForbiddenException('You have view-only access to this board');
    }
  }

  /**
   * Managing a board — its members, its type — takes a board owner or an
   * account admin. Assumes visibility was already established.
   */
  async assertCanManage(auth: AuthContext, boardId: string): Promise<void> {
    if (auth.role === 'admin') return;
    const [membership] = await this.db
      .select({ role: boardMembers.role })
      .from(boardMembers)
      .where(and(eq(boardMembers.boardId, boardId), eq(boardMembers.userId, auth.userId)))
      .limit(1);
    if (membership?.role !== 'owner') {
      throw new ForbiddenException('Only board owners can do this');
    }
  }
}
