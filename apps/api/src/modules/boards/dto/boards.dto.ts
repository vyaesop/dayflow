import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
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

const COLUMN_TYPES = [
  'status',
  'people',
  'date',
  'text',
  'number',
  'tags',
  'dropdown',
  'checkbox',
  'timeline',
  'vote',
  'location',
  'link',
];

const GROUP_COLORS = ['blue', 'purple', 'green', 'pink', 'amber', 'red', 'teal', 'indigo'];

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

  @ApiPropertyOptional({ enum: ['main', 'shareable', 'private'] })
  @IsOptional()
  @IsIn(['main', 'shareable', 'private'])
  type?: 'main' | 'shareable' | 'private';

  @ApiPropertyOptional({ description: 'Template key from GET /v1/templates' })
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

export class RenameItemDto {
  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  name!: string;
}

export class MoveItemDto {
  @ApiPropertyOptional({ description: 'Target group; omit to reorder within the current group' })
  @IsOptional()
  @IsUUID()
  groupId?: string;

  @ApiPropertyOptional({ nullable: true, description: 'Place after this item; null moves it first' })
  @IsOptional()
  @ValidateIf((_, value) => value !== null)
  @IsUUID()
  afterItemId?: string | null;
}

export class SetCellValueDto {
  @ApiProperty({
    nullable: true,
    description:
      'Shape depends on the column type: {labelId} for status, {userIds:[]} for people, ' +
      '{date,time?} for date, {text} for text, {number} for number, {checked} for checkbox. ' +
      'Send null to clear the cell.',
    example: { labelId: 'done' },
  })
  @IsOptional()
  value?: unknown;
}

export class CreateColumnDto {
  @ApiProperty({ enum: COLUMN_TYPES })
  @IsIn(COLUMN_TYPES)
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
