import { Module } from '@nestjs/common';
import { MailModule } from '../mail/mail.module';
import { BoardsModule } from '../boards/boards.module';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { OtpService } from './otp.service';
import { SessionService } from './session.service';
import { TokenService } from './token.service';

@Module({
  imports: [MailModule, BoardsModule],
  controllers: [AuthController],
  providers: [AuthService, OtpService, SessionService, TokenService],
  exports: [SessionService, TokenService],
})
export class AuthModule {}
