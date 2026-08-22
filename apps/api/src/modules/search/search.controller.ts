import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { SearchService } from './search.service';

@ApiTags('search')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller()
export class SearchController {
  constructor(private readonly search: SearchService) {}

  @Get('search')
  @ApiOperation({ summary: 'Search boards and items by name (min 2 characters)' })
  @ApiQuery({ name: 'q', required: true, example: 'launch' })
  run(@CurrentAuth() auth: AuthContext, @Query('q') q = '') {
    return this.search.search(auth, q);
  }
}
