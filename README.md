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
Set `RESEND_API_KEY` in `apps/api/.env` to send real email; `devCode` is
suppressed when `NODE_ENV=production`, and production refuses to boot without a
mail key so email can never silently no-op. Set `PUBLIC_BASE_URL` to the API's
public https origin so invite emails link to the hosted landing page
(`/invite/<token>`) instead of a raw deep link.

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
- Editable table view: create/rename/duplicate/archive/delete items, inline "add item"
- 21 column types — status, people, date, timeline, text, long text, number
  (unit, decimals, summary mode), checkbox, dropdown, tags, link, email, phone,
  location, files, rating, vote, plus the read-only Item ID, Creation log,
  Last updated and Auto number — every value validated server-side per type
- Subitems (one level) with their own column set, nested under the parent row
  with a "N subitems · M done" roll-up; parents carry their subitems through
  duplicate, move, archive and restore
- Saved views per board: named Table / Kanban / Calendar / Dashboard views that
  store filters, multi-column sort, hidden and reordered columns and
  conditional colours; one default view; a shared TS/Dart filter engine keeps
  the CSV export and the app in agreement
- Advanced filter builder ("Where column · condition · value", And/Or, date
  presets, dynamic "Me"), sort sheet, column visibility/reorder sheet and
  conditional colouring (cell or row) on top of Quick Find and quick filters
- Column summary footers per group: sums/averages, rating averages, status
  batteries, checkbox counts, people counts, date ranges
- Groups: add, rename, recolor, collapse, reorder, delete (never the last one)
- Batch actions: select many items and set status, assign, move, duplicate,
  archive or delete them in one transactional request
- Archive (indefinite) and Trash (purged after 30 days) for boards and items,
  with an Archive & trash screen to restore or delete permanently
- Move an item to another board with a column-mapping preview (same-named
  columns keep their values, the rest is listed as lost); duplicate a board
  (structure / items / items + updates); save a board as an account template
- Drag items to reorder within a group, or move them between groups; fractional
  positions so a reorder writes one row instead of renumbering the list
- Kanban view with drag-and-drop between status lanes
- Board creation from six built-in templates plus the account's own
- Optimistic editing throughout: the UI updates first and rolls back if the
  server rejects the change

**Items**
- Item card with Columns / Updates / Files / Subitems tabs
- Updates: rich text (bold, italic, strike, code, links, lists), threaded
  replies (one level), emoji reactions, bookmarks, inline image and file
  attachments, edit and delete; `@` mention autocomplete notifies account
  members or "Everyone on this board", replies notify the parent author
- Board discussion: an update thread on the board itself
- Board activity log with filters, keyset pagination and a 7-day undo for
  value changes, renames, moves and archives
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

Automations, timeline/Gantt views, dependencies, mirror/formula columns and
time tracking. See `MONDAY_FEATURE_GAP.md` for the full comparison and the
remaining backlog.

Also outstanding:

- **Push delivery.** Notification prefs exist and email delivery works
  (mentions, assignments, replies respect the email toggle), but
  `device_tokens` is unused and nothing is delivered via FCM/APNs — that needs
  a Firebase project.
- **Realtime scale-out.** Fan-out is in-process, so more than one API instance
  needs a shared bus (Redis pub/sub) before events reach clients on other
  nodes. Clients fall back to polling (25s) with a visible notice whenever the
  socket cannot connect — e.g. on a serverless host.
- **Production file storage.** Attachments live on local disk and are served by
  unguessable id (only allowlisted image types render inline; everything else
  downloads as an opaque attachment). Production wants R2/S3 with presigned
  URLs.
- **List view.** The mobile table already renders as a list; a distinct
  condensed list view was skipped (a `list` view type is accepted and renders
  as the table).
- **Google and Apple sign-in.** The mobile buttons show a "coming soon" toast
  until OAuth client IDs exist; the API's `POST /v1/auth/google` verifies the
  token audience and is ready once `GOOGLE_CLIENT_ID` is set.
- **Crash reporting.** No Sentry/Crashlytics — needs an account/DSN.
- **Release packaging.** Android still signs with the debug keystore and both
  platforms ship the stock Flutter launcher icon; a keystore, icon set, and
  splash art are needed before a store submission.
- **Coach-marks tour, i18n, automations, workdocs, audio notes, document
  scan.** Not started (several are deferred to v1.1 in the plan).

Recently closed out (all verified by the e2e suite or manual probes): invite
deep links (`dayflow:///invite/<token>` registered on both platforms, hosted
landing page at `GET /invite/<token>`, hashed tokens at rest, pending-invite
hand-off through signup), the full board-type model end to end (see below),
the widget Dashboard view, notification emails, the support center, product
feedback persistence, the 30-day account-deletion grace flow, a `/healthz`
endpoint, request logging + global error shaping, OTP lockouts that survive
code re-issue, transactional refresh rotation, WS auth via first frame, and
scheduled cleanup jobs for expired tokens/OTPs/invitations.

## Board types

Boards follow the monday.com model. `main` boards are visible to every account
member; `private` and `shareable` boards are visible only to their board
members (plus account admins, so boards stay reachable when owners leave);
guests only ever see boards they were explicitly added to, and may only be
added to `shareable` ones. Every board has members with a role — `owner`
(manages members, settings, and the board type; the creator is the first
owner, and a board always keeps at least one), `member` (edits), and `viewer`
(read-only on that board). Ownership is limited to account admins/members.
Endpoints: `GET/POST /boards/:id/members`, `PATCH/DELETE
/boards/:id/members/:userId`, and `PATCH /boards/:id` with `{type}`. In the
app: the privacy picker on New Board, the Board members sheet (⋮ menu), and
Change board type for owners; restricted boards show a lock/link badge in
lists. Being added to a board notifies you in-app and by email.
