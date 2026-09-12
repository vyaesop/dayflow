import { Inject, Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { and, isNull, lt, or } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { accounts, boards, invitations, items, otpCodes, otpThrottle, refreshTokens } from '../../db/schema';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Housekeeping that needs a long-running process (no-op on serverless, where
 * the ScheduleModule is not registered): purges dead auth artifacts so tables
 * don't grow without bound, and executes account deletions whose 30-day
 * grace period has ended.
 */
@Injectable()
export class MaintenanceService {
  private readonly logger = new Logger(MaintenanceService.name);

  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  @Cron('10 4 * * *') // daily, 04:10 server time
  async purgeAuthArtifacts(): Promise<void> {
    const now = Date.now();
    const [tokens, otps, ledgers, invites] = await Promise.all([
      // Keep expired tokens 7 days and revoked ones 30 for incident forensics.
      this.db
        .delete(refreshTokens)
        .where(
          or(
            lt(refreshTokens.expiresAt, new Date(now - 7 * DAY_MS)),
            lt(refreshTokens.revokedAt, new Date(now - 30 * DAY_MS)),
          ),
        )
        .returning({ id: refreshTokens.id }),
      this.db
        .delete(otpCodes)
        .where(lt(otpCodes.expiresAt, new Date(now - DAY_MS)))
        .returning({ id: otpCodes.id }),
      this.db
        .delete(otpThrottle)
        .where(
          and(
            lt(otpThrottle.updatedAt, new Date(now - DAY_MS)),
            or(isNull(otpThrottle.lockedUntil), lt(otpThrottle.lockedUntil, new Date(now))),
          ),
        )
        .returning({ email: otpThrottle.email }),
      this.db
        .delete(invitations)
        .where(lt(invitations.expiresAt, new Date(now - 30 * DAY_MS)))
        .returning({ id: invitations.id }),
    ]);
    this.logger.log(
      `Purged ${tokens.length} refresh tokens, ${otps.length} OTP codes, ${ledgers.length} OTP ledgers, ${invites.length} invitations`,
    );
  }

  @Cron('20 4 * * *') // daily, 04:20 server time
  async purgeTrash(): Promise<void> {
    // Trash keeps rows 30 days; after that boards and items are gone for good.
    const cutoff = new Date(Date.now() - 30 * DAY_MS);
    const [gone, orphans] = await Promise.all([
      this.db.delete(boards).where(lt(boards.trashedAt, cutoff)).returning({ id: boards.id }),
      this.db.delete(items).where(lt(items.trashedAt, cutoff)).returning({ id: items.id }),
    ]);
    this.logger.log(`Purged ${gone.length} boards and ${orphans.length} items from the trash`);
  }

  @Cron('30 4 * * *') // daily, 04:30 server time
  async processDueAccountDeletions(): Promise<void> {
    // Everything account-scoped cascades from the accounts row.
    const deleted = await this.db
      .delete(accounts)
      .where(lt(accounts.deletionScheduledAt, new Date()))
      .returning({ id: accounts.id, name: accounts.name });
    for (const account of deleted) {
      this.logger.warn(`Deleted account ${account.id} ("${account.name}") after its grace period`);
    }
  }
}
