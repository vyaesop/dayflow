import { z } from 'zod';

const envSchema = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(4000),
    DATABASE_URL: z.string().min(1),
    // Hosted database (e.g. Neon). Takes precedence over DATABASE_URL when set.
    DB_LIVE_URL: z.string().optional(),
    DIRECT_DATABASE_URL: z.string().optional(),
    JWT_SECRET: z.string().min(16),
    ACCESS_TOKEN_TTL_SEC: z.coerce.number().int().positive().default(900),
    REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
    OTP_DEV_ECHO: z
      .string()
      .optional()
      .transform((v) => v === 'true'),
    RESEND_API_KEY: z.string().optional(),
    MAIL_FROM: z.string().default('Dayflow <no-reply@dayflow.app>'),
    GOOGLE_CLIENT_ID: z.string().optional(),
    CORS_ORIGINS: z.string().default(''),
    /** Where uploaded files live. Required on read-only checkouts (serverless → /tmp/uploads). */
    UPLOAD_DIR: z.string().optional(),
    /** Public https origin of this API, used to build clickable links in emails (invites). */
    PUBLIC_BASE_URL: z
      .string()
      .url()
      .optional()
      .transform((v) => v?.replace(/\/+$/, '')),
  })
  .superRefine((env, ctx) => {
    if (env.NODE_ENV !== 'production') return;
    // Production must fail at boot rather than silently degrade.
    if (!env.RESEND_API_KEY) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['RESEND_API_KEY'],
        message: 'required in production — without it OTP and invite emails are never delivered',
      });
    }
    if (env.JWT_SECRET.length < 32) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['JWT_SECRET'],
        message: 'must be at least 32 characters in production',
      });
    }
  });

export type Env = z.infer<typeof envSchema>;

export function validateEnv(config: Record<string, unknown>): Env {
  const result = envSchema.safeParse(config);
  if (!result.success) {
    const issues = result.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('\n  ');
    throw new Error(`Invalid environment configuration:\n  ${issues}`);
  }
  return result.data;
}
