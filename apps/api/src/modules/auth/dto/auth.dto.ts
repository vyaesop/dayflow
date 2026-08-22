import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsIn, IsNotEmpty, IsOptional, IsString, IsUUID, Length, MaxLength, MinLength } from 'class-validator';

export class RequestOtpDto {
  @ApiProperty({ example: 'alex@acme.com' })
  @IsEmail()
  email!: string;

  @ApiProperty({ enum: ['signup', 'login'] })
  @IsIn(['signup', 'login'])
  purpose!: 'signup' | 'login';
}

export class VerifyOtpDto {
  @ApiProperty({ example: 'alex@acme.com' })
  @IsEmail()
  email!: string;

  @ApiProperty({ example: '421822', minLength: 6, maxLength: 6 })
  @IsString()
  @Length(6, 6)
  code!: string;
}

export class CompleteSignupDto {
  @ApiProperty({ description: 'Token returned by otp/verify for a new user' })
  @IsString()
  @IsNotEmpty()
  signupToken!: string;

  @ApiProperty({ example: 'Alex Smith' })
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  fullName!: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password!: string;

  @ApiPropertyOptional({ enum: ['work', 'personal', 'school'] })
  @IsOptional()
  @IsIn(['work', 'personal', 'school'])
  useFor?: 'work' | 'personal' | 'school';

  @ApiPropertyOptional({ example: 'more_workflows' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  manageCategory?: string;

  @ApiPropertyOptional({ example: 'business_operations' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  workCategory?: string;
}

export class SelectAccountDto {
  @ApiProperty({ description: 'Token returned by otp/verify for an existing user' })
  @IsString()
  @IsNotEmpty()
  selectToken!: string;

  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  accountId!: string;
}

export class PasswordLoginDto {
  @ApiProperty({ example: 'alex@acme.com' })
  @IsEmail()
  email!: string;

  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  password!: string;
}

export class GoogleLoginDto {
  @ApiProperty({ description: 'Google ID token from the native Google Sign-In SDK' })
  @IsString()
  @IsNotEmpty()
  idToken!: string;
}

export class RefreshDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}

export class SwitchAccountDto {
  @ApiProperty({ format: 'uuid' })
  @IsUUID()
  accountId!: string;
}

export class ChangePasswordDto {
  @ApiProperty()
  @IsString()
  @IsNotEmpty()
  currentPassword!: string;

  @ApiProperty({ minLength: 8 })
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  newPassword!: string;
}
