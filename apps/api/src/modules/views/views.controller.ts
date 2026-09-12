import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsIn, IsObject, IsOptional, IsString, IsUUID, MaxLength, MinLength, ValidateIf } from 'class-validator';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { ViewsService, type ViewType } from './views.service';

const VIEW_TYPES = ['table', 'list', 'kanban', 'calendar', 'dashboard'] as const;

export class CreateViewDto {
  @ApiProperty({ enum: VIEW_TYPES })
  @IsIn(VIEW_TYPES)
  type!: ViewType;

  @ApiProperty({ example: 'My open tasks' })
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;

  @ApiPropertyOptional({ description: 'ViewConfig: filters, sort, hiddenColumnIds, columnOrder, conditionalColors, laneColumnId, dateColumnId' })
  @IsOptional()
  @IsObject()
  config?: Record<string, unknown>;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}

export class UpdateViewDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  config?: Record<string, unknown>;

  @ApiPropertyOptional({ description: 'true makes this the default view; false is rejected — pick another default instead' })
  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}

export class MoveViewDto {
  @ApiPropertyOptional({ nullable: true, description: 'Place after this view; null moves it first' })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterViewId?: string | null;
}

@ApiTags('views')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class ViewsController {
  constructor(private readonly views: ViewsService) {}

  @Get('boards/:id/views')
  @ApiOperation({ summary: 'Saved views of a board, in display order' })
  list(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) boardId: string) {
    return this.views.list(auth, boardId);
  }

  @Post('boards/:id/views')
  @ApiOperation({ summary: 'Create a saved view (filters, sort, hidden columns, colors)' })
  create(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) boardId: string, @Body() dto: CreateViewDto) {
    return this.views.create(auth, boardId, dto);
  }

  @Patch('views/:id')
  @ApiOperation({ summary: 'Rename a view, replace its config, or make it the default' })
  update(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateViewDto) {
    return this.views.update(auth, id, dto);
  }

  @Post('views/:id/move')
  @ApiOperation({ summary: 'Reorder a view among its board\'s views' })
  move(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: MoveViewDto) {
    return this.views.move(auth, id, dto.afterViewId ?? null);
  }

  @Post('views/:id/duplicate')
  @ApiOperation({ summary: 'Duplicate a view with its config' })
  duplicate(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.views.duplicate(auth, id);
  }

  @Delete('views/:id')
  @ApiOperation({ summary: 'Delete a view (a board keeps at least one)' })
  remove(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.views.remove(auth, id);
  }
}
