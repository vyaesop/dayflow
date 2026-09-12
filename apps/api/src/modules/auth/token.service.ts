import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { and, eq } from 'drizzle-orm';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { Database, DRIZZLE } from '../../db/db.module';
import { refreshTokens } from '../../db/schema';
import type { AccessTokenPayload, AuthContext } from '../../common/auth-context';
import type { Env } from '../../config/env';

export interface TokenPair {
  accessToken: string;
  accessExpiresInSec: number;
  refreshToken: string;
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

@Injectable()
export class TokenService {
  private readonly accessTtlSec: number;
  private readonly refreshTtlDays: number;

  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly jwt: JwtService,
    config: ConfigService<Env, true>,
  ) {
    this.accessTtlSec = config.get('ACCESS_TOKEN_TTL_SEC', { infer: true });
    this.refreshTtlDays = config.get('REFRESH_TOKEN_TTL_DAYS', { infer: true });
  }

  async issuePair(ctx: AuthContext, userAgent?: string): Promise<TokenPair> {
    const payload: AccessTokenPayload = { sub: ctx.userId, acc: ctx.accountId, role: ctx.role, typ: 'access' };
    const accessToken = await this.jwt.signAsync(payload, { expiresIn: this.accessTtlSec });
    const refreshToken = await this.createRefreshToken(ctx, randomUUID(), userAgent);
    return { accessToken, accessExpiresInSec: this.accessTtlSec, refreshToken };
  }

  /**
   * Rotates a refresh token. Reuse of an already-rotated token revokes the whole
   * family (stolen-token defense) and forces re-login.
   *
   * Rotation runs in a transaction with the token row locked, so two
   * concurrent refreshes with the same token cannot both succeed — the loser
   * observes the row as already rotated and is treated as reuse.
   */
  async rotate(
    rawToken: string,
    userAgent?: string,
  ): Promise<{ ctx: { userId: string; accountId: string | null }; refreshToken: string }> {
    const tokenHash = sha256(rawToken);

    const outcome = await this.db.transaction(async (tx) => {
      const [row] = await tx
        .select()
        .from(refreshTokens)
        .where(eq(refreshTokens.tokenHash, tokenHash))
        .limit(1)
        .for('update');

      if (!row || row.expiresAt < new Date()) return { kind: 'invalid' as const };
      if (row.revokedAt || row.replacedById) {
        return { kind: 'reused' as const, familyId: row.familyId, userId: row.userId };
      }

      const newRaw = randomBytes(48).toString('base64url');
      const [replacement] = await tx
        .insert(refreshTokens)
        .values({
          userId: row.userId,
          accountId: row.accountId,
          tokenHash: sha256(newRaw),
          familyId: row.familyId,
          userAgent,
          expiresAt: new Date(Date.now() + this.refreshTtlDays * 24 * 60 * 60 * 1000),
        })
        .returning({ id: refreshTokens.id });
      await tx
        .update(refreshTokens)
        .set({ replacedById: replacement.id, revokedAt: new Date() })
        .where(eq(refreshTokens.id, row.id));

      return { kind: 'ok' as const, userId: row.userId, accountId: row.accountId, refreshToken: newRaw };
    });

    if (outcome.kind === 'reused') {
      // Must persist even though the caller gets an error, so it happens
      // outside the (rolled-back-on-throw) transaction.
      await this.db
        .update(refreshTokens)
        .set({ revokedAt: new Date() })
        .where(and(eq(refreshTokens.familyId, outcome.familyId), eq(refreshTokens.userId, outcome.userId)));
      throw new UnauthorizedException('Session expired. Please log in again.');
    }
    if (outcome.kind === 'invalid') {
      throw new UnauthorizedException('Session expired. Please log in again.');
    }

    return { ctx: { userId: outcome.userId, accountId: outcome.accountId }, refreshToken: outcome.refreshToken };
  }

  async signAccess(ctx: AuthContext): Promise<{ accessToken: string; accessExpiresInSec: number }> {
    const payload: AccessTokenPayload = { sub: ctx.userId, acc: ctx.accountId, role: ctx.role, typ: 'access' };
    return {
      accessToken: await this.jwt.signAsync(payload, { expiresIn: this.accessTtlSec }),
      accessExpiresInSec: this.accessTtlSec,
    };
  }

  async revoke(rawToken: string): Promise<void> {
    await this.db
      .update(refreshTokens)
      .set({ revokedAt: new Date() })
      .where(eq(refreshTokens.tokenHash, sha256(rawToken)));
  }

  async revokeAllForUser(userId: string): Promise<void> {
    await this.db.update(refreshTokens).set({ revokedAt: new Date() }).where(eq(refreshTokens.userId, userId));
  }

  private async createRefreshToken(ctx: AuthContext, familyId: string, userAgent?: string): Promise<string> {
    const raw = randomBytes(48).toString('base64url');
    await this.db.insert(refreshTokens).values({
      userId: ctx.userId,
      accountId: ctx.accountId || null,
      tokenHash: sha256(raw),
      familyId,
      userAgent,
      expiresAt: new Date(Date.now() + this.refreshTtlDays * 24 * 60 * 60 * 1000),
    });
    return raw;
  }
}
