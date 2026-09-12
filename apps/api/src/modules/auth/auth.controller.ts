import { Body, Controller, Headers, HttpCode, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentAuth } from '../../common/current-auth.decorator';
import { JwtAuthGuard } from '../../common/jwt-auth.guard';
import type { AuthContext } from '../../common/auth-context';
import { AuthService } from './auth.service';
import {
  ChangePasswordDto,
  CompleteSignupDto,
  GoogleLoginDto,
  PasswordLoginDto,
  RefreshDto,
  RequestOtpDto,
  SelectAccountDto,
  SwitchAccountDto,
  VerifyOtpDto,
} from './dto/auth.dto';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('otp/request')
  @HttpCode(200)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @ApiOperation({ summary: 'Send a 6-digit verification code to an email address' })
  requestOtp(@Body() dto: RequestOtpDto) {
    return this.auth.requestOtp(dto.email, dto.purpose);
  }

  @Post('otp/verify')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Verify an OTP code; returns a signup token or the account picker payload' })
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOtp(dto.email, dto.code);
  }

  @Post('signup/complete')
  @HttpCode(201)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Create the user + account after OTP verification and the onboarding wizard' })
  completeSignup(@Body() dto: CompleteSignupDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.completeSignup(dto, userAgent);
  }

  @Post('login/select')
  @HttpCode(200)
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @ApiOperation({ summary: 'Choose an account to log in (after OTP verify for an existing user)' })
  selectAccount(@Body() dto: SelectAccountDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.selectAccount(dto.selectToken, dto.accountId, userAgent);
  }

  @Post('login/password')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Log in with email + password' })
  passwordLogin(@Body() dto: PasswordLoginDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.passwordLogin(dto.email, dto.password, userAgent);
  }

  @Post('google')
  @HttpCode(200)
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @ApiOperation({ summary: 'Log in / sign up with a Google ID token' })
  googleLogin(@Body() dto: GoogleLoginDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.googleLogin(dto.idToken, userAgent);
  }

  @Post('refresh')
  @HttpCode(200)
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({ summary: 'Rotate the refresh token and mint a new access token' })
  refresh(@Body() dto: RefreshDto, @Headers('user-agent') userAgent?: string) {
    return this.auth.refresh(dto.refreshToken, userAgent);
  }

  @Post('logout')
  @HttpCode(204)
  @ApiOperation({ summary: 'Revoke a refresh token' })
  async logout(@Body() dto: RefreshDto): Promise<void> {
    await this.auth.logout(dto.refreshToken);
  }

  @Post('switch')
  @HttpCode(200)
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Switch to another account the user belongs to' })
  switchAccount(
    @CurrentAuth() auth: AuthContext,
    @Body() dto: SwitchAccountDto,
    @Headers('user-agent') userAgent?: string,
  ) {
    return this.auth.switchAccount(auth, dto.accountId, userAgent);
  }

  @Post('password/change')
  @HttpCode(204)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @UseGuards(JwtAuthGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Change password (revokes all other sessions)' })
  async changePassword(@CurrentAuth() auth: AuthContext, @Body() dto: ChangePasswordDto): Promise<void> {
    await this.auth.changePassword(auth, dto.currentPassword, dto.newPassword);
  }
}
