# Dayflow

A work-management app in the spirit of monday.com — boards, groups, typed columns,
workspaces, and multi-account teams. Flutter client, NestJS + Postgres API.

> Dayflow is an independent product with its own name, mark, and palette. It borrows
> the *interaction model* of board-based work management, not any competitor's branding.

## Layout

```
dayflow/
├─ apps/
│  ├─ api/          NestJS 11 + Drizzle ORM + Postgres
│  └─ mobile/       Flutter client (iOS · Android · web · desktop)
├─ packages/
│  └─ contracts/    Shared TypeScript request/response types
└─ docker-compose.yml   Local Postgres
```

## Prerequisites

- Node 20+
- Flutter 3.38+ (Dart 3.12+)
- No database install needed — `db:local` runs a project-local Postgres

## Running it

**1. Database**

```bash
npm install
npm run db:local              # embedded Postgres on :5433, data in .pgdata
npm run db:migrate            # apply schema (separate terminal)
```

`db:local` keeps running; leave it in its own terminal. If you would rather use
Docker or a hosted Postgres, `docker compose up -d` starts one on :5432 — point
`DATABASE_URL` in `apps/api/.env` at whichever you choose.

To run against a hosted database (e.g. Neon), set `DB_LIVE_URL` in
`apps/api/.env` to the pooled connection string — the API, migrations, and
seeds all prefer it over `DATABASE_URL` when it is set.

**2. API**

```bash
npm run api:dev               # http://localhost:4000, Swagger at /docs
```

In development the OTP endpoints echo the verification code back as `devCode`
(and log it), so you can complete signup without a configured mail provider.
Set `SMTP_*` in `apps/api/.env` to send real email; `devCode` is suppressed when
`NODE_ENV=production`.

**3. Client**

```bash
cd apps/mobile
flutter run                                  # picks a connected device
flutter run -d chrome --web-port=5173        # or the browser
```

The client resolves the API origin per platform — `10.0.2.2` on the Android
emulator, `localhost` elsewhere. Override it explicitly:

```bash
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

## What works today

**Auth & accounts**
- Email OTP sign-up and log in (6-digit code, 30s resend cooldown, rate limited)
- Password log in, argon2id hashed, with a fallback to one-time codes
- JWT access tokens (15 min) + rotating refresh tokens (30 days) with
  reuse detection — a replayed refresh token revokes the family
- Multiple accounts per email, account picker at login, in-app account switcher
- Session restore on cold start; single-flight refresh on 401

**Onboarding**
- Three persona questions (`I'm here for…`, `I want to manage…`, `I mainly work on…`)
- Account + workspace + starter board seeded from the answers
- Notification ask, confetti finish, setup checklist that tracks real progress

**Home**
- Greeting, setup-progress ring, favorites, recently visited, workspaces
- Board favoriting (optimistic, reconciled against the server)
- Visit tracking feeding "recently visited"

**Boards**
- Editable table view: create/rename/duplicate/delete items, inline "add item"
- Typed cell editors for status, people, date, text, number, checkbox, link,
  timeline, location, dropdown and tags — validated server-side per column type
- Groups: add, rename, recolor, collapse, reorder, delete (never the last one)
- Columns: add, rename, delete, and edit the choices of status/dropdown/tags
  columns (labels, colours, which label counts as done)
- Drag items to reorder within a group, or move them between groups; fractional
  positions so a reorder writes one row instead of renumbering the list
- Kanban view with drag-and-drop between status lanes
- Board creation from six templates (task management, content calendar,
  client projects, event management, requests & approvals, blank)
- Optimistic editing throughout: the UI updates first and rolls back if the
  server rejects the change

**Items**
- Item card with the design's Columns / Updates / Files tabs
- Updates: threaded replies (one level), likes, bookmarks, edit and delete;
  `@Full Name` mentions notify account members, replies notify the parent author
- Files: upload attachments (15MB cap, local-disk storage in dev), image
  previews, delete; served via unguessable-id URLs so image widgets can load
  them without a bearer token (production would swap in presigned R2/S3 URLs)
- Activity log under the Columns tab; every mutation writes an entry

**Motion**
- Motion tokens lifted from monday.com's Vibe design system
  (`--motion-productive-*` 70–150ms, `--motion-expressive-*` 250–400ms, and the
  four Vibe easing curves including the signature overshoot
  `cubic-bezier(0, 0, 0.2, 1.4)`) — see `lib/core/theme/motion.dart`
