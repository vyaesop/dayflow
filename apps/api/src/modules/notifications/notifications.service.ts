import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { and, count, desc, eq, isNull } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { notifications, userProfiles } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

export interface NotificationPayload {
  id: string;
  type: string;
  actor: { userId: string; fullName: string; avatarUrl: string | null } | null;
  payload: Record<string, unknown>;
  readAt: string | null;
  createdAt: string;
}

@Injectable()
export class NotificationsService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  async list(auth: AuthContext, limit = 50): Promise<{ notifications: NotificationPayload[]; unreadCount: number }> {
    const [rows, [unread]] = await Promise.all([
      this.db
        .select({
          id: notifications.id,
          type: notifications.type,
          payload: notifications.payload,
          readAt: notifications.readAt,
          createdAt: notifications.createdAt,
          actorUserId: notifications.actorUserId,
          actorName: userProfiles.fullName,
          actorAvatar: userProfiles.avatarUrl,
        })
        .from(notifications)
        .leftJoin(userProfiles, eq(notifications.actorUserId, userProfiles.userId))
        .where(and(eq(notifications.userId, auth.userId), eq(notifications.accountId, auth.accountId)))
        .orderBy(desc(notifications.createdAt))
        .limit(limit),
      this.db
        .select({ n: count() })
        .from(notifications)
        .where(
          and(
            eq(notifications.userId, auth.userId),
            eq(notifications.accountId, auth.accountId),
            isNull(notifications.readAt),
          ),
        ),
    ]);

    return {
      notifications: rows.map((r) => ({
        id: r.id,
        type: r.type,
        actor: r.actorUserId
          ? { userId: r.actorUserId, fullName: r.actorName ?? '', avatarUrl: r.actorAvatar }
          : null,
        payload: (r.payload ?? {}) as Record<string, unknown>,
        readAt: r.readAt?.toISOString() ?? null,
        createdAt: r.createdAt.toISOString(),
      })),
      unreadCount: Number(unread?.n ?? 0),
    };
  }

  async markRead(auth: AuthContext, notificationId: string): Promise<{ ok: true }> {
    const result = await this.db
      .update(notifications)
      .set({ readAt: new Date() })
      .where(and(eq(notifications.id, notificationId), eq(notifications.userId, auth.userId)))
      .returning({ id: notifications.id });
    if (result.length === 0) throw new NotFoundException('Notification not found');
    return { ok: true };
  }

  async markAllRead(auth: AuthContext): Promise<{ ok: true; updated: number }> {
    const result = await this.db
      .update(notifications)
      .set({ readAt: new Date() })
      .where(
        and(
          eq(notifications.userId, auth.userId),
          eq(notifications.accountId, auth.accountId),
          isNull(notifications.readAt),
        ),
      )
      .returning({ id: notifications.id });
    return { ok: true, updated: result.length };
  }
}
