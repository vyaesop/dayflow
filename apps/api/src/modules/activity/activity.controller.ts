import { Controller, Get, Param, ParseIntPipe, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { ActivityService } from './activity.service';

@ApiTags('activity')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class ActivityController {
  constructor(private readonly activity: ActivityService) {}

  @Get('boards/:id/activity')
  @ApiOperation({ summary: 'Board activity log with filters and keyset pagination' })
  @ApiQuery({ name: 'event', required: false })
  @ApiQuery({ name: 'actorId', required: false })
  @ApiQuery({ name: 'itemId', required: false })
  @ApiQuery({ name: 'from', required: false, description: 'ISO date (inclusive)' })
  @ApiQuery({ name: 'to', required: false, description: 'ISO date (inclusive)' })
  @ApiQuery({ name: 'cursor', required: false })
  @ApiQuery({ name: 'limit', required: false })
  list(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) boardId: string,
    @Query('event') event?: string,
    @Query('actorId', new ParseUUIDPipe({ optional: true })) actorId?: string,
    @Query('itemId', new ParseUUIDPipe({ optional: true })) itemId?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
    @Query('cursor') cursor?: string,
    @Query('limit', new ParseIntPipe({ optional: true })) limit?: number,
  ) {
    return this.activity.list(auth, boardId, { event, actorId, itemId, from, to, cursor, limit });
  }

  @Post('activity/:id/undo')
  @ApiOperation({ summary: 'Undo a change from the last 7 days' })
  undo(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.activity.undo(auth, id);
  }
}
