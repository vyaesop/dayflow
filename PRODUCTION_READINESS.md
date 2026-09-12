# Dayflow — Remaining Work for Production

Audit date: 2026-08-22. Covers `apps/api` (NestJS/Drizzle, deployed on Vercel serverless + Neon) and `apps/mobile` (Flutter).

---

## Status update — 2026-09-12 (P0 board parity)

The P0 backlog from `MONDAY_FEATURE_GAP.md` shipped: saved views with an
advanced filter builder, sort, hidden/reordered columns, conditional colours and
summary footers; subitems; nine new column types; batch actions; Archive +
30-day Trash with restore; board activity log with 7-day undo; board discussion;
rich-text updates with mention autocomplete, reactions and attachments; move item
to another board; board duplicate; save board as template; guest role; member
deactivate/reactivate. Migrations `0002_p0_board_parity` and
`0003_drop_update_likes` must be applied wherever `0001` is (they are additive
apart from folding `update_likes` into `update_reactions`). Verified with 243 API
unit tests, 220 offline Flutter tests and the 66-test live-API e2e suite. The
remaining production items below (push, OAuth client IDs, object storage,
crash reporting, hosting) are unchanged.

## Status update — 2026-08-22 (same day, code-only pass)

Everything implementable without external accounts/hosting was built and verified
(96 API unit tests, 93 Flutter tests incl. the 42-test live-API e2e suite, plus
manual probes of board access, invites, WS auth, and account deletion):

**Features finished:** invite deep links (`dayflow:///invite/<token>` registered
on Android + iOS, hosted landing page `GET /invite/<token>`, hashed tokens at
rest, pending-invite hand-off through signup) · the complete board-type model,
monday-style (visibility enforcement everywhere; board members with
owner/member/viewer roles; owner-gated member management + type changes; guest
and last-owner rules; privacy picker on create; Board members sheet; change
type; lock badges; board_invite notifications + email; 9 dedicated e2e tests)
· widget Dashboard view (stats, status
battery, items-per-group chart, number totals, upcoming) · email notification
delivery for mentions/assignments/replies respecting the email pref · support
center screen · feedback persisted to a `feedback` table · 30-day
account-deletion grace flow (schedule/cancel UI + purge job) · realtime polling
fallback with visible degraded-mode banner + reconnect-on-resume.

**Security fixed:** Google `verifyIdToken` audience · CORS never reflect-any in
production · Swagger gated off in production · mail throws instead of no-oping
in production (and `RESEND_API_KEY`/32-char `JWT_SECRET` required by the env
schema there) · OTP lockout that survives code re-issue · transactional refresh
rotation (concurrent-refresh race closed) · invite `devLink` production-gated ·
file serving hardened (inline only for image types, nosniff, attachment
otherwise; multer streaming size limits; image-only avatars) · WS auth via first
frame instead of query string · per-route throttles on all auth endpoints ·
migrate.ts refuses to run without an explicit database URL.

**Infra added:** `/healthz` · global exception filter + request logging ·
scheduled cleanup jobs (expired refresh tokens/OTPs/invitations, due account
deletions; long-running hosts only) · GitHub Actions CI (API lint/typecheck/
test/build + Flutter analyze/test) · migration `0001_production_features`
(applies cleanly; **not yet applied to Neon**) · release builds fail loudly
without `API_BASE_URL` · Android label "Dayflow" · iOS photo-library usage
string.

**Still open (needs accounts, hosting, or assets — not code):** FCM push ·
Google/Apple sign-in client IDs · R2/S3 storage · Sentry/Crashlytics · rehost
API off Vercel serverless (or add Redis pub/sub + hosted throttle storage) ·
Android release keystore · launcher icons/splash art · store listings ·
`NODE_ENV=production` flip on Vercel with a real Resend key + `PUBLIC_BASE_URL`
+ apply migration 0001 to Neon. Deliberately skipped as code-only-but-partial:
i18n (needs a real translation pass) and offline-first storage (an architecture
project of its own).

The sections below are the original audit, kept for reference.

---

## 1. Half-baked / UI-only features

Features where the UI (or schema) exists but the behavior behind it is missing or broken in production.

### Push notifications — UI only, zero delivery
- Onboarding "enable notifications" screen is cosmetic: the Continue button just navigates, no permission request (`apps/mobile/lib/features/onboarding/notifications_screen.dart`).
- Settings exposes Push/Email toggles that PATCH `/me/notification-prefs` — but nothing ever consumes those prefs (`apps/mobile/lib/features/settings/settings_screen.dart:275`).
- `device_tokens` table exists in the schema with **no registration endpoint and no consumer** — FCM/APNs is entirely unimplemented.
- No `POST_NOTIFICATIONS` permission in the Android manifest (required on Android 13+).
- **To finish:** FCM integration (firebase_messaging + google-services.json), a device-token registration endpoint, a sender in `notifications.service.ts`, permission wiring in onboarding.

### Email notifications — toggle with no channel
- `notifications.service.ts` only inserts/reads DB rows; nothing sends notification emails. No digest job exists (no `@nestjs/schedule`, no cron anywhere).

