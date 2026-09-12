import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OAuth2Client } from 'google-auth-library';
import { eq } from 'drizzle-orm';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';
import { Database, DRIZZLE } from '../../db/db.module';
import {
  accountMembers,
  accounts,
  notificationPrefs,
  userProfiles,
  users,
  workspaces,
} from '../../db/schema';
import type { AuthContext, SelectTokenPayload, SignupTokenPayload } from '../../common/auth-context';
import type { Env } from '../../config/env';
import { MailService } from '../mail/mail.service';
import { BoardSeederService } from '../boards/board-seeder.service';
import { OtpService } from './otp.service';
import { SessionService, type AccountSummary, type AuthSession } from './session.service';
import { TokenService } from './token.service';
import type { CompleteSignupDto } from './dto/auth.dto';

export type OtpVerifyResult =
  | { status: 'new_user'; signupToken: string }
  | { status: 'existing'; selectToken: string; accounts: AccountSummary[] };

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly devEcho: boolean;
  private readonly googleClient: OAuth2Client | null;
  private readonly googleClientId: string | null;

  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly otp: OtpService,
    private readonly tokens: TokenService,
    private readonly sessions: SessionService,
    private readonly mail: MailService,
    private readonly jwt: JwtService,
    private readonly seeder: BoardSeederService,
    config: ConfigService<Env, true>,
  ) {
    this.devEcho = config.get('NODE_ENV', { infer: true }) !== 'production' && !!config.get('OTP_DEV_ECHO', { infer: true });
    const googleClientId = config.get('GOOGLE_CLIENT_ID', { infer: true });
    this.googleClientId = googleClientId ?? null;
    this.googleClient = googleClientId ? new OAuth2Client(googleClientId) : null;
  }

  async requestOtp(email: string, purpose: 'signup' | 'login'): Promise<{ ok: true; resendAfterSec: number; devCode?: string }> {
    const normalized = normalizeEmail(email);
    const code = await this.otp.issue(normalized, purpose);
    await this.mail.sendOtpEmail(normalized, code, purpose);
    if (this.devEcho) {
      this.logger.log(`[dev] OTP for ${normalized}: ${code}`);
      return { ok: true, resendAfterSec: 30, devCode: code };
    }
    return { ok: true, resendAfterSec: 30 };
  }

  async verifyOtp(email: string, code: string): Promise<OtpVerifyResult> {
    const normalized = normalizeEmail(email);
    await this.otp.verifyAndConsume(normalized, code);

    const [user] = await this.db.select().from(users).where(eq(users.email, normalized)).limit(1);
    if (!user) {
      const payload: SignupTokenPayload = { email: normalized, typ: 'signup' };
      const signupToken = await this.jwt.signAsync(payload, { expiresIn: '30m' });
      return { status: 'new_user', signupToken };
    }

    if (!user.emailVerifiedAt) {
      await this.db.update(users).set({ emailVerifiedAt: new Date() }).where(eq(users.id, user.id));
    }
    const payload: SelectTokenPayload = { sub: user.id, typ: 'select' };
    const selectToken = await this.jwt.signAsync(payload, { expiresIn: '10m' });
    const accountList = await this.sessions.accountsForUser(user.id);
    return { status: 'existing', selectToken, accounts: accountList };
  }

  async completeSignup(dto: CompleteSignupDto, userAgent?: string): Promise<AuthSession> {
    let payload: SignupTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<SignupTokenPayload>(dto.signupToken);
      if (payload.typ !== 'signup') throw new Error();
    } catch {
      throw new UnauthorizedException('Sign-up session expired. Please verify your email again.');
    }

    const email = payload.email;
    const [existing] = await this.db.select({ id: users.id }).from(users).where(eq(users.email, email)).limit(1);
    if (existing) {
      throw new ConflictException('An account with this email already exists. Please log in.');
    }

    const passwordHash = await argon2.hash(dto.password);
    const { userId, accountId } = await this.db.transaction(async (tx) => {
      const [user] = await tx
        .insert(users)
        .values({ email, passwordHash, emailVerifiedAt: new Date() })
        .returning({ id: users.id });

      await tx.insert(userProfiles).values({
        userId: user.id,
        fullName: dto.fullName.trim(),
        useFor: dto.useFor,
        manageCategory: dto.manageCategory,
        workCategory: dto.workCategory,
        onboardingCompletedAt: new Date(),
        setupChecklist: ['create_first_board'],
      });
      await tx.insert(notificationPrefs).values({ userId: user.id });

      const accountName = `${firstNameOf(dto.fullName)}'s team`;
      const [account] = await tx
        .insert(accounts)
        .values({ name: accountName, slug: slugify(accountName) })
        .returning({ id: accounts.id });
      await tx.insert(accountMembers).values({
        accountId: account.id,
        userId: user.id,
        role: 'admin',
        lastUsedAt: new Date(),
      });

      return { userId: user.id, accountId: account.id };
    });

    // Seed workspace + first board outside the user transaction to keep it small.
    const [workspace] = await this.db
      .insert(workspaces)
      .values({ accountId, name: 'Main workspace', createdByUserId: userId })
      .returning({ id: workspaces.id });
    await this.seeder.seedFirstBoard({ accountId, workspaceId: workspace.id, userId });

    return this.sessions.createSession(userId, accountId, userAgent);
  }

  async selectAccount(selectToken: string, accountId: string, userAgent?: string): Promise<AuthSession> {
    let payload: SelectTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<SelectTokenPayload>(selectToken);
      if (payload.typ !== 'select') throw new Error();
    } catch {
      throw new UnauthorizedException('Login session expired. Please start again.');
    }
    return this.sessions.createSession(payload.sub, accountId, userAgent);
  }

  async passwordLogin(
    email: string,
    password: string,
    userAgent?: string,
  ): Promise<{ status: 'ok'; session: AuthSession } | { status: 'choose'; selectToken: string; accounts: AccountSummary[] }> {
    const normalized = normalizeEmail(email);
    const [user] = await this.db.select().from(users).where(eq(users.email, normalized)).limit(1);
    if (!user?.passwordHash || !(await argon2.verify(user.passwordHash, password))) {
      throw new UnauthorizedException('Incorrect email or password.');
    }

    const accountList = await this.sessions.accountsForUser(user.id);
    if (accountList.length === 0) {
      throw new UnauthorizedException('This user has no active accounts.');
    }
    if (accountList.length === 1) {
      return { status: 'ok', session: await this.sessions.createSession(user.id, accountList[0].id, userAgent) };
    }
    const payload: SelectTokenPayload = { sub: user.id, typ: 'select' };
    const selectToken = await this.jwt.signAsync(payload, { expiresIn: '10m' });
    return { status: 'choose', selectToken, accounts: accountList };
  }

  async googleLogin(idToken: string, userAgent?: string): Promise<AuthSession> {
    if (!this.googleClient || !this.googleClientId) {
      throw new BadRequestException('Google sign-in is not configured on this server.');
    }
    // `audience` is mandatory: without it any Google OAuth client's tokens
    // would be accepted, letting a third-party app log in as its users here.
    let info;
    try {
      const ticket = await this.googleClient.verifyIdToken({ idToken, audience: this.googleClientId });
      info = ticket.getPayload();
    } catch {
      throw new UnauthorizedException('Google token could not be verified.');
    }
    if (!info?.email || !info.sub) {
      throw new UnauthorizedException('Google token could not be verified.');
    }
    const email = normalizeEmail(info.email);

    const [existing] = await this.db.select().from(users).where(eq(users.email, email)).limit(1);
    if (existing) {
      if (!existing.googleSub) {
        await this.db.update(users).set({ googleSub: info.sub, emailVerifiedAt: existing.emailVerifiedAt ?? new Date() }).where(eq(users.id, existing.id));
      }
      const accountList = await this.sessions.accountsForUser(existing.id);
      if (accountList.length === 0) throw new UnauthorizedException('This user has no active accounts.');
      return this.sessions.createSession(existing.id, accountList[0].id, userAgent);
    }

    // First-time Google user: provision like a signup, onboarding still pending.
    const fullName = info.name ?? email.split('@')[0];
    const { userId, accountId } = await this.db.transaction(async (tx) => {
      const [user] = await tx
        .insert(users)
        .values({ email, googleSub: info.sub, emailVerifiedAt: new Date() })
        .returning({ id: users.id });
      await tx.insert(userProfiles).values({
        userId: user.id,
        fullName,
        avatarUrl: info.picture,
        setupChecklist: ['create_first_board'],
      });
      await tx.insert(notificationPrefs).values({ userId: user.id });
      const accountName = `${firstNameOf(fullName)}'s team`;
      const [account] = await tx
        .insert(accounts)
        .values({ name: accountName, slug: slugify(accountName) })
        .returning({ id: accounts.id });
      await tx.insert(accountMembers).values({ accountId: account.id, userId: user.id, role: 'admin', lastUsedAt: new Date() });
      return { userId: user.id, accountId: account.id };
    });
    const [workspace] = await this.db
      .insert(workspaces)
      .values({ accountId, name: 'Main workspace', createdByUserId: userId })
      .returning({ id: workspaces.id });
    await this.seeder.seedFirstBoard({ accountId, workspaceId: workspace.id, userId });
    return this.sessions.createSession(userId, accountId, userAgent);
  }

  async refresh(rawToken: string, userAgent?: string): Promise<AuthSession> {
    const { ctx, refreshToken } = await this.tokens.rotate(rawToken, userAgent);
    if (!ctx.accountId) throw new UnauthorizedException('Session expired. Please log in again.');
    await this.sessions.assertActiveMembership(ctx.userId, ctx.accountId);
    const me = await this.sessions.buildMe(ctx.userId, ctx.accountId);
    const access = await this.tokens.signAccess({
      userId: ctx.userId,
      accountId: ctx.accountId,
      role: me.account.role as AuthContext['role'],
    });
    return { ...me, ...access, refreshToken };
  }

  async logout(rawToken: string): Promise<void> {
    await this.tokens.revoke(rawToken);
  }

  async switchAccount(auth: AuthContext, accountId: string, userAgent?: string): Promise<AuthSession> {
    return this.sessions.createSession(auth.userId, accountId, userAgent);
  }

  async changePassword(auth: AuthContext, currentPassword: string, newPassword: string): Promise<void> {
    const [user] = await this.db.select().from(users).where(eq(users.id, auth.userId)).limit(1);
    if (!user) throw new UnauthorizedException();
    if (user.passwordHash && !(await argon2.verify(user.passwordHash, currentPassword))) {
      throw new BadRequestException('Current password is incorrect.');
    }
    await this.db.update(users).set({ passwordHash: await argon2.hash(newPassword), updatedAt: new Date() }).where(eq(users.id, auth.userId));
    await this.tokens.revokeAllForUser(auth.userId);
  }
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/** Exported for unit tests; used to derive the default account name. */
export function firstNameOf(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] || 'My';
}

/** Exported for unit tests. Appends 6 random hex chars to keep slugs unique. */
export function slugify(name: string): string {
  const base = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return `${base}-${randomBytes(3).toString('hex')}`;
}
