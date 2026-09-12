import { describe, expect, it } from 'vitest';
import { validateEnv } from './env';

const minimal = {
  DATABASE_URL: 'postgres://dayflow:dayflow@127.0.0.1:5433/dayflow',
  JWT_SECRET: 'a-sufficiently-long-secret',
};

describe('validateEnv', () => {
  it('applies defaults for everything optional', () => {
    const env = validateEnv(minimal);

    expect(env.NODE_ENV).toBe('development');
    expect(env.PORT).toBe(4000);
    expect(env.ACCESS_TOKEN_TTL_SEC).toBe(900);
    expect(env.REFRESH_TOKEN_TTL_DAYS).toBe(30);
    expect(env.CORS_ORIGINS).toBe('');
    expect(env.MAIL_FROM).toContain('Dayflow');
  });

  it('coerces numeric strings from the process environment', () => {
    const env = validateEnv({ ...minimal, PORT: '8080', ACCESS_TOKEN_TTL_SEC: '60' });

    expect(env.PORT).toBe(8080);
    expect(env.ACCESS_TOKEN_TTL_SEC).toBe(60);
  });

  it('treats OTP_DEV_ECHO as a boolean flag', () => {
    expect(validateEnv({ ...minimal, OTP_DEV_ECHO: 'true' }).OTP_DEV_ECHO).toBe(true);
    expect(validateEnv({ ...minimal, OTP_DEV_ECHO: 'false' }).OTP_DEV_ECHO).toBe(false);
    expect(validateEnv({ ...minimal, OTP_DEV_ECHO: 'yes' }).OTP_DEV_ECHO).toBe(false);
    expect(validateEnv(minimal).OTP_DEV_ECHO).toBe(false);
  });

  it('rejects a missing database url', () => {
    expect(() => validateEnv({ JWT_SECRET: minimal.JWT_SECRET })).toThrow(/DATABASE_URL/);
  });

  it('accepts an optional hosted database url', () => {
    const hosted = 'postgresql://user:pass@ep-example-pooler.us-east-1.aws.neon.tech/db?sslmode=require';

    expect(validateEnv(minimal).DB_LIVE_URL).toBeUndefined();
    expect(validateEnv({ ...minimal, DB_LIVE_URL: hosted }).DB_LIVE_URL).toBe(hosted);
  });

  it('rejects a jwt secret that is too short to be safe', () => {
    expect(() => validateEnv({ ...minimal, JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/);
  });

  it('rejects an unknown NODE_ENV', () => {
    expect(() => validateEnv({ ...minimal, NODE_ENV: 'staging' })).toThrow(/NODE_ENV/);
  });

  it('rejects a non-positive port', () => {
    expect(() => validateEnv({ ...minimal, PORT: '0' })).toThrow(/PORT/);
  });

  it('reports every problem at once', () => {
    expect(() => validateEnv({})).toThrow(/DATABASE_URL[\s\S]*JWT_SECRET/);
  });

  it('normalizes PUBLIC_BASE_URL and rejects non-urls', () => {
    expect(validateEnv({ ...minimal, PUBLIC_BASE_URL: 'https://api.dayflow.app/' }).PUBLIC_BASE_URL).toBe(
      'https://api.dayflow.app',
    );
    expect(() => validateEnv({ ...minimal, PUBLIC_BASE_URL: 'not a url' })).toThrow(/PUBLIC_BASE_URL/);
  });

  describe('production hardening', () => {
    const production = {
      ...minimal,
      NODE_ENV: 'production',
      JWT_SECRET: 'a-32char-or-longer-production-secret!',
      RESEND_API_KEY: 're_123',
    };

    it('accepts a fully configured production environment', () => {
      expect(validateEnv(production).NODE_ENV).toBe('production');
    });

    it('requires RESEND_API_KEY so email never silently no-ops', () => {
      expect(() => validateEnv({ ...production, RESEND_API_KEY: undefined })).toThrow(/RESEND_API_KEY/);
    });

    it('requires a 32+ char JWT secret', () => {
      expect(() => validateEnv({ ...production, JWT_SECRET: 'only-twenty-chars-xx' })).toThrow(/JWT_SECRET/);
    });

    it('does not impose production requirements on development', () => {
      expect(() => validateEnv(minimal)).not.toThrow();
    });
  });
});
