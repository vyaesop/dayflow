import { Inject, Injectable } from '@nestjs/common';
import { eq, sql } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { feedback, notificationPrefs, userProfiles } from '../../db/schema';
import type { AuthContext } from '../../common/auth-context';

@Injectable()
export class UsersService {
  constructor(@Inject(DRIZZLE) private readonly db: Database) {}

  async updateProfile(
    userId: string,
    fields: { fullName?: string; language?: string; personalStatus?: string | null },
  ): Promise<void> {
    const patch: Partial<typeof userProfiles.$inferInsert> = { updatedAt: new Date() };
    if (fields.fullName !== undefined) patch.fullName = fields.fullName.trim();
    if (fields.language !== undefined) patch.language = fields.language;
    if (fields.personalStatus !== undefined) patch.personalStatus = fields.personalStatus;
    await this.db.update(userProfiles).set(patch).where(eq(userProfiles.userId, userId));
  }

  async getNotificationPrefs(userId: string): Promise<{ emailEnabled: boolean; pushEnabled: boolean }> {
    const [row] = await this.db
      .select({ emailEnabled: notificationPrefs.emailEnabled, pushEnabled: notificationPrefs.pushEnabled })
      .from(notificationPrefs)
      .where(eq(notificationPrefs.userId, userId))
      .limit(1);
    // The row is seeded at signup; fall back to defaults for legacy users.
    return row ?? { emailEnabled: true, pushEnabled: true };
  }

  async updateNotificationPrefs(
    userId: string,
    fields: { emailEnabled?: boolean; pushEnabled?: boolean },
  ): Promise<{ emailEnabled: boolean; pushEnabled: boolean }> {
    await this.db
      .insert(notificationPrefs)
      .values({ userId, ...fields, updatedAt: new Date() })
      .onConflictDoUpdate({ target: notificationPrefs.userId, set: { ...fields, updatedAt: new Date() } });
    return this.getNotificationPrefs(userId);
  }

  async setAvatarUrl(userId: string, avatarUrl: string | null): Promise<void> {
    await this.db
      .update(userProfiles)
      .set({ avatarUrl, updatedAt: new Date() })
      .where(eq(userProfiles.userId, userId));
  }

  async saveFeedback(auth: AuthContext, message: string, userAgent?: string): Promise<void> {
    await this.db.insert(feedback).values({
      accountId: auth.accountId,
      userId: auth.userId,
      message,
      userAgent: userAgent?.slice(0, 400),
    });
  }

  async completeChecklistStep(userId: string, step: string): Promise<void> {
    await this.db
      .update(userProfiles)
      .set({
        setupChecklist: sql`(select array(select distinct unnest(${userProfiles.setupChecklist} || ${step}::text)))`,
        updatedAt: new Date(),
      })
      .where(eq(userProfiles.userId, userId));
  }
}
