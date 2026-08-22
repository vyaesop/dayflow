import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { ItemsService } from './items.service';

export class AddUpdateDto {
  @ApiProperty({ example: 'Kicked this off — @Alex Smith can you review?' })
  @IsString()
  @MinLength(1)
  @MaxLength(5000)
  body!: string;

  @ApiPropertyOptional({ description: 'Reply to this top-level update' })
  @IsOptional()
  @IsUUID()
  parentId?: string;
}

export class EditUpdateDto {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(5000)
  body!: string;
}

@ApiTags('items')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class ItemsController {
  constructor(private readonly items: ItemsService) {}

  @Get('my-work')
  @ApiOperation({ summary: 'Items assigned to me, bucketed by due date' })
  @ApiQuery({ name: 'includeDone', required: false, example: 'true' })
  myWork(@CurrentAuth() auth: AuthContext, @Query('includeDone') includeDone?: string) {
    return this.items.myWork(auth, includeDone === 'true');
  }

  @Get('updates/feed')
  @ApiOperation({ summary: 'Company-wide update feed (top-level updates across boards)' })
  @ApiQuery({ name: 'boardId', required: false })
  @ApiQuery({ name: 'bookmarked', required: false, example: 'true' })
  feed(
    @CurrentAuth() auth: AuthContext,
    @Query('boardId') boardId?: string,
    @Query('bookmarked') bookmarked?: string,
  ) {
    return this.items.updateFeed(auth, { boardId, bookmarked: bookmarked === 'true' });
  }

  @Get('items/:id')
  @ApiOperation({ summary: 'Item detail with cell values, updates and activity' })
  getItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.getItem(auth, id);
  }

  @Post('items/:id/updates')
  @ApiOperation({ summary: 'Post an update or a reply (notifies @mentions and the parent author)' })
  addUpdate(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AddUpdateDto,
  ) {
    return this.items.addUpdate(auth, id, dto.body, dto.parentId);
  }

  @Patch('updates/:id')
  @ApiOperation({ summary: 'Edit your own update' })
  editUpdate(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: EditUpdateDto,
  ) {
    return this.items.editUpdate(auth, id, dto.body);
  }

  @Post('updates/:id/like')
  @ApiOperation({ summary: 'Toggle your like on an update' })
  toggleLike(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.toggleLike(auth, id);
  }

  @Post('updates/:id/bookmark')
  @ApiOperation({ summary: 'Toggle your bookmark on an update' })
  toggleBookmark(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.toggleBookmark(auth, id);
  }

  @Delete('updates/:id')
  @ApiOperation({ summary: 'Delete an update and its replies (author or account admin)' })
  deleteUpdate(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.items.deleteUpdate(auth, id);
  }
}
