import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { IsEmail, IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { MembersService } from './members.service';

const ASSIGNABLE_ROLES = ['admin', 'member', 'viewer'] as const;

export class InviteMemberDto {
  @ApiProperty({ example: 'teammate@acme.com' })
  @IsEmail()
  email!: string;

  @ApiPropertyOptional({ enum: ASSIGNABLE_ROLES, default: 'member' })
  @IsOptional()
  @IsIn(ASSIGNABLE_ROLES)
  role?: (typeof ASSIGNABLE_ROLES)[number];
}

export class AcceptInviteDto {
  @ApiProperty({ description: 'Token from the invitation link' })
  @IsString()
  @MinLength(10)
  @MaxLength(200)
  token!: string;
}

export class ChangeRoleDto {
  @ApiProperty({ enum: ASSIGNABLE_ROLES })
  @IsIn(ASSIGNABLE_ROLES)
  role!: (typeof ASSIGNABLE_ROLES)[number];
}

@ApiTags('members')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class MembersController {
  constructor(private readonly members: MembersService) {}

  @Get('members')
  @ApiOperation({ summary: 'Account members, plus pending invitations for admins' })
  list(@CurrentAuth() auth: AuthContext) {
    return this.members.list(auth);
  }

  @Post('invitations')
  @ApiOperation({ summary: 'Invite an email to the account (admins only)' })
  invite(@CurrentAuth() auth: AuthContext, @Body() dto: InviteMemberDto) {
    return this.members.invite(auth, dto.email, dto.role ?? 'member');
  }

  @Post('invitations/accept')
  @ApiOperation({ summary: 'Accept an invitation as the signed-in user' })
  accept(@CurrentAuth() auth: AuthContext, @Body() dto: AcceptInviteDto) {
    return this.members.accept(auth, dto.token);
  }

  @Delete('invitations/:id')
  @ApiOperation({ summary: 'Revoke a pending invitation (admins only)' })
  revoke(@CurrentAuth() auth: AuthContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.members.revokeInvite(auth, id);
  }

  @Patch('members/:userId')
  @ApiOperation({ summary: "Change a member's role (admins only)" })
  changeRole(
    @CurrentAuth() auth: AuthContext,
    @Param('userId', ParseUUIDPipe) userId: string,
    @Body() dto: ChangeRoleDto,
  ) {
    return this.members.changeRole(auth, userId, dto.role);
  }

  @Delete('members/:userId')
  @ApiOperation({ summary: 'Remove a member from the account (admins only)' })
  remove(@CurrentAuth() auth: AuthContext, @Param('userId', ParseUUIDPipe) userId: string) {
    return this.members.remove(auth, userId);
  }
}
