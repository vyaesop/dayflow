import { Body, Controller, Get, Headers, Patch, Post, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiOperation, ApiTags } from '@nestjs/swagger';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { IsBoolean, IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { SessionService } from '../auth/session.service';
import { FilesService, MAX_UPLOAD_BYTES } from '../files/files.service';
import { UsersService } from './users.service';

const PERSONAL_STATUSES = [
  'working_from_home',
  'out_sick',
  'on_break',
  'out_of_office',
  'working_outside',
  'family_time',
  'do_not_disturb',
] as const;

class UpdateMeDto {
  @ApiPropertyOptional({ example: 'Alex Smith' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  fullName?: string;

  @ApiPropertyOptional({ example: 'en' })
  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;

  @ApiPropertyOptional({ enum: PERSONAL_STATUSES, nullable: true })
  @IsOptional()
  @IsIn([...PERSONAL_STATUSES, null])
  personalStatus?: string | null;
}

class ChecklistDto {
  @ApiProperty({ example: 'get_started_basics' })
  @IsString()
  @MaxLength(60)
  step!: string;
}

class FeedbackDto {
  @ApiProperty({ example: "There's a bug on the home screen" })
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  message!: string;
}

class NotificationPrefsDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  emailEnabled?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  pushEnabled?: boolean;
}

@ApiTags('me')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('me')
export class UsersController {
  constructor(
    private readonly users: UsersService,
    private readonly sessions: SessionService,
    private readonly files: FilesService,
  ) {}

  @Get()
  @ApiOperation({ summary: 'Current user, profile, and account memberships' })
  me(@CurrentAuth() auth: AuthContext) {
    return this.sessions.buildMe(auth.userId, auth.accountId);
  }

  @Patch()
  @ApiOperation({ summary: 'Update profile fields' })
  async update(@CurrentAuth() auth: AuthContext, @Body() dto: UpdateMeDto) {
    await this.users.updateProfile(auth.userId, dto);
    return this.sessions.buildMe(auth.userId, auth.accountId);
  }

  @Post('checklist')
  @ApiOperation({ summary: 'Mark a setup-checklist step as done' })
  async checklist(@CurrentAuth() auth: AuthContext, @Body() dto: ChecklistDto) {
    await this.users.completeChecklistStep(auth.userId, dto.step);
    return this.sessions.buildMe(auth.userId, auth.accountId);
  }

  @Post('avatar')
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 } }))
  @ApiConsumes('multipart/form-data')
  @ApiBody({ schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } } } })
  @ApiOperation({ summary: 'Upload a profile photo' })
  async avatar(@CurrentAuth() auth: AuthContext, @UploadedFile() file: Express.Multer.File) {
    const stored = await this.files.upload(auth, file, {}, { imageOnly: true });
    await this.users.setAvatarUrl(auth.userId, stored.url);
    return this.sessions.buildMe(auth.userId, auth.accountId);
  }

  @Get('notification-prefs')
  @ApiOperation({ summary: 'Notification delivery preferences' })
  notificationPrefs(@CurrentAuth() auth: AuthContext) {
    return this.users.getNotificationPrefs(auth.userId);
  }

  @Patch('notification-prefs')
  @ApiOperation({ summary: 'Update notification delivery preferences' })
  updateNotificationPrefs(@CurrentAuth() auth: AuthContext, @Body() dto: NotificationPrefsDto) {
    return this.users.updateNotificationPrefs(auth.userId, dto);
  }

  @Post('feedback')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @ApiOperation({ summary: 'Send product feedback' })
  async feedback(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: FeedbackDto,
    @Headers('user-agent') userAgent?: string,
  ) {
    await this.users.saveFeedback(auth, dto.message, userAgent);
    return { ok: true };
  }
}
