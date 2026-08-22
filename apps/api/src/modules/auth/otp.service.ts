import { BadRequestException, HttpException, HttpStatus, Inject, Injectable } from '@nestjs/common';
import { and, desc, eq, gt, isNull } from 'drizzle-orm';
import * as argon2 from 'argon2';
import { randomInt } from 'node:crypto';
import { Database, DRIZZLE } from '../../db/db.module';
import { otpCodes } from '../../db/schema';

const OTP_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;

@Injectable()
export class OtpService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  /** Creates a fresh 6-digit code for the email, invalidating previous unconsumed ones. */
  async issue(email: string, purpose: 'signup' | 'login'): Promise<string> {
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
      throw new BadRequestException('Incorrect code. Please try again.');
    }

    await this.db.update(otpCodes).set({ consumedAt: new Date() }).where(eq(otpCodes.id, row.id));
  }
}
