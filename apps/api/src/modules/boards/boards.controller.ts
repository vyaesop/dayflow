import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Res,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { BoardExportService } from './board-export.service';
import { BoardsService } from './boards.service';
import { BoardWritesService } from './board-writes.service';
import { templateGallery } from './templates.catalog';
import {
  CreateBoardDto,
  CreateColumnDto,
  CreateGroupDto,
  CreateItemDto,
  CreateWorkspaceDto,
  MoveGroupDto,
  MoveItemDto,
  RenameItemDto,
  SetCellValueDto,
  UpdateBoardDto,
  UpdateColumnDto,
  UpdateGroupDto,
} from './dto/boards.dto';

@ApiTags('boards')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class BoardsController {
  constructor(
    private readonly boards: BoardsService,
    private readonly writes: BoardWritesService,
    private readonly exporter: BoardExportService,
  ) {}

  // --------------------------------------------------------------------- read

  @Get('workspaces')
  @ApiOperation({ summary: 'Workspaces with their boards' })
  listWorkspaces(@CurrentAuth() auth: AuthContext) {
    return this.boards.listWorkspaces(auth);
  }

  @Get('templates')
  @ApiOperation({ summary: 'Board template gallery' })
  listTemplates() {
    return templateGallery();
  }

  @Get('boards/:id')
  @ApiOperation({ summary: 'Full board payload: columns, groups, items, values, members' })
  getBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.boards.getBoard(auth, id);
  }

  @Get('boards/:id/export.csv')
  @Header('Content-Type', 'text/csv; charset=utf-8')
  @ApiOperation({ summary: 'Export the board as CSV' })
  async exportCsv(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Res() res: Response,
  ) {
    const { fileName, csv } = await this.exporter.toCsv(auth, id);
    res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
    res.send(csv);
  }

  @Post('boards/:id/visit')
  @ApiOperation({ summary: 'Record a board visit (drives Recently Visited)' })
  async visit(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    await this.boards.visit(auth, id);
    return { ok: true };
  }

  @Post('boards/:id/favorite')
  @ApiOperation({ summary: 'Toggle board favorite for the current user' })
  toggleFavorite(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.boards.toggleFavorite(auth, id);
  }

  // --------------------------------------------------------- workspaces/boards

  @Post('workspaces')
  @ApiOperation({ summary: 'Create a workspace' })
  createWorkspace(@CurrentAuth() auth: AuthContext, @Body() dto: CreateWorkspaceDto) {
    return this.writes.createWorkspace(auth, dto.name);
  }

  @Post('boards')
  @ApiOperation({ summary: 'Create a board, optionally from a template' })
  createBoard(@CurrentAuth() auth: AuthContext, @Body() dto: CreateBoardDto) {
    return this.writes.createBoard(auth, dto);
  }

  @Patch('boards/:id')
  @ApiOperation({ summary: 'Rename a board or change its description' })
  updateBoard(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateBoardDto,
  ) {
    return this.writes.updateBoard(auth, id, dto);
  }

  @Delete('boards/:id')
  @ApiOperation({ summary: 'Archive a board' })
  archiveBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.archiveBoard(auth, id);
  }

  // ------------------------------------------------------------------- groups

  @Post('boards/:id/groups')
  @ApiOperation({ summary: 'Add a group to a board' })
  createGroup(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) boardId: string,
    @Body() dto: CreateGroupDto,
  ) {
    return this.writes.createGroup(auth, boardId, dto);
  }

  @Patch('groups/:id')
  @ApiOperation({ summary: 'Rename, recolor or collapse a group' })
  updateGroup(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateGroupDto,
  ) {
    return this.writes.updateGroup(auth, id, dto);
  }

  @Post('groups/:id/move')
  @ApiOperation({ summary: 'Reorder a group within its board' })
  moveGroup(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MoveGroupDto,
  ) {
    return this.writes.moveGroup(auth, id, dto.afterGroupId ?? null);
  }

  @Delete('groups/:id')
  @ApiOperation({ summary: 'Delete a group and its items' })
  deleteGroup(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.deleteGroup(auth, id);
  }

  // -------------------------------------------------------------------- items

  @Post('boards/:id/items')
  @ApiOperation({ summary: 'Create an item in a group' })
  createItem(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) boardId: string,
    @Body() dto: CreateItemDto,
  ) {
    return this.writes.createItem(auth, boardId, dto);
  }

  @Patch('items/:id')
  @ApiOperation({ summary: 'Rename an item' })
  renameItem(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: RenameItemDto,
  ) {
    return this.writes.renameItem(auth, id, dto.name);
  }

  @Post('items/:id/move')
  @ApiOperation({ summary: 'Move an item within or between groups' })
  moveItem(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: MoveItemDto,
  ) {
    return this.writes.moveItem(auth, id, dto);
  }

  @Post('items/:id/duplicate')
  @ApiOperation({ summary: 'Duplicate an item with its cell values' })
  duplicateItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.duplicateItem(auth, id);
  }

  @Delete('items/:id')
  @ApiOperation({ summary: 'Archive an item' })
  archiveItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.archiveItem(auth, id);
  }

  @Put('items/:itemId/columns/:columnId')
  @ApiOperation({ summary: 'Set or clear one cell value' })
  setCellValue(
    @CurrentAuth() auth: AuthContext,
    @Param('itemId', ParseUUIDPipe) itemId: string,
    @Param('columnId', ParseUUIDPipe) columnId: string,
    @Body() dto: SetCellValueDto,
  ) {
    return this.writes.setCellValue(auth, itemId, columnId, dto.value ?? null);
  }

  // ------------------------------------------------------------------ columns

  @Post('boards/:id/columns')
  @ApiOperation({ summary: 'Add a column to a board' })
  createColumn(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) boardId: string,
    @Body() dto: CreateColumnDto,
  ) {
    return this.writes.createColumn(auth, boardId, dto);
  }

  @Patch('columns/:id')
  @ApiOperation({ summary: 'Rename a column or change its settings/width' })
  updateColumn(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateColumnDto,
  ) {
    return this.writes.updateColumn(auth, id, dto);
  }

  @Delete('columns/:id')
  @ApiOperation({ summary: 'Delete a column and its values' })
  deleteColumn(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.deleteColumn(auth, id);
  }
}
