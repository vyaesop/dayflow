import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  MinLength,
  ValidateIf,
} from 'class-validator';
import { ALL_COLUMN_TYPES } from '../column-values';

const GROUP_COLORS = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo'];
const BOARD_TYPES = ['main', 'shareable', 'private'] as const;
const COLUMN_SCOPES = ['items', 'subitems'] as const;
const DUPLICATE_MODES = ['structure', 'items', 'items_and_updates'] as const;
const BATCH_ACTIONS = ['archive', 'trash', 'restore', 'duplicate', 'move', 'set_cell', 'delete_permanent'] as const;

export class CreateWorkspaceDto {
  @ApiProperty({ example: 'Marketing' })
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;
}

export class CreateBoardDto {
  @ApiProperty({ example: 'Campaign tracker' })
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  name!: string;

  @ApiPropertyOptional({ description: 'Defaults to the oldest workspace in the account' })
  @IsOptional()
  @IsUUID()
  workspaceId?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiPropertyOptional({ enum: BOARD_TYPES })
  @IsOptional()
  @IsIn(BOARD_TYPES)
  type?: (typeof BOARD_TYPES)[number];

  @ApiPropertyOptional({ description: 'Template key from GET /v1/templates (built-in or custom_…)' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  template?: string;
}

export class UpdateBoardDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @ApiPropertyOptional({
    enum: BOARD_TYPES,
    description: 'Changing visibility takes a board owner or an account admin',
  })
  @IsOptional()
  @IsIn(BOARD_TYPES)
  type?: (typeof BOARD_TYPES)[number];
}

export class DuplicateBoardDto {
  @ApiPropertyOptional({ description: 'Defaults to "<name> (copy)"' })
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  name?: string;

  @ApiProperty({ enum: DUPLICATE_MODES })
  @IsIn(DUPLICATE_MODES)
  mode!: (typeof DUPLICATE_MODES)[number];

  @ApiPropertyOptional({ description: 'Defaults to the source board\'s workspace' })
  @IsOptional()
  @IsUUID()
  workspaceId?: string;
}

export class SaveAsTemplateDto {
  @ApiProperty({ example: 'Sprint board' })
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @ApiProperty({ description: 'Snapshot the current items as sample rows' })
  @IsBoolean()
  includeItems!: boolean;
}

const BOARD_MEMBER_ROLES = ['owner', 'member', 'viewer'] as const;

export class AddBoardMemberDto {
  @ApiProperty({ description: 'An active member of this account' })
  @IsUUID()
  userId!: string;

  @ApiPropertyOptional({ enum: BOARD_MEMBER_ROLES, default: 'member' })
  @IsOptional()
  @IsIn(BOARD_MEMBER_ROLES)
  role?: (typeof BOARD_MEMBER_ROLES)[number];
}

export class ChangeBoardMemberRoleDto {
  @ApiProperty({ enum: BOARD_MEMBER_ROLES })
  @IsIn(BOARD_MEMBER_ROLES)
  role!: (typeof BOARD_MEMBER_ROLES)[number];
}

export class CreateGroupDto {
  @ApiProperty({ example: 'In progress' })
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title!: string;

  @ApiPropertyOptional({ enum: GROUP_COLORS })
  @IsOptional()
  @IsIn(GROUP_COLORS)
  color?: string;
}

export class UpdateGroupDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title?: string;

  @ApiPropertyOptional({ enum: GROUP_COLORS })
  @IsOptional()
  @IsIn(GROUP_COLORS)
  color?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  collapsed?: boolean;
}

export class MoveGroupDto {
  @ApiPropertyOptional({ nullable: true, description: 'Place after this group; null moves it first' })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterGroupId?: string | null;
}

export class CreateItemDto {
  @ApiProperty()
  @IsUUID()
  groupId!: string;

  @ApiProperty({ example: 'Draft the launch plan' })
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  name!: string;

  @ApiPropertyOptional({
    nullable: true,
    description: 'Place after this item; null puts it first; omit to append',
  })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterItemId?: string | null;
}

export class CreateSubitemDto {
  @ApiProperty({ example: 'Write the copy' })
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  name!: string;

  @ApiPropertyOptional({ nullable: true, description: 'Place after this sibling; null puts it first; omit to append' })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterItemId?: string | null;
}

export class RenameItemDto {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  name!: string;
}

export class MoveItemDto {
  @ApiPropertyOptional({ description: 'Target group; omit to reorder within the current group (subitems: always omit)' })
  @IsOptional()
  @IsUUID()
  groupId?: string;

  @ApiPropertyOptional({ nullable: true, description: 'Place after this item; null moves it first' })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterItemId?: string | null;
}

export class MoveToBoardDto {
  @ApiProperty({ description: 'Destination board' })
  @IsUUID()
  boardId!: string;

  @ApiProperty({ description: 'Group on the destination board' })
  @IsUUID()
  groupId!: string;
}

export class SetCellValueDto {
  @ApiProperty({
    nullable: true,
    description:
      'Shape depends on the column type: {labelId} for status, {userIds:[]} for people, ' +
      '{date,time?} for date, {text} for text/long_text, {number} for number, {checked} for checkbox, ' +
      '{email,label?}, {phone,countryCode?}, {rating}, {fileIds:[]}, {url,label?}, {address,lat?,lng?}, ' +
      '{from,to} for timeline, {optionIds:[]} for dropdown/tags. Send null to clear the cell.',
    example: { labelId: 'done' },
  })
  @IsOptional()
  value?: unknown;
}

export class BatchItemsDto {
  @ApiProperty({ type: [String], description: 'Items on this board (top-level or subitems), 1..200' })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(200)
  @IsUUID('4', { each: true })
  itemIds!: string[];

  @ApiProperty({ enum: BATCH_ACTIONS })
  @IsIn(BATCH_ACTIONS)
  action!: (typeof BATCH_ACTIONS)[number];

  @ApiPropertyOptional({ description: 'move: target group' })
  @IsOptional()
  @IsUUID()
  groupId?: string;

  @ApiPropertyOptional({ description: 'set_cell: column to write' })
  @IsOptional()
  @IsUUID()
  columnId?: string;

  @ApiPropertyOptional({ nullable: true, description: 'set_cell: value (null clears)' })
  @IsOptional()
  value?: unknown;
}

export class CreateColumnDto {
  @ApiProperty({ enum: ALL_COLUMN_TYPES })
  @IsIn(ALL_COLUMN_TYPES)
  type!: string;

  @ApiProperty({ example: 'Owner' })
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title!: string;

  @ApiPropertyOptional({ description: 'Type-specific settings; sensible defaults are applied when omitted' })
  @IsOptional()
  @IsObject()
  settings?: Record<string, unknown>;

  @ApiPropertyOptional({ enum: COLUMN_SCOPES, default: 'items' })
  @IsOptional()
  @IsIn(COLUMN_SCOPES)
  scope?: (typeof COLUMN_SCOPES)[number];
}

export class UpdateColumnDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  settings?: Record<string, unknown>;

  @ApiPropertyOptional({ minimum: 60 })
  @IsOptional()
  @IsInt()
  @Min(60)
  width?: number;
}

export class MoveColumnDto {
  @ApiPropertyOptional({ nullable: true, description: 'Place after this column (same scope); null moves it first' })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterColumnId?: string | null;
}
