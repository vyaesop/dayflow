import { Inject, Injectable, Logger } from '@nestjs/common';
import { eq, inArray } from 'drizzle-orm';
import { Database, DRIZZLE } from '../../db/db.module';
import { notificationPrefs, notifications, userProfiles, users } from '../../db/schema';
import { MailService } from '../mail/mail.service';
import { describeNotification } from './notification-copy';

export interface NotificationInput {
  accountId: string;
  userId: string;
  type: 'mention' | 'assigned' | 'reply' | 'account_invite' | 'board_invite' | 'update_on_subscribed';
  actorUserId: string | null;
  payload: Record<string, unknown>;
}

/**
 * Single entry point for creating notifications: writes the in-app row and
 * emails each recipient who has email notifications enabled. Email delivery
 * is best-effort — a mail failure never fails the request that triggered it.
 */
@Injectable()
export class NotifierService {
  private readonly logger = new Logger(NotifierService.name);

  constructor(
    @Inject(DRIZZLE) private readonly db: Database,
    private readonly mail: MailService,
  ) {}

  async dispatch(inputs: NotificationInput[], options?: { email?: boolean }): Promise<void> {
    if (inputs.length === 0) return;
    await this.db.insert(notifications).values(inputs);

    if (options?.email === false) return;
    try {
      await this.emailFanout(inputs);
    } catch (err) {
      this.logger.warn(`Notification email fan-out failed: ${err instanceof Error ? err.message : err}`);
    }
  }

  private async emailFanout(inputs: NotificationInput[]): Promise<void> {
    const recipientIds = [...new Set(inputs.map((i) => i.userId))];
    const actorIds = [...new Set(inputs.map((i) => i.actorUserId).filter((v): v is string => !!v))];

    const [recipients, actors] = await Promise.all([
      this.db
        .select({ id: users.id, email: users.email, emailEnabled: notificationPrefs.emailEnabled })
        .from(users)
        .leftJoin(notificationPrefs, eq(notificationPrefs.userId, users.id))
        .where(inArray(users.id, recipientIds)),
      actorIds.length
        ? this.db
            .select({ userId: userProfiles.userId, fullName: userProfiles.fullName })
            .from(userProfiles)
            .where(inArray(userProfiles.userId, actorIds))
        : Promise.resolve([]),
    ]);

    const recipientById = new Map(recipients.map((r) => [r.id, r]));
    const actorNameById = new Map(actors.map((a) => [a.userId, a.fullName]));

    for (const input of inputs) {
      const recipient = recipientById.get(input.userId);
      // Missing prefs row means defaults (enabled); an explicit false opts out.
      if (!recipient || recipient.emailEnabled === false) continue;

      const copy = describeNotification(
        input.type,
        input.actorUserId ? (actorNameById.get(input.actorUserId) ?? '') : '',
        input.payload as { boardName?: string; itemName?: string; accountName?: string; snippet?: string },
      );
      if (!copy) continue;

      try {
        await this.mail.sendNotificationEmail(recipient.email, copy.subject, copy.line);
      } catch (err) {
        this.logger.warn(
          `Notification email to ${recipient.email} failed: ${err instanceof Error ? err.message : err}`,
        );
      }
    }
  }
}
