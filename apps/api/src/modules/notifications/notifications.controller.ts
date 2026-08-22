import { Controller, Get, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { NotificationsService } from './notifications.service';

@ApiTags('notifications')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  @ApiOperation({ summary: 'Notification feed for the current user and account' })
  list(@CurrentAuth() auth: AuthContext) {
    return this.notifications.list(auth);
  }

  @Post('read-all')
  @ApiOperation({ summary: 'Mark every unread notification as read' })
  markAllRead(@CurrentAuth() auth: AuthContext) {
    return this.notifications.markAllRead(auth);
  }

  @Post(':id/read')
  @ApiOperation({ summary: 'Mark one notification as read' })
  markRead(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.notifications.markRead(auth, id);
  }
}
