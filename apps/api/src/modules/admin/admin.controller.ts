import { Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { AdminService } from './admin.service';

@ApiTags('admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('admin')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('account/deletion')
  @ApiOperation({ summary: 'Whether (and when) this account is scheduled for deletion' })
  deletionStatus(@CurrentAuth() auth: AuthContext) {
    return this.admin.deletionStatus(auth);
  }

  @Post('account/deletion')
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @ApiOperation({ summary: 'Schedule this account for deletion after a 30-day grace period (admins only)' })
  scheduleDeletion(@CurrentAuth() auth: AuthContext) {
    return this.admin.scheduleDeletion(auth);
  }

  @Delete('account/deletion')
  @ApiOperation({ summary: 'Cancel a scheduled account deletion (admins only)' })
  cancelDeletion(@CurrentAuth() auth: AuthContext) {
    return this.admin.cancelDeletion(auth);
  }
}
