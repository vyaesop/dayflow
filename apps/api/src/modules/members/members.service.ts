import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { and, asc, count, eq, gt, isNull } from 'drizzle-orm';
import { createHash, randomBytes } from 'node:crypto';
import { Database, DRIZZLE } from '../../db/db.module';
import {
  accountMembers,
  accounts,
  invitations,
  userProfiles,
  users,
} from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';
import type { Env } from '../../config/env';
import { MailService } from '../mail/mail.service';
import { NotifierService } from '../notifications/notifier.service';

const INVITE_TTL_DAYS = 14;

export interface MemberPayload {
  userId: string;
  fullName: string;
  email: string;
  avatarUrl: string | null;
  role: string;
  status: string;
  isYou: boolean;
}

export interface PendingInvitePayload {
  id: string;
  email: string;
  role: string;
  invitedByName: string;
  expiresAt: string;
  /** Dev-only: the accept link, so the flow is testable without an inbox. */
  devLink?: string;
}

export interface InvitePreview {
  valid: boolean;
  accountName?: string;
  inviterName?: string;
}

@Injectable()
export class MembersService {
  private readonly devEcho: boolean;
  private readonly publicBaseUrl: string | null;

  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly mail: MailService,
    private readonly notifier: NotifierService,
    config: ConfigService<Env, true>,
  ) {
    // Like the OTP echo, dev links (which carry the raw invite token) must
    // never appear in production responses.
    this.devEcho =
      config.get('NODE_ENV', { infer: true }) !== 'production' &&
      !!config.get('OTP_DEV_ECHO', { infer: true });
    this.publicBaseUrl = config.get('PUBLIC_BASE_URL', { infer: true }) ?? null;
  }

  /** Account members plus, for admins, the outstanding invitations. */
  async list(auth: AuthContext): Promise<{ members: MemberPayload[]; invitations: PendingInvitePayload[] }> {
    const memberRows = await this.db
      .select({
        userId: accountMembers.userId,
        role: accountMembers.role,
        status: accountMembers.status,
        fullName: userProfiles.fullName,
        avatarUrl: userProfiles.avatarUrl,
        email: users.email,
      })
      .from(accountMembers)
      .innerJoin(users, eq(accountMembers.userId, users.id))
      .leftJoin(userProfiles, eq(accountMembers.userId, userProfiles.userId))
      .where(eq(accountMembers.accountId, auth.accountId))
      .orderBy(asc(accountMembers.createdAt));

    const members: MemberPayload[] = memberRows.map((m) => ({
      userId: m.userId,
      fullName: m.fullName ?? m.email,
      email: m.email,
      avatarUrl: m.avatarUrl,
      role: m.role,
      status: m.status,
      isYou: m.userId === auth.userId,
    }));

    if (auth.role !== 'admin') return { members, invitations: [] };

    const inviteRows = await this.db
      .select({
        id: invitations.id,
        email: invitations.email,
        role: invitations.role,
        expiresAt: invitations.expiresAt,
        invitedByName: userProfiles.fullName,
      })
      .from(invitations)
      .leftJoin(userProfiles, eq(invitations.invitedByUserId, userProfiles.userId))
      .where(
        and(
          eq(invitations.accountId, auth.accountId),
          isNull(invitations.acceptedAt),
          gt(invitations.expiresAt, new Date()),
        ),
      )
      .orderBy(asc(invitations.createdAt));

    return {
      members,
      // Tokens are stored hashed, so links can only be produced at invite
      // time — re-inviting issues a fresh link.
      invitations: inviteRows.map((i) => ({
        id: i.id,
        email: i.email,
        role: i.role,
        invitedByName: i.invitedByName ?? '',
        expiresAt: i.expiresAt.toISOString(),
      })),
    };
  }

  /** Invites an email to the account. Admins only. */
  async invite(
    auth: AuthContext,
    email: string,
    role: 'admin' | 'member' | 'viewer' | 'guest',
  ): Promise<PendingInvitePayload> {
    this.assertAdmin(auth);
    const normalized = email.trim().toLowerCase();

    // Already a member? Nothing to invite.
    const [existingUser] = await this.db
      .select({ id: users.id })
      .from(users)
      .where(eq(users.email, normalized))
      .limit(1);
    if (existingUser) {
      const [alreadyMember] = await this.db
        .select({ id: accountMembers.id })
        .from(accountMembers)
        .where(
          and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.userId, existingUser.id)),
        )
        .limit(1);
      if (alreadyMember) throw new ConflictException('That person is already in this account');
    }

    // Re-inviting the same address replaces the outstanding invitation rather
    // than piling up rows.
    await this.db
      .delete(invitations)
      .where(
        and(
          eq(invitations.accountId, auth.accountId),
          eq(invitations.email, normalized),
          isNull(invitations.acceptedAt),
        ),
      );

    const token = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + INVITE_TTL_DAYS * 24 * 60 * 60 * 1000);

    const [invitation] = await this.db
      .insert(invitations)
      .values({
        accountId: auth.accountId,
        email: normalized,
        role,
        invitedByUserId: auth.userId,
        tokenHash: sha256(token),
        expiresAt,
      })
      .returning();

    const [account] = await this.db
      .select({ name: accounts.name })
      .from(accounts)
      .where(eq(accounts.id, auth.accountId))
      .limit(1);
    const [inviter] = await this.db
      .select({ fullName: userProfiles.fullName })
      .from(userProfiles)
      .where(eq(userProfiles.userId, auth.userId))
      .limit(1);

    await this.mail.sendInviteEmail(
      normalized,
      inviter?.fullName ?? 'A teammate',
      account?.name ?? 'Dayflow',
      this.inviteLink(token),
    );

    // If they already have a Dayflow login, surface it in-app too. The invite
    // email above is the delivery channel, so no second email here.
    if (existingUser) {
      await this.notifier.dispatch(
        [
          {
            accountId: auth.accountId,
            userId: existingUser.id,
            type: 'account_invite',
            actorUserId: auth.userId,
            payload: { accountName: account?.name ?? '', invitationId: invitation.id },
          },
        ],
        { email: false },
      );
    }

    return {
      id: invitation.id,
      email: invitation.email,
      role: invitation.role,
      invitedByName: inviter?.fullName ?? '',
      expiresAt: invitation.expiresAt.toISOString(),
      ...(this.devEcho ? { devLink: this.inviteLink(token) } : {}),
    };
  }

  async revokeInvite(auth: AuthContext, invitationId: string): Promise<{ ok: true }> {
    this.assertAdmin(auth);
    const deleted = await this.db
      .delete(invitations)
      .where(and(eq(invitations.id, invitationId), eq(invitations.accountId, auth.accountId)))
      .returning({ id: invitations.id });
    if (deleted.length === 0) throw new NotFoundException('Invitation not found');
    return { ok: true };
  }

  /**
   * Accepts an invitation for the signed-in user. The invited address does not
   * have to match the caller's — the token is the authority — but the caller
   * must not already be a member.
   */
  async accept(auth: AuthContext, token: string): Promise<{ accountId: string; accountName: string; role: string }> {
    const [invitation] = await this.db
      .select()
      .from(invitations)
      .where(eq(invitations.tokenHash, sha256(token)))
      .limit(1);

    if (!invitation || invitation.acceptedAt || invitation.expiresAt < new Date()) {
      throw new BadRequestException('This invitation is no longer valid');
    }

    const [existing] = await this.db
      .select({ id: accountMembers.id })
      .from(accountMembers)
      .where(
        and(eq(accountMembers.accountId, invitation.accountId), eq(accountMembers.userId, auth.userId)),
      )
      .limit(1);
    if (existing) {
      await this.db
        .update(invitations)
        .set({ acceptedAt: new Date() })
        .where(eq(invitations.id, invitation.id));
      throw new ConflictException('You are already in this account');
    }

    await this.db.transaction(async (tx) => {
      await tx.insert(accountMembers).values({
        accountId: invitation.accountId,
        userId: auth.userId,
        role: invitation.role,
        status: 'active',
        lastUsedAt: new Date(),
      });
      await tx.update(invitations).set({ acceptedAt: new Date() }).where(eq(invitations.id, invitation.id));
    });

    const [account] = await this.db
      .select({ name: accounts.name })
      .from(accounts)
      .where(eq(accounts.id, invitation.accountId))
      .limit(1);

    return {
      accountId: invitation.accountId,
      accountName: account?.name ?? '',
      role: invitation.role,
    };
  }

  async changeRole(
    auth: AuthContext,
    userId: string,
    role: 'admin' | 'member' | 'viewer' | 'guest',
  ): Promise<MemberPayload> {
    this.assertAdmin(auth);
    if (userId === auth.userId && role !== 'admin') {
      await this.assertNotLastAdmin(auth);
    }

    const [updated] = await this.db
      .update(accountMembers)
      .set({ role })
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.userId, userId)))
      .returning();
    if (!updated) throw new NotFoundException('Member not found');

    const [profile] = await this.db
      .select({ fullName: userProfiles.fullName, avatarUrl: userProfiles.avatarUrl, email: users.email })
      .from(users)
      .leftJoin(userProfiles, eq(users.id, userProfiles.userId))
      .where(eq(users.id, userId))
      .limit(1);

    return {
      userId,
      fullName: profile?.fullName ?? profile?.email ?? '',
      email: profile?.email ?? '',
      avatarUrl: profile?.avatarUrl ?? null,
      role: updated.role,
      status: updated.status,
      isYou: userId === auth.userId,
    };
  }

  /**
   * Deactivating keeps a member's rows (assignments, updates, ownership) but
   * blocks new sessions for this account; reactivating reverses it.
   */
  async setStatus(auth: AuthContext, userId: string, status: 'active' | 'deactivated'): Promise<MemberPayload> {
    this.assertAdmin(auth);
    if (userId === auth.userId && status === 'deactivated') {
      throw new BadRequestException('You cannot deactivate yourself');
    }
    const [target] = await this.db
      .select({ role: accountMembers.role, status: accountMembers.status })
      .from(accountMembers)
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.userId, userId)))
      .limit(1);
    if (!target) throw new NotFoundException('Member not found');
    if (status === 'deactivated' && target.role === 'admin') {
      await this.assertNotLastActiveAdmin(auth);
    }

    const [updated] = await this.db
      .update(accountMembers)
      .set({ status })
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.userId, userId)))
      .returning();

    const [profile] = await this.db
      .select({ fullName: userProfiles.fullName, avatarUrl: userProfiles.avatarUrl, email: users.email })
      .from(users)
      .leftJoin(userProfiles, eq(users.id, userProfiles.userId))
      .where(eq(users.id, userId))
      .limit(1);

    return {
      userId,
      fullName: profile?.fullName ?? profile?.email ?? '',
      email: profile?.email ?? '',
      avatarUrl: profile?.avatarUrl ?? null,
      role: updated.role,
      status: updated.status,
      isYou: userId === auth.userId,
    };
  }

  /** An account must keep at least one admin who can still sign in. */
  private async assertNotLastActiveAdmin(auth: AuthContext): Promise<void> {
    const [admins] = await this.db
      .select({ n: count() })
      .from(accountMembers)
      .where(
        and(
          eq(accountMembers.accountId, auth.accountId),
          eq(accountMembers.role, 'admin'),
          eq(accountMembers.status, 'active'),
        ),
      );
    if (Number(admins?.n ?? 0) <= 1) {
      throw new BadRequestException('An account must keep at least one active admin');
    }
  }

  async remove(auth: AuthContext, userId: string): Promise<{ ok: true }> {
    this.assertAdmin(auth);
    if (userId === auth.userId) {
      await this.assertNotLastAdmin(auth);
    }

    const deleted = await this.db
      .delete(accountMembers)
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.userId, userId)))
      .returning({ id: accountMembers.id });
    if (deleted.length === 0) throw new NotFoundException('Member not found');
    return { ok: true };
  }

  private assertAdmin(auth: AuthContext): void {
    if (auth.role !== 'admin') {
      throw new ForbiddenException('Only account admins can manage members');
    }
  }

  /** An account must always keep at least one admin who can administer it. */
  private async assertNotLastAdmin(auth: AuthContext): Promise<void> {
    const [admins] = await this.db
      .select({ n: count() })
      .from(accountMembers)
      .where(and(eq(accountMembers.accountId, auth.accountId), eq(accountMembers.role, 'admin')));
    if (Number(admins?.n ?? 0) <= 1) {
      throw new BadRequestException('An account must keep at least one admin');
    }
  }

  /**
   * What the public invite landing page shows before the viewer has an app
   * session: just enough to be welcoming, nothing sensitive.
   */
  async preview(token: string): Promise<InvitePreview> {
    const [invitation] = await this.db
      .select({
        acceptedAt: invitations.acceptedAt,
        expiresAt: invitations.expiresAt,
        accountName: accounts.name,
        inviterName: userProfiles.fullName,
      })
      .from(invitations)
      .innerJoin(accounts, eq(invitations.accountId, accounts.id))
      .leftJoin(userProfiles, eq(invitations.invitedByUserId, userProfiles.userId))
      .where(eq(invitations.tokenHash, sha256(token)))
      .limit(1);

    if (!invitation || invitation.acceptedAt || invitation.expiresAt < new Date()) {
      return { valid: false };
    }
    return {
      valid: true,
      accountName: invitation.accountName,
      inviterName: invitation.inviterName ?? 'A teammate',
    };
  }

  /**
   * Invite emails need a clickable https link, so when PUBLIC_BASE_URL is set
   * the link points at this API's landing page (which hands off to the app);
   * without it the raw deep link is the best available.
   */
  private inviteLink(token: string): string {
    if (this.publicBaseUrl) return `${this.publicBaseUrl}/invite/${token}`;
    return `dayflow:///invite/${token}`;
  }
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}
