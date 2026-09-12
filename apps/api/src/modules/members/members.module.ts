import { Module } from '@nestjs/common';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { InvitePageController } from './invite-page.controller';
import { MembersController } from './members.controller';
import { MembersService } from './members.service';

@Module({
  imports: [MailModule, NotificationsModule],
  controllers: [MembersController, InvitePageController],
  providers: [MembersService],
})
export class MembersModule {}