### Google sign-in — no-op button + a security bug behind it
- Mobile button shows a SnackBar: "will be enabled once a client ID is configured" (`apps/mobile/lib/features/auth/email_screen.dart:85`).
- API endpoint `POST auth/google` exists, but `verifyIdToken` is called **without `audience`** (`apps/api/src/modules/auth/auth.service.ts:185`) — an ID token minted for *any* Google OAuth client would be accepted → account takeover by email. Must pass `audience: GOOGLE_CLIENT_ID` before enabling.
- `GOOGLE_CLIENT_ID` on Vercel is likely still blank from the bulk import.

### Apple sign-in — "coming soon" no-op
- `email_screen.dart:94`. Required by App Store policy if Google sign-in ships on iOS.

### Member invites — emails link to a dead deep link
- Invites generate `dayflow://invite/<token>` (`apps/api/src/modules/members/members.service.ts:344`), but the scheme is **never registered**: no `<intent-filter>` in the Android manifest, no `CFBundleURLTypes` in iOS Info.plist. The link in the invite email does nothing on any platform, and there is no web fallback URL.
- Invite tokens are stored **in plaintext** (unlike refresh tokens, which are hashed).
- `devLink` (raw invite token) leaks in responses whenever `OTP_DEV_ECHO=true` — with **no NODE_ENV gate** (`members.service.ts:56,116,209`), unlike the OTP echo which is correctly production-gated.

### Realtime board sync — built on both ends, dead in the deployed environment
- Full WS client with reconnect/backoff (`apps/mobile/lib/core/realtime/realtime_client.dart`) and a hand-rolled `ws` gateway on the API — but the gateway is deliberately **not attached in serverless** (`apps/api/src/serverless.ts:9-15`); `publish()` degrades to a no-op.
- Client has **no polling fallback and no stale/offline indicator** — against the Vercel deployment it reconnect-loops forever and boards silently never update.
- Fan-out is in-process only (`realtime.gateway.ts:41`) — even on a WS-capable host it breaks with >1 instance without Redis pub/sub.
- Also: the WS auth token is passed in the query string (leaks into proxy/access logs).

### File attachments & avatars — work locally, broken in production
- Local-disk storage only, no S3/R2 anywhere (`apps/api/src/modules/files/files.service.ts:40`). On Vercel, `/tmp` is per-instance and ephemeral — uploads vanish. `vercel.json` sets no env vars, so without `UPLOAD_DIR` set uploads may throw outright.
- Serving is unauthenticated and echoes the client-supplied MIME type inline → uploading `text/html` gives **stored XSS on the API origin** (`files.controller.ts:85-93`).
- The 15MB size check runs *after* multer buffers the whole body in memory — no `limits` option on the interceptor. No MIME/extension allowlist.
- **To finish:** R2/S3 with presigned URLs (as PLAN.md always intended), MIME allowlist, multer limits, `Content-Disposition: attachment` or a sandboxed domain for user content.

### OTP email login — real Resend integration exists but is silently disconnected
- `mail.service.ts:38-42`: if `RESEND_API_KEY` is unset, `send()` logs and **returns success**. In production that means "OTP sent!" with no email ever delivered. `RESEND_API_KEY` on Vercel is likely still blank from the bulk import.
- Production currently only works because demo mode (`NODE_ENV=development` + `OTP_DEV_ECHO=true`) echoes the code in the API response — which also means **anyone can log in as any email address** on the live deployment.
- **To finish:** real Resend key, flip `NODE_ENV=production` + remove `OTP_DEV_ECHO`, and make `MailService.send()` throw in production when unconfigured instead of no-oping.

### Feedback form — submissions are discarded
- `users.controller.ts:124-129` `console.log`s the message and returns; nothing is persisted. Needs a table or forwarding (email/Slack).

### Support center — "coming soon" toast
- `apps/mobile/lib/features/more/more_screen.dart:78`.

### Account deletion grace flow — dead schema column
- `accounts.deletion_scheduled_at` exists (`src/db/schema/accounts.ts:13`) but is referenced nowhere; no processor job. Either build the flow or drop the column.

### Board-level membership — not enforced
- Access control is account-level only (per README). Board members/roles exist in UI but any account member can reach any board via the API.

### Dashboards view — planned (Phase 3), not built
- The 4-widget dashboard view from PLAN.md never landed (README "not built yet").

### i18n — planned (EN/ES/ZH), not built.

### Sidekick AI — intentionally deferred to v1.1 per sign-off; no action needed for v1.

---

## 2. Security fixes required before real users

