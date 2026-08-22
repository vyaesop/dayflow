import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { validateEnv, type Env } from './config/env';
import { DbModule } from './db/db.module';
import { AuthModule } from './modules/auth/auth.module';
import { BoardsModule } from './modules/boards/boards.module';
import { FilesModule } from './modules/files/files.module';
import { HomeModule } from './modules/home/home.module';
import { ItemsModule } from './modules/items/items.module';
import { MailModule } from './modules/mail/mail.module';
import { MembersModule } from './modules/members/members.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { SearchModule } from './modules/search/search.module';
import { UsersModule } from './modules/users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    JwtModule.registerAsync({
      global: true,
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>) => ({
        secret: config.get('JWT_SECRET', { infer: true }),
      }),
    }),
    ThrottlerModule.forRoot([{ limit: 120, ttl: 60_000 }]),
    DbModule,
    RealtimeModule,
    MailModule,
    AuthModule,
    UsersModule,
    MembersModule,
    BoardsModule,
    ItemsModule,
    FilesModule,
    HomeModule,
    SearchModule,
    NotificationsModule,
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
