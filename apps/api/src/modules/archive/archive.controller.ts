import { Controller, Get, ParseUUIDPipe, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { ArchiveService } from './archive.service';

@ApiTags('archive')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class ArchiveController {
  constructor(private readonly archive: ArchiveService) {}

  @Get('archive')
  @ApiOperation({ summary: 'Archived boards and items visible to the caller' })
  @ApiQuery({ name: 'boardId', required: false })
  listArchive(
    @CurrentAuth() auth: AuthContext,
    @Query('boardId', new ParseUUIDPipe({ optional: true })) boardId?: string,
  ) {
    return this.archive.listArchive(auth, boardId);
  }

  @Get('trash')
  @ApiOperation({ summary: 'Trashed boards and items (purged 30 days after deletion)' })
  @ApiQuery({ name: 'boardId', required: false })
  listTrash(
    @CurrentAuth() auth: AuthContext,
    @Query('boardId', new ParseUUIDPipe({ optional: true })) boardId?: string,
  ) {
    return this.archive.listTrash(auth, boardId);
  }
}
