import { BadRequestException, HttpException, HttpStatus, Inject, Injectable } from '@nestjs/common';
import { and, desc, eq, gt, isNull, sql } from 'drizzle-orm';
import * as argon2 from 'argon2';
import { randomInt } from 'node:crypto';
import { Database, DRIZZLE } from '../../db/db.module';
import { otpCodes, otpThrottle } from '../../db/schema';

const OTP_TTL_MS = 10 * 60 * 1000;
/** Wrong guesses allowed against a single issued code. */
const MAX_ATTEMPTS = 5;
/** Wrong guesses allowed per email across re-issued codes before a lockout. */
const LOCKOUT_THRESHOLD = 8;
const LOCKOUT_MS = 15 * 60 * 1000;

@Injectable()
export class OtpService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  /** Creates a fresh 6-digit code for the email, invalidating previous unconsumed ones. */
  async issue(email: string, purpose: 'signup' | 'login'): Promise<string> {
    await this.assertNotLocked(email);
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    const codeHash = await argon2.hash(code);
    await this.db.transaction(async (tx) => {
      await tx
        .update(otpCodes)
        .set({ consumedAt: new Date() })
        .where(and(eq(otpCodes.email, email), isNull(otpCodes.consumedAt)));
      await tx.insert(otpCodes).values({
        email,
        codeHash,
        purpose,
        expiresAt: new Date(Date.now() + OTP_TTL_MS),
      });
    });
    return code;
  }

  /** Verifies and consumes the newest active code. Throws on mismatch, expiry, or too many attempts. */
  async verifyAndConsume(email: string, code: string): Promise<void> {
    await this.assertNotLocked(email);
    const [row] = await this.db
      .select()
      .from(otpCodes)
      .where(and(eq(otpCodes.email, email), isNull(otpCodes.consumedAt), gt(otpCodes.expiresAt, new Date())))
      .orderBy(desc(otpCodes.createdAt))
      .limit(1);

    if (!row) {
      throw new BadRequestException('Code is invalid or has expired. Request a new one.');
    }
    if (row.attempts >= MAX_ATTEMPTS) {
      throw new HttpException('Too many attempts. Request a new code.', HttpStatus.TOO_MANY_REQUESTS);
    }

    const matches = await argon2.verify(row.codeHash, code);
    if (!matches) {
      await this.db
        .update(otpCodes)
        .set({ attempts: row.attempts + 1 })
        .where(eq(otpCodes.id, row.id));
      await this.recordFailure(email);
      throw new BadRequestException('Incorrect code. Please try again.');
    }

    await this.db.update(otpCodes).set({ consumedAt: new Date() }).where(eq(otpCodes.id, row.id));
    // A successful login clears the failure ledger.
    await this.db.delete(otpThrottle).where(eq(otpThrottle.email, email));
  }

  /**
   * The per-code attempt counter alone is resettable by requesting a fresh
   * code, so failures are also tallied per email; crossing the threshold
   * locks the address for a cool-down window.
   */
  private async recordFailure(email: string): Promise<void> {
    const [ledger] = await this.db
      .insert(otpThrottle)
      .values({ email, failedAttempts: 1, updatedAt: new Date() })
      .onConflictDoUpdate({
        target: otpThrottle.email,
        set: { failedAttempts: sql`${otpThrottle.failedAttempts} + 1`, updatedAt: new Date() },
      })
      .returning({ failedAttempts: otpThrottle.failedAttempts });

    if ((ledger?.failedAttempts ?? 0) >= LOCKOUT_THRESHOLD) {
      await this.db
        .update(otpThrottle)
        .set({ lockedUntil: new Date(Date.now() + LOCKOUT_MS), failedAttempts: 0, updatedAt: new Date() })
        .where(eq(otpThrottle.email, email));
    }
  }

  private async assertNotLocked(email: string): Promise<void> {
    const [ledger] = await this.db
      .select({ lockedUntil: otpThrottle.lockedUntil })
      .from(otpThrottle)
      .where(eq(otpThrottle.email, email))
      .limit(1);
    if (ledger?.lockedUntil && ledger.lockedUntil > new Date()) {
      throw new HttpException(
        'Too many failed attempts. Try again in a few minutes.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }
}
