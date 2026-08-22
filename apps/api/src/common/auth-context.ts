export interface AuthContext {
  userId: string;
  accountId: string;
  role: 'admin' | 'member' | 'viewer' | 'guest';
}

export interface AccessTokenPayload {
  sub: string;
  acc: string;
  role: AuthContext['role'];
  typ: 'access';
}

export interface SignupTokenPayload {
  email: string;
  typ: 'signup';
}

export interface SelectTokenPayload {
  sub: string;
  typ: 'select';
}
