import { Module } from '@nestjs/common';
import { MailModule } from '../mail/mail.module';
import { MembersController } from './members.controller';
import { MembersService } from './members.service';

@Module({
  imports: [MailModule],
  controllers: [MembersController],
  providers: [MembersService],
})
export class MembersModule {}
