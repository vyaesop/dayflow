import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { and, desc, eq } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { accountMembers, accounts, userProfiles, users } from '../../db/schema';
import { TokenService } from './token.service';

export interface AccountSummary {
  id: string;
  name: string;
  slug: string;
  logoUrl: string | null;
  role: string;
  lastUsedAt: string | null;
}

export interface MePayload {
  user: {
    id: string;
    email: string;
    fullName: string;
    avatarUrl: string | null;
    personalStatus: string | null;
    language: string;
    onboardingCompleted: boolean;
    setupChecklist: string[];
  };
  account: AccountSummary;
  accounts: AccountSummary[];
}

export interface AuthSession extends MePayload {
  accessToken: string;
  accessExpiresInSec: number;
  refreshToken: string;
}

@Injectable()
export class SessionService {
  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly tokens: TokenService,
  ) {}

  async accountsForUser(userId: string): Promise<AccountSummary[]> {
    const rows = await this.db
      .select({
        id: accounts.id,
        name: accounts.name,
        slug: accounts.slug,
        logoUrl: accounts.logoUrl,
        role: accountMembers.role,
        lastUsedAt: accountMembers.lastUsedAt,
      })
      .from(accountMembers)
      .innerJoin(accounts, eq(accountMembers.accountId, accounts.id))
      .where(and(eq(accountMembers.userId, userId), eq(accountMembers.status, 'active')))
      .orderBy(desc(accountMembers.lastUsedAt));
    return rows.map((r) => ({ ...r, lastUsedAt: r.lastUsedAt?.toISOString() ?? null }));
  }

  async buildMe(userId: string, accountId: string): Promise<MePayload> {
    const [row] = await this.db
      .select({
        id: users.id,
        email: users.email,
        fullName: userProfiles.fullName,
        avatarUrl: userProfiles.avatarUrl,
        personalStatus: userProfiles.personalStatus,
        language: userProfiles.language,
        onboardingCompletedAt: userProfiles.onboardingCompletedAt,
        setupChecklist: userProfiles.setupChecklist,
      })
      .from(users)
      .innerJoin(userProfiles, eq(userProfiles.userId, users.id))
      .where(eq(users.id, userId))
      .limit(1);
    if (!row) throw new UnauthorizedException('User not found');

    const allAccounts = await this.accountsForUser(userId);
    const account = allAccounts.find((a) => a.id === accountId);
    if (!account) throw new UnauthorizedException('Not a member of this account');

    return {
      user: {
        id: row.id,
        email: row.email,
        fullName: row.fullName,
        avatarUrl: row.avatarUrl,
        personalStatus: row.personalStatus,
        language: row.language,
        onboardingCompleted: row.onboardingCompletedAt != null,
        setupChecklist: row.setupChecklist,
      },
      account,
      accounts: allAccounts,
    };
  }

  async createSession(userId: string, accountId: string, userAgent?: string): Promise<AuthSession> {
    const me = await this.buildMe(userId, accountId);
    await this.db
      .update(accountMembers)
      .set({ lastUsedAt: new Date() })
      .where(and(eq(accountMembers.userId, userId), eq(accountMembers.accountId, accountId)));
    const pair = await this.tokens.issuePair(
      { userId, accountId, role: me.account.role as 'admin' | 'member' | 'viewer' | 'guest' },
      userAgent,
    );
    return { ...me, ...pair };
  }
}
