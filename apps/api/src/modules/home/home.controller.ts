import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { HomeService } from './home.service';

@ApiTags('home')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('home')
export class HomeController {
  constructor(private readonly home: HomeService) {}

  @Get('overview')
  @ApiOperation({ summary: 'Home tab payload: greeting, setup progress, favorites, recently visited' })
  overview(@CurrentAuth() auth: AuthContext) {
    return this.home.overview(auth);
  }
}
