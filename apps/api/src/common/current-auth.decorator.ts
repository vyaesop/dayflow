import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthContext } from './auth-context';
import type { AuthedRequest } from './jwt-auth.guard';

export const CurrentAuth = createParamDecorator((_data: unknown, ctx: ExecutionContext): AuthContext => {
  const request = ctx.switchToHttp().getRequest<AuthedRequest>();
  return request.auth;
});
