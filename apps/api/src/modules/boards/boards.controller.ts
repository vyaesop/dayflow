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
  Query,
  Res,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { BoardExportService } from './board-export.service';
import { BoardMembersService } from './board-members.service';
import { BoardsService } from './boards.service';
import { BoardWritesService } from './board-writes.service';
import { ItemWritesService } from './item-writes.service';
import {
  AddBoardMemberDto,
  BatchItemsDto,
  ChangeBoardMemberRoleDto,
  CreateBoardDto,
  CreateColumnDto,
  CreateGroupDto,
  CreateItemDto,
  CreateSubitemDto,
  CreateWorkspaceDto,
  DuplicateBoardDto,
  MoveColumnDto,
  MoveGroupDto,
  MoveItemDto,
  MoveToBoardDto,
  RenameItemDto,
  SaveAsTemplateDto,
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
    private readonly itemWrites: ItemWritesService,
    private readonly exporter: BoardExportService,
    private readonly members: BoardMembersService,
  ) {}

  // --------------------------------------------------------------------- read

  @Get('workspaces')
  @ApiOperation({ summary: 'Workspaces with their boards' })
  listWorkspaces(@CurrentAuth() auth: AuthContext) {
    return this.boards.listWorkspaces(auth);
  }

  @Get('templates')
  @ApiOperation({ summary: 'Board template gallery: built-in templates followed by this account\'s own' })
  listTemplates(@CurrentAuth() auth: AuthContext) {
    return this.writes.listTemplates(auth);
  }

  @Delete('templates/:id')
  @ApiOperation({ summary: 'Delete an account template (author or admin)' })
  deleteTemplate(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.deleteTemplate(auth, id);
  }

  @Get('boards/:id')
  @ApiOperation({ summary: 'Full board payload: columns, groups, items (with subitems), values, members, views' })
  getBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.boards.getBoard(auth, id);
  }

  @Get('boards/:id/export.csv')
  @Header('Content-Type', 'text/csv; charset=utf-8')
  @ApiOperation({ summary: 'Export the board as CSV, optionally through a saved view\'s filters/sort/columns' })
  @ApiQuery({ name: 'viewId', required: false })
  async exportCsv(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Res() res: Response,
    @Query('viewId', new ParseUUIDPipe({ optional: true })) viewId?: string,
  ) {
    const { fileName, csv } = await this.exporter.toCsv(auth, id, viewId);
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
  @ApiOperation({ summary: 'Rename a board, change its description or its type' })
  updateBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateBoardDto) {
    return this.writes.updateBoard(auth, id, dto);
  }

  @Post('boards/:id/archive')
  @ApiOperation({ summary: 'Archive a board (kept indefinitely, restorable)' })
  archiveBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.archiveBoard(auth, id);
  }

  @Delete('boards/:id')
  @ApiOperation({ summary: 'Move a board to the trash (purged after 30 days unless restored)' })
  trashBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.trashBoard(auth, id);
  }

  @Post('boards/:id/restore')
  @ApiOperation({ summary: 'Restore a board from the archive or the trash' })
  restoreBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.restoreBoard(auth, id);
  }

  @Delete('boards/:id/permanent')
  @ApiOperation({ summary: 'Permanently delete a trashed board (board owners / account admins)' })
  deleteBoardPermanently(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.deleteBoardPermanently(auth, id);
  }

  @Post('boards/:id/duplicate')
  @ApiOperation({ summary: 'Duplicate a board: structure, items and subitems, or everything incl. updates' })
  duplicateBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: DuplicateBoardDto) {
    return this.writes.duplicateBoard(auth, id, dto);
  }

  @Post('boards/:id/save-as-template')
  @ApiOperation({ summary: 'Save the board\'s structure (and optionally items) as an account template' })
  saveAsTemplate(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SaveAsTemplateDto) {
    return this.writes.saveAsTemplate(auth, id, dto);
  }

  // ------------------------------------------------------------ board members

  @Get('boards/:id/members')
  @ApiOperation({ summary: 'Board members with roles, plus whether the caller can manage them' })
  listBoardMembers(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.members.list(auth, id);
  }

  @Post('boards/:id/members')
  @ApiOperation({ summary: 'Add an account member to a board (board owners and admins)' })
  addBoardMember(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: AddBoardMemberDto) {
    return this.members.add(auth, id, dto.userId, dto.role ?? 'member');
  }

  @Patch('boards/:id/members/:userId')
  @ApiOperation({ summary: "Change a board member's role (board owners and admins)" })
  changeBoardMemberRole(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('userId', ParseUUIDPipe) userId: string,
    @Body() dto: ChangeBoardMemberRoleDto,
  ) {
    return this.members.changeRole(auth, id, userId, dto.role);
  }

  @Delete('boards/:id/members/:userId')
  @ApiOperation({ summary: 'Remove someone from a board (owners/admins; anyone may remove themselves)' })
  removeBoardMember(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('userId', ParseUUIDPipe) userId: string,
  ) {
    return this.members.remove(auth, id, userId);
  }

  // ------------------------------------------------------------------- groups

  @Post('boards/:id/groups')
  @ApiOperation({ summary: 'Add a group to a board' })
  createGroup(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) boardId: string, @Body() dto: CreateGroupDto) {
    return this.writes.createGroup(auth, boardId, dto);
  }

  @Patch('groups/:id')
  @ApiOperation({ summary: 'Rename, recolor or collapse a group' })
  updateGroup(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateGroupDto) {
    return this.writes.updateGroup(auth, id, dto);
  }

  @Post('groups/:id/move')
  @ApiOperation({ summary: 'Reorder a group within its board' })
  moveGroup(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: MoveGroupDto) {
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
  createItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) boardId: string, @Body() dto: CreateItemDto) {
    return this.itemWrites.createItem(auth, boardId, dto);
  }

  @Post('boards/:id/items/batch')
  @ApiOperation({ summary: 'Apply one action to many items at once (archive, trash, restore, duplicate, move, set_cell, delete_permanent)' })
  batch(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) boardId: string, @Body() dto: BatchItemsDto) {
    return this.itemWrites.batch(auth, boardId, dto);
  }

  @Post('items/:id/subitems')
  @ApiOperation({ summary: 'Add a subitem under an item (creates the board\'s subitem columns on first use)' })
  createSubitem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateSubitemDto) {
    return this.itemWrites.createSubitem(auth, id, dto);
  }

  @Patch('items/:id')
  @ApiOperation({ summary: 'Rename an item' })
  renameItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RenameItemDto) {
    return this.itemWrites.renameItem(auth, id, dto.name);
  }

  @Post('items/:id/move')
  @ApiOperation({ summary: 'Move an item within or between groups (subitems reorder among siblings)' })
  moveItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: MoveItemDto) {
    return this.itemWrites.moveItem(auth, id, dto);
  }

  @Get('items/:id/move-preview')
  @ApiOperation({ summary: 'Preview how an item\'s columns map onto another board before moving it' })
  @ApiQuery({ name: 'boardId', required: true })
  movePreview(
    @CurrentAuth() auth: AuthContext,
    @Param('id', ParseUUIDPipe) id: string,
    @Query('boardId', ParseUUIDPipe) boardId: string,
  ) {
    return this.itemWrites.movePreview(auth, id, boardId);
  }

  @Post('items/:id/move-to-board')
  @ApiOperation({ summary: 'Move an item (with subitems, updates and files) to another board' })
  moveToBoard(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: MoveToBoardDto) {
    return this.itemWrites.moveToBoard(auth, id, dto);
  }

  @Post('items/:id/duplicate')
  @ApiOperation({ summary: 'Duplicate an item with its cell values and subitems' })
  duplicateItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.itemWrites.duplicateItem(auth, id);
  }

  @Post('items/:id/archive')
  @ApiOperation({ summary: 'Archive an item (kept indefinitely, restorable)' })
  archiveItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.itemWrites.archiveItem(auth, id);
  }

  @Delete('items/:id')
  @ApiOperation({ summary: 'Move an item to the trash (purged after 30 days unless restored)' })
  trashItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.itemWrites.trashItem(auth, id);
  }

  @Post('items/:id/restore')
  @ApiOperation({ summary: 'Restore an item from the archive or the trash' })
  restoreItem(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.itemWrites.restoreItem(auth, id);
  }

  @Delete('items/:id/permanent')
  @ApiOperation({ summary: 'Permanently delete a trashed item (board owners / account admins)' })
  deleteItemPermanently(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.itemWrites.deleteItemPermanently(auth, id);
  }

  @Put('items/:itemId/columns/:columnId')
  @ApiOperation({ summary: 'Set or clear one cell value' })
  setCellValue(
    @CurrentAuth() auth: AuthContext,
    @Param('itemId', ParseUUIDPipe) itemId: string,
    @Param('columnId', ParseUUIDPipe) columnId: string,
    @Body() dto: SetCellValueDto,
  ) {
    return this.itemWrites.setCellValue(auth, itemId, columnId, dto.value ?? null);
  }

  // ------------------------------------------------------------------ columns

  @Post('boards/:id/columns')
  @ApiOperation({ summary: 'Add a column to a board (item or subitem scope)' })
  createColumn(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) boardId: string, @Body() dto: CreateColumnDto) {
    return this.writes.createColumn(auth, boardId, dto);
  }

  @Patch('columns/:id')
  @ApiOperation({ summary: 'Rename a column or change its settings/width' })
  updateColumn(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateColumnDto) {
    return this.writes.updateColumn(auth, id, dto);
  }

  @Post('columns/:id/move')
  @ApiOperation({ summary: 'Reorder a column within its scope' })
  moveColumn(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string, @Body() dto: MoveColumnDto) {
    return this.writes.moveColumn(auth, id, dto.afterColumnId ?? null);
  }

  @Delete('columns/:id')
  @ApiOperation({ summary: 'Delete a column and its values' })
  deleteColumn(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.writes.deleteColumn(auth, id);
  }
}