1. **Google `verifyIdToken` without `audience`** — account takeover; fix before enabling Google sign-in (`auth.service.ts:185`).
2. **Live deployment is in demo mode** — `NODE_ENV=development` + `OTP_DEV_ECHO=true` on Vercel: OTP codes echoed in responses.
3. **CORS falls back to reflect-any-origin** when `CORS_ORIGINS` is empty (`main.ts:20`, `serverless.ts:25`) — and it's likely empty on Vercel. Make it required in production in the zod schema.
4. **Rate limiting is not actually enforced on serverless** — `ThrottlerModule` uses in-memory storage; each lambda has its own counter. Needs Redis/Upstash storage. Also `auth/refresh`, `auth/google`, `signup/complete` and uploads have no per-route throttle.
5. **OTP attempt limit is resettable** — re-requesting a code invalidates the old row and resets the 5-attempt budget (`otp.service.ts:19-30`). Add a per-email persistent failure counter/lockout.
6. **Stored XSS via file serving** (see §1 files).
7. **Swagger `/docs` is public in production** — gate on `NODE_ENV`.
8. **Invite tokens plaintext at rest** — hash like refresh tokens.
9. **JWT secret** — local `.env` uses a dev-grade secret; confirm the Vercel value is a fresh strong random.
10. **Refresh rotation isn't transactional** — two concurrent refreshes with the same token can both succeed before revocation lands (`token.service.ts:61-75`).
11. **WS token in query string** — move to first-message auth or a ticket endpoint.

(What's already good: helmet on, argon2-hashed OTPs, SHA-256-hashed refresh tokens with family-based reuse detection and revoke-all-on-password-change, no default JWT secret, strict zod env validation, secure token storage on mobile via flutter_secure_storage.)

---

## 3. Infrastructure gaps

- **Hosting:** Vercel serverless cannot host the WS gateway. PLAN.md specified Railway. Either move the API to a long-running host (Railway/Fly/Render) — which also fixes throttling, cron, and `/tmp` — or keep Vercel and add client polling + Pusher/Ably + Upstash. Moving is the smaller total change.
- **Object storage:** R2/S3 for uploads (see §1).
- **Background jobs — none exist, and several tables grow unbounded:** expired refresh tokens, consumed OTP rows, and expired invitations are never purged; account deletion has no processor; no notification digests.
- **Migrations are manual:** no migrate step on deploy; `scripts/migrate.ts` silently falls back to localhost on misconfigured env — make it fail loudly and add a deploy-time migrate.
- **Observability — nothing:** no health endpoint, no structured/JSON logging, no request IDs, no Sentry, no global exception filter. Minimum bar: `/healthz`, pino, Sentry (API + Flutter).
- **CI/CD — nothing:** no `.github/workflows`. Minimum bar: lint + typecheck + `vitest` + `flutter analyze` + `flutter test` on push.

---

## 4. Mobile store readiness

1. **Release builds sign with the debug keystore** (`android/app/build.gradle.kts:34`) — Play will reject. Create a keystore + `key.properties` + `signingConfigs.release`.
2. **Launcher icons are the stock Flutter logo on both platforms**; native splash is plain white; no adaptive icon. Use `flutter_launcher_icons` + `flutter_native_splash`.
3. **`API_BASE_URL` defaults to dev loopback** (`http://10.0.2.2:4000`) with no build-time guard — a release build without `--dart-define` is dead on launch, and silently (cleartext is debug-only). Add an assert/flavor.
4. **No crash reporting** — no Sentry/Crashlytics, no `runZonedGuarded`. Blind in the field.
5. **iOS:** no `DEVELOPMENT_TEAM`/provisioning; missing `NSPhotoLibraryUsageDescription` despite `file_picker` usage (rejection/crash risk); pods never installed (Windows dev box — needs a Mac or CI runner to ship iOS).
6. No R8/minify, no proguard rules, no versionCode automation, app label casing mismatch ("dayflow" vs "Dayflow").
7. **No offline handling:** all data providers are memory-only `autoDispose`; cold start offline = error screens; no connectivity indicator; optimistic edits have rollback but no offline queue.

---

## 5. Test & quality gaps

- API tests are 5 pure unit specs (~500 lines); **zero HTTP/integration tests** — supertest is installed but unused. Nothing exercises controllers, guards, tenancy isolation, token rotation, or the OTP flow.
- The Flutter `api_e2e_test.dart` (42 tests) is the only end-to-end coverage and **self-skips silently** when no API is on :4000 — green CI could mean nothing ran.
- No tests for the 401-refresh interceptor path, WS reconnect logic, or router guards.

---

## Suggested order of attack

1. **Production env flip + quick security fixes** (small): Resend key, `NODE_ENV=production`, kill OTP echo, require `CORS_ORIGINS`, gate Swagger, Google `audience`, mail-throws-in-prod, strong JWT secret. Turns the demo into a real (if degraded) product.
2. **Rehost the API** to Railway/Fly + Redis (throttler storage + WS pub/sub) + R2 uploads. Unblocks realtime, files, rate limiting, and cron in one move.
3. **Finish invites**: register the `dayflow://` scheme (+ App/Universal Links with a web fallback page), hash invite tokens.
4. **Mobile release hardening**: keystore, icons/splash, crash reporting, base-URL guard, iOS usage strings.
5. **Push notifications (FCM)** — the largest net-new feature; the schema and UI are waiting for it.
6. **CI + observability + cleanup jobs.**
7. **Product picks**: feedback persistence, board-level membership enforcement, dashboards view, i18n.
