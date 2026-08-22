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
   */
  async rotate(rawToken: string, userAgent?: string): Promise<{ ctx: { userId: string; accountId: string | null }; refreshToken: string }> {
    const tokenHash = sha256(rawToken);
    const [row] = await this.db.select().from(refreshTokens).where(eq(refreshTokens.tokenHash, tokenHash)).limit(1);

    if (!row || row.expiresAt < new Date()) {
      throw new UnauthorizedException('Session expired. Please log in again.');
    }
    if (row.revokedAt || row.replacedById) {
      await this.db
        .update(refreshTokens)
        .set({ revokedAt: new Date() })
        .where(and(eq(refreshTokens.familyId, row.familyId), eq(refreshTokens.userId, row.userId)));
      throw new UnauthorizedException('Session expired. Please log in again.');
    }

    const newRaw = await this.createRefreshToken(
      { userId: row.userId, accountId: row.accountId ?? '', role: 'member' },
      row.familyId,
      userAgent,
    );
    const newHash = sha256(newRaw);
    const [replacement] = await this.db
      .select({ id: refreshTokens.id })
      .from(refreshTokens)
      .where(eq(refreshTokens.tokenHash, newHash))
      .limit(1);
    await this.db
      .update(refreshTokens)
      .set({ replacedById: replacement?.id, revokedAt: new Date() })
      .where(eq(refreshTokens.id, row.id));

    return { ctx: { userId: row.userId, accountId: row.accountId }, refreshToken: newRaw };
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
