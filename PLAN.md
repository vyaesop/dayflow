# Dayflow — Work Management Platform · Build Plan (signed-off stack)
**Source:** 31 design boards (~200 screens) in `monday project management app design/`
**Status:** Plan approved pending final "go" · **Date:** 2026-07-03

**Locked decisions:** Flutter app · custom API on Neon Postgres · brand = **Dayflow** · AI assistant deferred to v1.1

---

## 1. Executive summary

The screenshots are the complete mobile experience of a monday.com-class work-management product: flexible boards with dynamic columns, multiple views (Table / Kanban / Calendar / Dashboard), rich item updates with mentions and files, cross-board "My Work", notifications, team/role administration, and full account lifecycle.

We build this as **Dayflow** — an original, investor-ready product. Layouts, flows, and interaction patterns follow the screenshots; branding, wording, and color tuning are ours (monday.com's name/logo are trademarks; the UX patterns are industry-standard and not protectable).

**Build:** a **Flutter** app (iOS + Android, with a Flutter Web build for URL-based investor demos) backed by a **NestJS API** with **Drizzle ORM on Neon Postgres**, WebSocket realtime, FCM push, and S3-compatible file storage.

---

## 2. Feature inventory (extracted from the screenshots)

### Auth & account lifecycle
- Splash → welcome (Log in / Create account)
- Sign up / log in with Google, Apple, or email
- **6-digit email OTP verification**
- Multi-account per email → "Choose an account to log in", account switcher, add account
- Change password, forgot-password email flow (with resend timer)
- Log out; **delete account** flow (type account name to confirm, 30-day grace period, "Are you sure" dialog, scheduled-for-deletion screen)

### Onboarding wizard (progress bar, skippable)
- Full name + password → "I'm here for ___" (Work / Personal / School)
- "I want to manage ___" (Workflows, Construction, Operations, Product, HR…)
- "…and I mainly work on ___" (Task mgmt, Business ops, Client projects, Content calendar, Event mgmt, Digital assets…)
- Notification permission ask → confetti "Done" → seeds the first board + guided coach-marks tour (3 steps)

### Home
- Greeting + **setup progress ring (33%)** with checklist (create board / learn basics / full experience)
- **My favorites** carousel (gradient hero cards), **Recently visited**, **Workspaces** entry
- Bottom tabs: Home · My Work · Notifications · More, plus a global **FAB** (New Item / New Column / New Group)

### Boards core
- Workspaces → Boards → **Groups (color-coded) → Items → dynamic Columns**
- Board types: **Main / Shareable / Private**; favorites; board description; created-by; delete board
- Templates gallery: Start from scratch, Team Tasks, Workdoc, Sales Process, Project High-Level Plan, Job Recruitment, Social Media Schedule, Content Calendar… with preview and "used by N teams"
- **Column Center**: Essentials (Status, People, Date, Text, Number, Tags, Timeline, Subitems), Featured (Vote, Location), Super useful (Checkbox, Dropdown, …)
- Table view: inline add item/group/column, updates bubble per item, Quick Find, per-column value cells

### Views
- **Main Table**, **List**, **Kanban** (lanes by status/label), **Calendar** (month), **Dashboard** (widgets, "add widget", scheduled PDF-export teaser)
- View switcher + **Save view** (named saved views per board)

### Filtering & search
- Quick filters: item name chips, Person, Status labels, Date presets (Today / Tomorrow / Yesterday / This week)
- **Advanced filter builder**: Where {Column} {Condition} {Value} + "Add another filter", column picker, person picker (Me dynamic / users / Unassigned)
- Board "Quick find"; global **Search Everywhere** (boards, items, updates; recent searches; show/hide archives; empty states)

### Item detail (card)
- Tabs: **Columns / Updates / Files**
- Column editors: Person picker (search + invite by email), Status picker (Working on it / Stuck / Done + Add/Edit labels), Date picker (calendar + optional time), text/number/etc.
- **Updates composer**: rich text, @mentions (people / Everyone on board / Everyone on item), file upload, photo, camera, checklist, audio note; upload progress
- Update actions: like, reply (threads), share, **bookmark**, copy, edit, delete (with confirm)
- Item actions: rename, **duplicate**, **move to group**, **move to board** (column-mismatch warning), archive, delete

### Collaboration
- **Board members** (add/remove, invite by email with role), member roles: **Admin / Member / Viewer / Guest**
- **Board discussion** (board-level update thread), **Activity log** (status/date/person changes, group/column created…)
- Invite a new team member (email + role, sent toast); **My Team** list
- **Update Feed** (company-wide), filter by board, **Bookmarks**

### My Work
- Cross-board aggregation into date buckets: Past Dates / This Week / Next Week / Later / Without a Date
- Hide done items; **Visible boards** filter; **Following** (people) filter
- Item quick-card; **Add to calendar** (device calendar via native integration) + **My Calendar** day view

### Notifications
- Tabs: All / Unread / **I was mentioned** / Assigned to me; search within notifications
- Mark all as read; settings: **email notifications** + **mobile push** toggles
- Push notifications (FCM) for mentions/assignments/updates

### Profile & settings
- Profile: avatar (photos / selfie / delete), **personal status presets** (Working from home, Out sick, On break, Out of office, Working outside, Family time, Do not disturb), personal info, Teams tab
- More tab: Update Feed, My Team, Search everywhere, Account, Notification settings, **Language** (full i18n incl. CJK — screenshots show a complete Chinese localization), Admin settings, Change password, Privacy/Terms, Join beta, Support & Feedback (Knowledge base, Send feedback with screenshot, Rate app, Report a problem, Intro tutorial), version, log out

### Admin
- **Manage Users**: list with role/status/team filters, change role (Admin/Member/Viewer/Guest), pending invites
- Delete account (admin-level, whole-org) flow

### Misc
- Export board to Excel/CSV; collapse/expand groups; zoom
- Empty states, success toasts, and error states throughout

### Deferred to v1.1+
- **Sidekick AI assistant** (full chat UX exists in the designs — parked per sign-off; the API is designed so a board-context AI service can bolt on later)
- Subitems, workdocs, automations, create-items-via-email, scheduled PDF exports, home-screen widgets, QR login, document scan, audio notes

---

## 3. Brand & design system

1. **Brand: Dayflow.** Original geometric logo mark, original template copy, no monday.com assets anywhere.
2. **The "saturation" fix.** Keep the airy pastel layout language, tune the color chemistry:
   - One restrained primary: indigo `#5B5BD6` (pressed `#4E4EC4`) — used sparingly: primary buttons, active tabs, links, selection.
   - Neutral surfaces: app bg `#F7F8FA`, cards `#FFFFFF`, borders `#E9EAF0`, text `#1B1D29` primary / `#6B6F80` secondary.
   - Status colors desaturated a step and darkened for WCAG AA with white text: Working on it **amber `#DD9A2E`**, Done **green `#2E9E6B`**, Stuck **red `#D65C6B`**, extra **blue `#4E7FD9`**, **purple `#8B66C9`**.
   - Group accent bars from the same muted family; favorites-hero gradient softened ~15%.
   - **Dark mode from day one** — all colors flow through theme tokens (Flutter `ThemeExtension`), zero hardcoded colors.
3. **Typography:** Inter (bundled), matching the SF Pro feel with a free license.
4. **Layout:** pixel-faithful to the 390pt mobile designs; adaptive layout (rail navigation, wider content) on tablets/desktop/web builds so laptop demos look intentional.

---

## 4. Stack (locked)

| Layer | Choice | Notes |
|---|---|---|
| App | **Flutter** (Dart 3, Material 3 heavily re-themed) | iOS + Android; **Flutter Web build** deployed for URL-based investor demos |
| App state | **Riverpod** (codegen) + `freezed` models | Predictable, testable, standard |
| Navigation | `go_router` | Deep links (board/item routes) |
| API client | Dio + **OpenAPI-generated Dart client** | Backend publishes OpenAPI; client types always in sync |
| Local persistence | `hive` (session/tokens/cache) | Offline-tolerant reads, instant cold start |
| Backend | **NestJS** (TypeScript, REST + OpenAPI/Swagger) | Enterprise-diligence-friendly structure, guards for roles |
| ORM / DB | **Drizzle ORM on Neon Postgres** | Neon serverless driver + pooled connections; branch databases for dev/preview |
| Realtime | NestJS WebSocket gateway (socket.io), board-room channels | Neon has no realtime — we own it; server-authoritative events |
| Auth | JWT access/refresh; **email OTP (6-digit, matches design)** via Resend; Google Sign-In (server-verified); Apple stubbed until dev account | Argon2 password hashing; rate-limited |
| Push | **Firebase Cloud Messaging** | Mentions, assignments, updates |
| Files | **Cloudflare R2** (S3 API, presigned uploads) | Avatars + update attachments |
| Email | **Resend** + React Email templates | OTP, invites, resets, notification digests |
| Testing | Flutter unit/widget/integration tests; backend Jest + supertest; GitHub Actions CI | Typecheck + lint + tests on every push |
| Deploy | API on **Railway** (WebSocket-friendly) · Neon cloud DB · Flutter Web demo on Cloudflare Pages · stores via TestFlight/Play later | |

**Monorepo layout**
```
dayflow/
  apps/mobile        # Flutter app
  apps/api           # NestJS + Drizzle
  packages/contracts # OpenAPI spec + generated Dart/TS clients
  tooling/           # CI, seed scripts, codegen
```

---

## 5. Architecture & data model (core tables)

```
accounts (org/tenant) ── account_members (user, role: admin|member|viewer|guest, status)
users ── user_profiles (avatar, personal_status, language) ── teams / team_members
workspaces ── boards (type: main|shareable|private, description)
board_members (role) · board_favorites · recent_visits
groups (board_id, title, color, position)
items (group_id, name, position, archived_at)
columns (board_id, type, title, settings jsonb, position)   ← column-type registry
column_values (item_id, column_id, value jsonb)             ← one row per cell
board_views (board_id, type: table|kanban|calendar|dashboard|list, name, config jsonb)
updates (item_id | board_id, author, body richtext, parent_id) · update_likes · update_bookmarks
files (owner refs, r2_key, meta)
activity_log (board_id, item_id, actor, event, payload jsonb)
notifications (user_id, type, payload, read_at) · notification_prefs · device_tokens (FCM)
invitations (email, role, status, token)
templates (gallery definitions, seed payloads)
otp_codes / refresh_tokens (auth)
```

Key engineering choices:
- **Column engine:** a typed registry (`status`, `people`, `date`, `text`, `number`, `tags`, `dropdown`, `checkbox`, `timeline`, `vote`, `location`, `link`) — each type declares its cell renderer, editor sheet, filter conditions, kanban-groupability, and validation, mirrored in Dart (UI) and TS (validation). New column types are additive.
- **Multi-tenancy:** every row carries `account_id`; NestJS guards enforce tenant isolation + role permissions on every route; board-level roles layered on top.
- **Optimistic UI + realtime:** mutations apply instantly in Riverpod state, POST to API, broadcast to board-room WebSocket channels; server-authoritative last-write-wins per cell, everything journaled to `activity_log`.
- **Ordering:** fractional indexing for drag-reorder of groups/items/columns without renumbering.
- **Neon specifics:** pooled connection string for the API, direct string for migrations; **Neon branch per PR** for preview environments; point-in-time restore as the backup story.

---

## 6. Build phases

**Phase 0 — Foundation.** Monorepo scaffold (Flutter + NestJS + contracts), Neon setup + initial Drizzle migrations, design-token theme + core UI kit (buttons, sheets, chips, avatars, toasts, tab bar, FAB), auth end-to-end (email OTP, Google, JWT refresh, account switcher), onboarding wizard + notification ask + confetti, seeded first board, coach-marks tour, Home shell.

**Phase 1 — Boards core.** Workspaces/boards CRUD, board types, favorites, recently visited, templates gallery (8 templates + start-from-scratch), groups/items CRUD with drag-reorder, column engine v1 (Status, People, Date, Text, Number), Table view, Quick Find, board info screen, FAB actions.

**Phase 2 — Item depth + realtime.** Item card (Columns/Updates/Files tabs), all column editor sheets, updates composer (mentions, images, file upload via R2, checklist), threads/likes/bookmark/edit/delete, item duplicate/move/archive, activity log, WebSocket realtime board sync.

**Phase 3 — Views & filtering.** Kanban, Calendar, List, Dashboard (4 starter widgets: numbers, status battery, chart, calendar peek), saved views, quick filters + advanced filter builder, column center with remaining types (Tags, Dropdown, Checkbox, Timeline, Vote, Location, Link).

**Phase 4 — Collaboration & comms.** Board members + roles, email invites (Resend), My Team, board discussion, notifications center (All/Unread/Mentioned/Assigned) + **FCM push** + email notifications + prefs, Update Feed + bookmarks, My Work (buckets, visible-boards & following filters) + My Calendar + device-calendar add, global Search Everywhere.

**Phase 5 — Admin & polish.** Excel/CSV export, profile (avatar upload/selfie, personal status presets), admin user management + org delete-account grace flow, change password, settings + feedback form, i18n scaffold (EN + ES + ZH via `flutter_localizations`), dark-mode pass, Flutter Web demo build tuning.

**Phase 6 — Hardening & demo.** Integration/E2E tests on golden paths, seed script for a convincing demo org (realistic boards/data), performance pass (60fps scrolling on big boards, cold start < 2s), security review, production deploy (Railway + Neon + R2 + Cloudflare Pages), README + architecture docs + investor demo script.

---

## 7. Quality bar

- Dart strict analysis + TS strict; CI blocks on typecheck, lint, tests.
- WCAG AA contrast (the mockups' pastel status chips fail — our tuned palette fixes this).
- Every screen ships its empty / loading / error state.
- Optimistic edits < 100ms perceived; realtime propagation < 1s; 60fps board scrolling.
- Argon2 hashing, rate-limited auth, short-lived JWTs + rotating refresh tokens, presigned uploads, tenant guards on every route.

---

## 8. Costs & prerequisites (user-provided)

- **Neon** free tier to start (you create the project → provide `DATABASE_URL`, or I scaffold against local Postgres until then).
- **Railway** ~$5/mo for the API · **Cloudflare** R2 + Pages free tiers · **Resend** free (3k emails/mo) · **Firebase/FCM** free.
- **Google OAuth client ID** (free) for Google Sign-In; **Apple Developer** ($99/yr) only when we ship Sign in with Apple + TestFlight — button stubbed until then.

## 9. Sign-off record

| Decision | Choice |
|---|---|
| Platform | **Flutter** (iOS/Android + Web demo build) |
| Backend | **Custom NestJS + Drizzle on Neon Postgres** |
| Brand | **Dayflow** |
| AI Sidekick | **Deferred to v1.1** (API designed to bolt on later) |

**Next step:** on your "go ahead", building starts at Phase 0.
