import { ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { eq } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { accounts } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

export const DELETION_GRACE_DAYS = 30;

export interface DeletionStatus {
  /** ISO timestamp the account will be permanently deleted at, or null. */
  scheduledAt: string | null;
  graceDays: number;
}

/**
 * Whole-account (organization) deletion with a 30-day grace window. The
 * account stays fully usable until the deadline; a scheduled maintenance job
 * performs the actual purge. Admins can cancel any time before then.
 */
@Injectable()
export class AdminService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  async deletionStatus(auth: AuthContext): Promise<DeletionStatus> {
    this.assertAdmin(auth);
    const [account] = await this.db
      .select({ deletionScheduledAt: accounts.deletionScheduledAt })
      .from(accounts)
      .where(eq(accounts.id, auth.accountId))
      .limit(1);
    if (!account) throw new NotFoundException('Account not found');
    return {
      scheduledAt: account.deletionScheduledAt?.toISOString() ?? null,
      graceDays: DELETION_GRACE_DAYS,
    };
  }

  async scheduleDeletion(auth: AuthContext): Promise<DeletionStatus> {
    this.assertAdmin(auth);
    const scheduledAt = new Date(Date.now() + DELETION_GRACE_DAYS * 24 * 60 * 60 * 1000);
    const updated = await this.db
      .update(accounts)
      .set({ deletionScheduledAt: scheduledAt, updatedAt: new Date() })
      .where(eq(accounts.id, auth.accountId))
      .returning({ id: accounts.id });
    if (updated.length === 0) throw new NotFoundException('Account not found');
    return { scheduledAt: scheduledAt.toISOString(), graceDays: DELETION_GRACE_DAYS };
  }

  async cancelDeletion(auth: AuthContext): Promise<DeletionStatus> {
    this.assertAdmin(auth);
    const updated = await this.db
      .update(accounts)
      .set({ deletionScheduledAt: null, updatedAt: new Date() })
      .where(eq(accounts.id, auth.accountId))
      .returning({ id: accounts.id });
    if (updated.length === 0) throw new NotFoundException('Account not found');
    return { scheduledAt: null, graceDays: DELETION_GRACE_DAYS };
  }

  private assertAdmin(auth: AuthContext): void {
    if (auth.role !== 'admin') {
      throw new ForbiddenException('Only account admins can manage account deletion');
    }
  }
}
