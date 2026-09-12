import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { validateEnv, type Env } from './config/env';
import { HttpExceptionFilter } from './common/http-exception.filter';
import { LoggingInterceptor } from './common/logging.interceptor';
import { DbModule } from './db/db.module';
import { AccessModule } from './modules/access/access.module';
import { ActivityModule } from './modules/activity/activity.module';
import { AdminModule } from './modules/admin/admin.module';
import { ArchiveModule } from './modules/archive/archive.module';
import { AuthModule } from './modules/auth/auth.module';
import { BoardsModule } from './modules/boards/boards.module';
import { FilesModule } from './modules/files/files.module';
import { HealthModule } from './modules/health/health.module';
import { HomeModule } from './modules/home/home.module';
import { ItemsModule } from './modules/items/items.module';
import { MailModule } from './modules/mail/mail.module';
import { MaintenanceModule } from './modules/maintenance/maintenance.module';
import { MembersModule } from './modules/members/members.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { SearchModule } from './modules/search/search.module';
import { UsersModule } from './modules/users/users.module';
import { ViewsModule } from './modules/views/views.module';

// Crons need a long-running process; on serverless the module is skipped and
// the @Cron methods stay inert (housekeeping then falls to platform crons).
const serverless = !!process.env.VERCEL || !!process.env.AWS_LAMBDA_FUNCTION_NAME;

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
    ...(serverless ? [] : [ScheduleModule.forRoot()]),
    DbModule,
    AccessModule,
    RealtimeModule,
    MailModule,
    AuthModule,
    UsersModule,
    MembersModule,
    BoardsModule,
    ViewsModule,
    ActivityModule,
    ArchiveModule,
    ItemsModule,
    FilesModule,
    HomeModule,
    SearchModule,
    NotificationsModule,
    AdminModule,
    HealthModule,
    MaintenanceModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_FILTER, useClass: HttpExceptionFilter },
    { provide: APP_INTERCEPTOR, useClass: LoggingInterceptor },
  ],
})
export class AppModule {}