- Entrance staggers on Home, item cards, updates, files and feeds
- Status pills pop on change and shimmer when the new label counts as done
  (echoing Vibe's label celebration); likes burst; group collapse sweeps with
  AnimatedSize; filter chips and calendar days transition on the standard curve

**Collaboration**
- Invite teammates by email with an admin/member/viewer role; re-inviting an
  address replaces the outstanding invitation rather than piling up rows
- Accept invitations, change roles, remove members; an account always keeps at
  least one admin
- Role enforcement across the API: viewers and guests can read but not write
- People cells offer account members, so assignment works across the team
- Real-time board sync over WebSocket (`/v1/realtime`): items, cells, groups and
  columns update live for everyone viewing a board, with the actor excluded so
  their optimistic update is never echoed back

**Views & filtering**
- Table (editable), Kanban (drag between status lanes), and a month Calendar
  over the board's date column, with a view switcher on the board
- Quick Find bar filters items by name as you type; quick-filter sheet narrows
  by person and status label (reordering pauses while a filter is active)

**My Work, search, notifications, feed**
- My Work aggregates items assigned to you across every board, bucketed into
  overdue / today / this week / later / no date, with "Hide done items" and a
  visible-boards filter as in the design
- Search across board and item names (debounced, LIKE-escaped)
- Notification center with All / Unread / I was mentioned / Assigned tabs and
  in-feed search; per-user email/push preference toggles
- Company-wide Update Feed with board filter and bookmarks-only view
- Board CSV export (copies to clipboard in-app, or `GET /v1/boards/:id/export.csv`)

**Profile & settings**
- Profile photo upload, name and personal-status editing, change password
  (revokes other sessions), notification preferences, send feedback

## Verification

```bash
npm run typecheck && npm run lint && npm run api:test    # API — 81 unit tests
cd apps/mobile && flutter analyze && flutter test        # client — 87 tests
```

The realtime gateway has its own smoke check, since WebSocket fan-out is not
covered by the HTTP e2e suite. It needs two access tokens for the same account:

```bash
npm run realtime:check -w @dayflow/api -- <tokenA> <tokenB> <boardId> <groupId>
```

It asserts that an unauthenticated handshake is refused, that a subscriber
receives `item.created` and `cell.changed`, and that the actor receives nothing.

`apps/mobile/test/api_e2e_test.dart` drives the real client stack (Dio, token
store, repositories, models) against a live API across 33 tests: signup by OTP,
board creation from a template, item and cell writes with validation failures,
group and column CRUD, status-label editing, item moves, updates, My Work,
search, board archiving, invitations with their admin guards, refresh-token
rotation with reuse detection, re-login and logout.
It skips itself when no server is listening, so the default run needs nothing
extra. To run only the offline tests:

```bash
flutter test --exclude-tags e2e
```

Note that `POST /v1/auth/otp/request` is rate limited to 5/minute per IP; running
the e2e suite more than twice inside a minute exhausts that budget and the
affected tests report themselves as skipped.

## Not built yet

Calendar and timeline views, dashboards, file attachments, threaded replies on
updates, rich-text update bodies, automations, and account-authored custom
templates (the `templates` table is reserved for these; the shipped catalog
lives in `templates.catalog.ts`).

Also outstanding:

- **Push delivery.** Notification prefs exist and are editable, but
  `device_tokens` is unused and nothing is delivered via FCM/APNs; email
  notifications likewise need a digest job.
- **Deep links.** Invitations are emailed as `dayflow://invite/<token>` but no
  URL scheme is registered, so invitees paste the link via
  More → "Accept an invitation". Admins can copy a pending invite's link from
  the members screen while no mail provider is configured.
- **Board-level membership.** `board_members` exists and is populated for board
  creators, but access is account-wide today: every member can open every board
  in the account, and `private` / `shareable` board types are not enforced.
- **Realtime scale-out.** Fan-out is in-process, so more than one API instance
  needs a shared bus (Redis pub/sub) before events reach clients on other nodes.
- **Production file storage.** Attachments live on local disk and are served by
  unguessable id; production needs R2/S3 with presigned URLs.
- **Dashboard view, saved views, advanced filter builder.** Table/Kanban/
  Calendar and quick filters exist; widget dashboards and the
  "Where {column} {condition} {value}" builder do not.
- **List view.** The mobile table already renders as a list; a distinct
  condensed list view was skipped.
- **Group reorder in the UI.** `POST /groups/:id/move` exists; the app reorders
  items by drag but groups only via the API.
- **Google and Apple sign-in.** Buttons show a "coming soon" toast; the API has
  `POST /v1/auth/google` and needs a client ID.
- **Coach-marks tour, i18n, subitems, automations, workdocs, audio notes,
  document scan.** Not started (several are deferred to v1.1 in the plan).
