# Dayflow vs monday.com — Feature Gap Report

**Date:** 2026-09-12
**Scope compared:** monday.com Work Management (the core product) plus the platform features that ship with it (docs, forms, dashboards, automations, integrations, AI, admin/security). The separate monday products (CRM, Dev, Service) are listed once in §14 for completeness only.
**Dayflow snapshot:** `apps/api` (NestJS 11 + Drizzle, 71 REST operations across 12 controllers plus a WebSocket gateway, 24 tables) and `apps/mobile` (Flutter, ~27 screens). Every Dayflow status below was checked in source: `apps/api/src/db/schema/enums.ts`, `apps/api/src/modules/**/*.controller.ts`, `apps/api/src/modules/boards/column-values.ts`, `apps/mobile/lib/app/router.dart`, `apps/mobile/lib/features/**`, plus `README.md`, `PLAN.md` and `PRODUCTION_READINESS.md`.
**monday.com sources:** the pricing/plan matrix, the developer column-type reference, the 2026 monday AI overview, and current third-party feature guides (links in §18). Several `support.monday.com` articles refused automated fetches, so a few details from them are marked *(unverified)*.

Legend: ✅ Have · 🟡 Partial · ❌ Missing · ⏸ Deliberately out of scope (per `PLAN.md`)

> **Status update, 2026-09-12 (same day):** every P0 item in §16 has since been implemented and verified
> end to end (API unit tests, Flutter tests and the live-API e2e suite). Rows below that are now closed:
> saved views with filter/sort/hidden columns/conditional colours (§2, §4), multi-column sort, column
> reorder and hide, column summary footers, batch actions, board and item Archive + 30-day Trash with
> restore, board-level activity log with 7-day undo, board discussion, subitems with roll-up (§5),
> long text / email / phone / files / rating / item ID / creation log / last updated / auto number columns
> (§3), rich-text updates with mention autocomplete, emoji reactions and inline attachments (§6),
> move item to another board, board duplicate, save board as template (§2), assignable guest role and
> member deactivate/reactivate (§13). The tables are kept as the pre-P0 baseline for comparison; the
> P1–P3 backlog in §16 is unchanged.

---

## 1. Executive summary

Dayflow covers the **mobile core** of monday.com well: boards → groups → items → typed columns, four views, an item card with updates/files/activity, My Work, notifications, invites, board types with roles, and realtime sync. Against monday.com's full surface it is roughly **a third of the way**. The gaps cluster in six areas: table mechanics (sort/filter/saved views), item depth (subitems, dependencies, mirror, formula), automations, dashboards, integrations/API, and admin/security.

| Area | monday.com | Dayflow | Coverage |
|---|---|---|---|
| Board structure & templates | Workspaces, folders, 200+ templates, docs, dashboards | Workspaces + boards, 6 templates | 🟡 ~45% |
| Column types | 36 types (+ AI columns) | 12 types (10 editable on mobile) | 🟡 ~30% |
| Views | 13 view types, saved views, public share | 4 views, no saved views | 🟡 ~30% |
| Table mechanics (sort, group-by, summaries, coloring, batch, undo) | Full | Quick filter + quick find only | 🟡 ~20% |
| Item depth (subitems, dependencies, mirror, formula, time tracking) | Full | None | ❌ 0% |
| Updates & activity | Rich text, reactions, pins, email replies, undo | Plain text, threads, likes, bookmarks, item log | 🟡 ~50% |
| Dashboards & reporting | 50+ widgets, cross-board, PDF export | 5 fixed single-board widgets | 🟡 ~15% |
| Automations & workflows | 300+ recipes, custom builder, workflows | None | ❌ 0% |
| Integrations, API, apps | 200+ integrations, GraphQL, webhooks, marketplace, MCP | REST + Swagger (JWT sessions only) | 🟡 ~10% |
| Docs / Forms / Canvas / Portfolio / Resource mgmt | All present | None | ❌ 0% |
| AI (Sidekick, Agents, Vibe, AI columns) | Full suite | None (deferred to v1.1) | ⏸ 0% |
| Search & navigation | Boards, items, updates, files, docs, people, archives | Board + item names | 🟡 ~30% |
| My Work | Buckets, following, custom columns, calendar sync | Buckets, hide done, visible boards | 🟡 ~60% |
| Notifications | In-app, push, email + digests, granular settings | In-app + email; push toggle without delivery | 🟡 ~55% |
| Collaboration & user types | Admin/Member/Viewer/Guest, Teams, custom roles | Admin/Member/Viewer (guest enforced, not assignable), board roles | 🟡 ~55% |
| Permissions & security | 4 board levels, column/item/view permissions, SSO, 2FA, SCIM, audit log | Board type + board role only | 🟡 ~25% |
| Admin console | Users, teams, settings, usage, billing, apps, content directory, trash | Members, roles, invites, account deletion | 🟡 ~25% |
| Import / export | Excel/CSV import, Excel export with updates, migrations, PDF | CSV export only | 🟡 ~20% |
| Mobile-specific | Push, widgets, offline, biometrics, calendar sync, scan, audio | Deep links, dark theme, polling fallback | 🟡 ~30% |
| Personalization & platforms | 14 languages, themes, web, desktop, add-ons | Light/dark theme; Flutter web/desktop builds untested | 🟡 ~25% |

Coverage figures are judgement calls weighted by how much a typical monday.com team uses each feature, not a raw row count.

---

## 2. Board structure, workspaces, templates

| monday.com feature | Dayflow | Notes / evidence |
|---|---|---|
| Workspaces (create, rename, delete, description, icon/color) | 🟡 | Create + list only (`POST/GET /workspaces`). No rename, delete, icon, description. |
| Workspace folders & sub-folders | ❌ | No `folders` table. |
| Open vs closed workspaces, workspace owners | ❌ | No workspace-level membership or permissions. |
| Board types: Main / Shareable / Private | ✅ | `board_type` enum, `BoardAccessService`, privacy picker, lock badges; restricted boards return 404 rather than 403. |
| Board members with roles | ✅ | owner/member/viewer, last-owner rule, guests only on shareable boards. |
| Board description / info box | ✅ | `PATCH /boards/:id {description}`, Board info sheet. |
| Board owner(s), created-by | 🟡 | Owners tracked in `board_members` and shown crowned in the members sheet; no "created by" surface. |
| Favorites, recently visited | ✅ | `board_favorites`, `recent_visits`, Home carousel. |
| Board duplicate (structure / with items / with updates) | ❌ | No board duplicate endpoint. |
| Save board as account template | ❌ | `templates` table exists with no write path; README calls it reserved. |
| Template center (200+ templates, categories, preview, "used by N teams") | 🟡 | 6 hard-coded templates in `templates.catalog.ts` (blank, task management, content calendar, client projects, event management, requests & approvals), each seeding groups, columns and sample items. No categories, preview or usage counts. |
| Board archive | ✅ | `DELETE /boards/:id` sets `archived_at`. |
| Archive browser + restore, 30-day Trash + restore | ❌ | Nothing lists or restores archived boards/items. Groups and columns are hard-deleted. |
| Board permissions (Edit everything / Edit content / Edit assigned rows / View only) | 🟡 | Binary editor-vs-viewer via board role. No "edit content but not structure" or "assigned rows only". |
| Board subscribers / followers | 🟡 | `board_members.following` boolean exists but is never read or written. |
| Board activity log (board-wide, filterable, 7-day undo) | 🟡 | `activity_log` rows are written for 17 event types but only the last 50 item-scoped rows are shown, inside the item card. No board-level log, filters or undo. |
| Board discussion (board-level updates) | 🟡 | `updates.item_id` is nullable so the schema supports it; no endpoint or UI posts to a board. |
| Item default values | ❌ | |
| Required columns | ❌ | |
| Conditional coloring (cells / rows) | ❌ | |
| Column summary footers (sum, avg, status distribution) | ❌ | Only appear as dashboard number totals. |
| Collapse groups, group footers | 🟡 | Collapse yes; no footers. |
| Group by column (table view) | ❌ | Grouping is fixed to the board's groups. |
| Multi-column sort | ❌ | No sort anywhere on API or mobile. |
| Hide / show / reorder / resize columns | 🟡 | Width stored; "Manage columns" sheet renames/deletes. No hide, no column reorder in UI, no per-view column set. |
| Column descriptions | ❌ | |
| Zoom / row height | ❌ | |
| Batch actions (multi-select → status, move, archive, delete, duplicate, export) | ❌ | Single-item actions only. |
| Undo (7 days via activity log) | ❌ | Optimistic rollback exists, but no user-triggered undo. |
| Board / item permalinks & deep links | 🟡 | `dayflow:///invite/<token>` registered on Android and iOS; no board/item share links. |
| Public board/view sharing & embed | ❌ | |
| Server-side pagination / filtering of large boards | ❌ | `GET /boards/:id` returns every non-archived item. |

---

## 3. Column types

monday.com exposes 36 column types in its API (plus AI columns and the Status variants Label/Priority). Dayflow's `column_type` enum has 12, of which 10 have mobile editors.

| Column | Dayflow | Notes |
|---|---|---|
| Name (item title) | ✅ | Item `name`. |
| Status (+ Label, Priority variants, done-flag, label editor) | ✅ | Labels with `isDone`, editable in Column settings sheet; default Working on it / Done / Stuck. |
| People (+ Teams) | 🟡 | Users only; no team assignment. |
| Date (with optional time, reminders) | 🟡 | ISO date + optional `HH:MM`, real-calendar validation; no reminders. |
| Text | ✅ | ≤5000 chars. |
| Long text | ❌ | |
| Numbers (units, currency, formatting, summary functions) | 🟡 | Number only; no unit/format/aggregation settings. |
| Checkbox | ✅ | |
| Dropdown (multi-select, limits) | ✅ | Options with colors; single-select on mobile. |
| Tags (account-wide shared tag pool) | 🟡 | Per-column options, not shared across boards as monday tags are. |
| Timeline (start/end, milestone) | 🟡 | API validates `{from,to}`; mobile renders a read-only chip with no editor; no milestone flag. |
| Link | ✅ | http/https only, optional label. |
| Location | 🟡 | Address + optional lat/lng; mobile edits address only, no map or geocoding. |
| Vote | 🟡 | API-only; no mobile editor or chip. |
| Email | ❌ | |
| Phone | ❌ | |
| Files column | ❌ | Files attach to the item (Files tab), not to a column. |
| Rating | ❌ | |
| Hour | ❌ | |
| Week | ❌ | |
| World clock | ❌ | |
| Country | ❌ | |
| Color picker | ❌ | |
| Button (triggers automations) | ❌ | |
| Subitems | ❌ | See §5. |
| Dependency | ❌ | |
| Connect boards (board relation) | ❌ | |
| Mirror | ❌ | |
| Formula | ❌ | |
| Time tracking | ❌ | |
| Item ID | ❌ | |
| Auto number | ❌ | |
| Creation log | ❌ | `items.created_at` / `created_by` exist but are not exposed as a column. |
| Last updated | ❌ | `column_values.updated_at` exists per cell; not surfaced. |
| Progress tracking (weighted status roll-up) | ❌ | |
| monday doc column | ❌ | |
| AI columns / AI blocks (categorize, summarize, extract, translate, sentiment, write) | ⏸ | AI deferred to v1.1. |
| Managed columns (Enterprise, admin-locked label sets) | ❌ | |
| Column permissions (restrict edit / restrict view) | ❌ | |

---

## 4. Views

| View / capability | Dayflow | Notes |
|---|---|---|
| Main Table | ✅ | Editable table with inline add, drag reorder, collapsible groups. |
| List (condensed) | 🟡 | `view_type` enum includes `list`; README notes the mobile table already renders as a list and no distinct view was built. |
| Kanban (lane by any status/label column, card customization, swimlanes) | 🟡 | Lane column picker over status columns; drag between lanes. No card field selection, no swimlanes. |
| Calendar (day / week / month, drag to reschedule) | 🟡 | Month only over the board's first date column; no drag. |
| Timeline view | ❌ | Not in `view_type` enum. |
| Gantt (dependencies, baseline, critical path, milestones, drag) | ❌ | |
| Workload (capacity per person, Pro+) | ❌ | |
| Chart view (bar/line/pie/stacked, per-board) | 🟡 | One items-per-group bar chart lives in the Dashboard view only. |
| Form view (WorkForms) | ❌ | |
| Files view (gallery of all board files) | ❌ | Files are per item only. |
| Map view | ❌ | Location column exists but no map rendering. |
| Cards view | ❌ | |
| Doc view / app views from marketplace | ❌ | |
| Dashboard view (per-board widgets) | 🟡 | Fixed widget set, not configurable (see §7). |
| Saved views (named, per-board, with filter/sort/hidden columns) | ❌ | `board_views` rows are created by the seeder only; `config` is never written; no CRUD endpoints or UI. |
| Default view per board, view permissions / lock view | ❌ | |
| Share view publicly / embed | ❌ | |
| Quick filters (person, status, date presets) | 🟡 | Person + status label, client-side, non-persistent. No date presets (Today / This week). |
| Quick Find (filter items by name) | ✅ | |
| Advanced filter builder ("Where column condition value", AND/OR, saved) | ❌ | README lists as not built. |
| Sort | ❌ | |
| Filter by "Me" dynamic person | ❌ | |

---

## 5. Items, subitems and structure

| Feature | Dayflow | Notes |
|---|---|---|
| Create / rename / move within & between groups / duplicate / archive | ✅ | Fractional positioning, validated cells, 17 activity events. |
| Delete permanently vs archive, restore | 🟡 | `DELETE /items/:id` archives; no restore, no hard delete, no trash. |
| Move item to another board (with column mapping warning) | ❌ | `PLAN.md` phase 2 item, not built. |
| Subitems (up to 4 levels, own columns, roll-ups) | ❌ | No `parent_item_id`. |
| Dependencies (strict / flexible / no-action modes, lead-lag, batch) | ❌ | |
| Connect boards + mirror columns | ❌ | |
| Formula column (functions, references) | ❌ | |
| Time tracking (manual + automation start/stop) | ❌ | |
| Recurring items (via "every time period" automations) | ❌ | |
| Item card customization (which columns show, order, required-only toggle) | ❌ | Card shows all columns in column order. |
| Item default values, required columns | ❌ | |
| Item-level permissions (view items where assigned) | ❌ | |
| Item lock / protected items | ❌ | |
| Convert item ↔ subitem | ❌ | |
| Item ID, permalink, copy link | ❌ | |
| Item templates via automation | ❌ | |
| Item "info boxes" | ❌ | |

---

## 6. Updates, files and activity

| Feature | Dayflow | Notes |
|---|---|---|
| Updates per item, threaded replies | 🟡 | One level of replies (nesting rejected). |
| Rich text (bold, lists, links, headings, code) | ❌ | Body is stored as a `{type:'doc'}` JSON document ready for rich text, but only plain paragraphs are produced and rendered. |
| @mention people | 🟡 | `@Full Name` matched server-side against account members and notified; no autocomplete picker in the composer, no mention entity in the stored document. |
| @mention teams / "Everyone on this board" / "Everyone on this item" | ❌ | |
| Likes | ✅ | |
| Emoji reactions (multiple) | ❌ | Single like only. |
| Pin update | ❌ | |
| Bookmark update | ✅ | |
| Edit / delete update | ✅ | Admins can delete anyone's. |
| Attach files, images, GIFs, emojis in update | 🟡 | Files can be uploaded from the composer and attach to the update; no inline images in the body, no GIF/emoji picker. |
| Checklists inside updates | ❌ | |
| Audio notes, camera capture, document scan (mobile composer) | ⏸ | Deferred in `PLAN.md`. |
| Reply to update via email; per-item email address to post updates | ❌ | |
| Copy update / share update | ❌ | |
| Update permissions (who can post) | 🟡 | Guests and board viewers cannot post; no per-board setting. |
| Files: upload, preview images, delete | ✅ | 15MB cap, local disk (R2/S3 pending), allowlisted image types inline. |
| Files: versioning, annotate, gallery, Files column, cloud-drive pickers (Drive/Dropbox/Box/OneDrive) | ❌ | |
| File size limit per plan (500MB Pro+) | 🟡 | 15MB fixed. |
| Activity log per item | ✅ | Last 50 rows under the Columns tab. |
| Activity log per board with filters (type, person, date) and 7-day undo | ❌ | Rows exist; no board view, filters or undo. |
| Company-wide Update Feed with board filter, bookmarks | ✅ | |
| Following / subscribing to items and boards | ❌ | `update_on_subscribed` notification type exists but is never dispatched. |

---

## 7. Dashboards and reporting

| Feature | Dayflow | Notes |
|---|---|---|
| Per-board Dashboard view | 🟡 | `dashboard_screen.dart` renders stat tiles (items, done, overdue), status battery, items-per-group bar chart, number totals (sum and average), and "Coming up", all computed client-side in `dashboard_data.dart`. |
| Standalone cross-board dashboards (up to 50 boards on Enterprise) | ❌ | |
| Add / remove / resize / drag widgets; persisted layout | ❌ | Widget set is fixed; nothing is stored. |
| 50+ widgets (Battery, Chart, Numbers, Table, Gantt, Timeline, Calendar, Workload, Time tracking, Overview, Files gallery, Countdown, Llama farm, Leaderboard, To-do, Text, Quote, Playlist, YouTube, iFrame…) | 🟡 | 5 fixed equivalents. |
| Chart types (bar, stacked, line, pie, donut) with X/Y/group-by/benchmark settings | ❌ | |
| Dashboard-level filters and widget filters | ❌ | |
| Personal (private) dashboards, sharing and permissions | ❌ | |
| Export dashboard / widget to PDF, CSV, image; scheduled email PDF | ❌ | `PLAN.md` mentions a "scheduled PDF-export teaser" in the design. |
| Sidekick-generated dashboards | ⏸ | |

---

## 8. Automations and workflows

| Feature | Dayflow | Notes |
|---|---|---|
| Automation center with 300+ pre-built recipes | ❌ | No automations module anywhere; README lists automations as not built. |
| Custom automation builder (trigger → condition → actions) | ❌ | |
| Triggers: status change, column change, item created, date arrives, every time period, button clicked, person assigned, update posted, subitem changes, dependency changes | ❌ | |
| Actions: notify, assign, set status/date, create item/subitem/group, move to group/board, archive, duplicate, push dates, start/stop time tracking, send email, create board from template | ❌ | |
| Cross-board automations | ❌ | |
| Due-date reminders and custom notifications | ❌ | Only mention/assign/reply/invite notifications exist. |
| monday workflows (visual multi-step builder) | ❌ | |
| AI blocks inside automations, AI workflow builder | ⏸ | |
| Automation activity log, usage quotas per plan | ❌ | |

---

## 9. Integrations, API and extensibility

| Feature | Dayflow | Notes |
|---|---|---|
| 200+ native integrations (Slack, Teams, Zoom, Gmail, Outlook, Google Calendar, Drive, Dropbox, OneDrive, Jira, GitHub, GitLab, Salesforce, HubSpot, Zendesk, Mailchimp, Typeform, Shopify, DocuSign, Figma, Adobe CC, Toggl, Harvest…) | ❌ | The only outbound services are Resend (email) and Google ID-token verification. |
| Public API (GraphQL v2, rate limits per plan) | 🟡 | REST API with OpenAPI/Swagger exists (`packages/contracts/openapi.json`), but only for the app's own JWT sessions. No stable public contract, versioning policy or per-plan limits. |
| Personal / admin API tokens | ❌ | |
| Webhooks (item created, column change, status change…) | ❌ | Realtime WS exists for the app client only. |
| Apps framework & marketplace (board views, item views, widgets, integration recipes, doc blocks) | ❌ | |
| OAuth for third-party apps | ❌ | |
| Zapier / Make / Power Automate connectors | ❌ | |
| MCP server (lets external AI assistants read and act on workspace data) | ❌ | |
| Email-to-board (create items by emailing a board address) | ⏸ | Deferred in `PLAN.md`. |
| Gmail add-on, Outlook add-in, Chrome extension, Slack/Teams/Zoom apps | ❌ | |
| Calendar sync (Google/Outlook/iCal feed) | ❌ | |
| Import from Trello, Asana, Basecamp, Jira, Excel | ❌ | |

---

## 10. Docs, forms, canvas, portfolio, resource management

| Product / feature | Dayflow | Notes |
|---|---|---|
| Workdocs (real-time co-editing, live board/widget embeds, checklists, version history, comments, templates, export PDF) | ⏸ | Deferred in `PLAN.md`. |
| Doc column, doc view on boards | ❌ | |
| WorkForms (form view per board, conditional logic, branding, multi-page, prefill, anonymous share/embed, response → item) | ❌ | The "Requests & approvals" template is a plain board, not a form. |
| WorkCanvas (whiteboard, diagrams, mind maps) | ❌ | |
| Portfolio management (Enterprise) | ❌ | |
| Resource management / capacity planning (Enterprise) | ❌ | |
| Goals / OKRs | ❌ | |
| Sprints (monday dev) | ❌ | Separate product. |

---

## 11. AI

All ⏸ — `PLAN.md` explicitly defers the Sidekick assistant to v1.1 and notes the API should allow a board-context AI service to bolt on.

| Feature | Dayflow |
|---|---|
| Sidekick (chat assistant with board/doc context; creates boards, dashboards, subitems, columns; summarizes) | ⏸ |
| monday Agents (ready-made sales/IT/HR/marketing agents; custom agent builder) | ⏸ |
| Vibe (prompt-to-app builder; exports Word/PPT/Excel) | ⏸ |
| AI columns / AI blocks (categorize, summarize, extract, translate, sentiment, write, improve) | ⏸ |
| AI automations & AI workflow builder | ⏸ |
| AI Notetaker (meeting transcription → action items) | ⏸ |
| AI docs assistant | ⏸ |
| MCP connectivity for external assistants | ⏸ |

---

## 12. Search, navigation, My Work, notifications

| Feature | Dayflow | Notes |
|---|---|---|
| Search Everywhere: boards, items, updates, files, docs, people, dashboards, workspaces | 🟡 | `GET /search` matches board names/descriptions and item names only (ILIKE, prefix-ranked, limit 20). |
| Search filters (type, board, date, person), recent searches, include archived | ❌ | `PLAN.md` lists recent searches and show/hide archives; not built. |
| In-board search of updates | ❌ | |
| Keyboard shortcuts / command palette (web) | ❌ | Mobile-first; not applicable today. |
| Left sidebar with workspaces, folders, favorites, recents (web) | 🟡 | Home tab equivalents on mobile. |
| My Work: date buckets | ✅ | overdue / today / this week / later / no date / done. |
| My Work: hide done, visible boards filter | ✅ | |
| My Work: "Following" people filter | ❌ | `board_members.following` column exists, unused. |
| My Work: customize which date/status columns feed it per board | ❌ | Uses the first people, date and status column on each board. |
| My Work: quick item card, add to device calendar, My Calendar day view | ❌ | |
| Notification center tabs (All / Unread / Mentioned / Assigned) + search | ✅ | |
| Mark all read, mark one read | ✅ | |
| Notification types | 🟡 | 5 dispatched (mention, assigned, reply, board_invite, account_invite); `update_on_subscribed` is defined but never sent. Missing: status/date changes on followed items, due-date reminders, automation notifications, likes, team mentions. |
| Push notifications (FCM/APNs) | ❌ | Toggle exists; `device_tokens` table unused; no registration endpoint or sender; no Android 13 permission. |
| Email notifications | ✅ | Mention / assigned / reply / invites via Resend, respecting the email toggle. |
| Email digests / daily summary, reply-by-email | ❌ | |
| Granular per-event notification settings, quiet hours / DND | 🟡 | Only two toggles (push, email). |

---

## 13. Collaboration, users, permissions, security

| Feature | Dayflow | Notes |
|---|---|---|
| User types Admin / Member / Viewer / Guest | 🟡 | `account_role` has all four and the access service enforces guest rules, but `ASSIGNABLE_ROLES` in `members.controller.ts` excludes `guest`, so no one can actually be made a guest. |
| Viewers free & unlimited, guests limited to shareable boards | 🟡 | Enforced in code; no plan/seat model to make viewers "free". |
| Teams (create, assign to People column, @mention, team-level permissions) | ❌ | `teams` and `team_members` tables exist; no service, endpoint or UI uses them. |
| Custom roles (Enterprise) | ❌ | |
| Invite by email with role; pending invites; revoke | ✅ | Hashed tokens, replace-on-reinvite, deep link + hosted landing page. |
| Invite from People picker (add new email inline) | ❌ | `PLAN.md` design shows it. |
| Domain-based auto-join / approved sign-up domains | ❌ | |
| User profile (avatar, title, phone, location, timezone, birthday, skills) | 🟡 | Avatar, name, personal status, language field. |
| Personal status presets | ✅ | 7 presets. |
| Working status / out-of-office with dates | ❌ | |
| User directory / My Team screen | ✅ | Members screen. |
| Deactivate / reactivate user | 🟡 | `member_status.deactivated` exists; only remove is exposed. |
| Board permission levels (4) | 🟡 | See §2. |
| Column permissions, view permissions, item-level permissions | ❌ | |
| Private boards & docs (Pro+) | 🟡 | Private boards yes; no docs. |
| Google sign-in | 🟡 | API verifies ID tokens with audience check; mobile button waits on a client ID. |
| Apple sign-in | ❌ | `users.apple_sub` column exists; button shows "coming soon". |
| Email OTP + password login, multi-account, account switcher | ✅ | Beyond monday's default; monday uses password / magic link / SSO. |
| Two-factor authentication (all plans) | ❌ | |
| SAML SSO (Okta, Azure AD, OneLogin, custom) | ❌ | |
| SCIM provisioning | ❌ | |
| IP restrictions | ❌ | |
| Session management (list/force-logout devices, session duration policy) | 🟡 | Refresh-token families, user-agent recorded, revoke-all on password change; no device list UI. |
| Password policy configuration | ❌ | |
| Account-wide security audit log (logins, role changes, exports; exportable) | ❌ | `activity_log` records content changes only. |
| Panic mode (instant account lockdown) | ❌ | |
| Compliance: SOC 2, ISO 27001, GDPR DPA, HIPAA BAA, data residency (US/EU/AU) | ❌ | Not applicable yet; no certifications or region choice. |
| Login-with-QR / device linking | ⏸ | Deferred in `PLAN.md`. |

---

## 14. Admin console, billing, import/export, personalization, platforms

| Feature | Dayflow | Notes |
|---|---|---|
| Manage users (filters by role/status/team, bulk actions, pending invites) | 🟡 | List, invite, change role, remove, revoke, last-admin guard. No filters or bulk actions. |
| Manage teams | ❌ | |
| General settings (account name, logo/branding, custom URL slug, date format, first day of week, timezone, work week) | ❌ | `accounts.logo_url` and `slug` exist in schema only. |
| Usage stats, storage usage | ❌ | |
| Billing & plan management, seat counts, free trial | ❌ | No plans/tiers concept at all. |
| Apps management (install, approve, permissions) | ❌ | |
| Content directory (all boards/docs/dashboards with owners) | ❌ | |
| Archive & Trash management with restore | ❌ | |
| Account templates management | ❌ | |
| Security & compliance center | ❌ | |
| Account deletion with 30-day grace | ✅ | Schedule / cancel UI + nightly purge cron. |
| Feedback and support center | ✅ | FAQ accordion + contact form persisted to the `feedback` table. |
| Excel / CSV import to a new board (column mapping) | ❌ | |
| Import items into an existing board | ❌ | |
| Export board to Excel (with updates, with subitems), batch export | 🟡 | CSV of cells only, via `GET /boards/:id/export.csv` or clipboard in-app. |
| Export account data (Enterprise), dashboard PDF | ❌ | |
| Themes: light / dark / night / system | 🟡 | Light + dark themes exist (`dayflowDarkTheme`) following the system setting; no in-app toggle, no night theme. |
| Languages (14+ incl. ES, PT, FR, DE, JA, KO, ZH, RU, NL, SV, TR, PL) | ❌ | English only. `user_profiles.language` is stored and editable but nothing localizes; `flutter_localizations` not wired. Designs include full Chinese strings. |
| Date / time format, week start preferences | ❌ | |
| Web app | 🟡 | Flutter web build compiles per README, but there is no desktop-optimized layout (sidebar, wide multi-column table). |
| Desktop apps (Windows / macOS) | 🟡 | Flutter desktop targets exist; untested and unpackaged. |
| Coach-marks tour, intro tutorial, knowledge base | 🟡 | Setup checklist and FAQ exist; guided tour not built. |
| Separate products: monday CRM, monday dev, monday service | ❌ | Out of scope for a Work Management clone. |

---

## 15. Mobile-specific comparison

The monday.com mobile app is the closest like-for-like comparison since Dayflow is mobile-first.

| monday mobile feature | Dayflow | Notes |
|---|---|---|
| Table, Kanban, Calendar views | ✅ | |
| Cards, Chart, Timeline, Gantt (read-only), Files, Form views on mobile | ❌ | |
| Dashboards on mobile (mobile-optimized widgets) | 🟡 | Fixed per-board dashboard. |
| Workdocs on mobile | ❌ | |
| Push notifications with deep link into item | ❌ | In-app tap navigates to the item; no push. |
| iOS calendar sync for My Work | ❌ | |
| Home-screen widgets (My Work, notifications) | ⏸ | Deferred. |
| Biometric / passcode app lock | ❌ | |
| Offline read cache and queued edits | ❌ | Memory-only providers; README: offline-first deliberately skipped. |
| Share sheet → create item / attach file | ❌ | |
| Camera / photo / voice note / document scan in composer | ⏸ | Deferred. |
| Board and item deep links (universal links) | 🟡 | `dayflow://` scheme registered on both platforms for invites only. |
| Tablet / iPad adaptive layout | ❌ | Phone layout only; `PLAN.md` promised rail navigation on tablets. |
| Realtime updates | 🟡 | WS live on long-running hosts; 25s polling fallback with banner on serverless. |
| Optimistic editing with rollback | ✅ | Parity or better. |
| Motion / haptics polish | ✅ | Vibe motion tokens ported. |

---

## 16. Prioritized backlog

Ordered by how much each closes the gap for a typical monday.com team, and by dependency (later items build on earlier ones).

**P0 — Board parity (a monday user notices these in the first hour)**
1. Saved views: CRUD on `board_views` with filter/sort/hidden-column config; default view per board.
2. Sort (multi-column) and an advanced filter builder with AND/OR, date presets and dynamic "Me"; server-side filter params on `GET /boards/:id`.
3. Hide / reorder columns; column summary footers; conditional coloring.
4. Subitems (one level first) with roll-up summary.
5. Everyday columns: Long text, Email, Phone, Files, Rating, Item ID, Creation log, Last updated, Auto number; mobile editors for Timeline and Vote.
6. Rich-text update bodies, mention autocomplete, emoji reactions, inline attachments, "Everyone on this board".
7. Board-level activity log with filters and 7-day undo; board discussion.
8. Archive/Trash browser with restore for boards and items; permanent delete.
9. Batch actions (multi-select) on items.
10. Move item to another board; board duplicate; save board as template.
11. Make the guest role assignable (one-line change in `members.controller.ts`) and expose deactivate/reactivate.

**P1 — Team parity**
12. Automations: a recipe engine with the top ~20 monday recipes (status → notify/assign/move, date arrives → notify, item created → assign/set status, every period → create item, status → archive) and a custom builder.
13. Timeline and Gantt views with a Dependency column (strict/flexible modes).
14. Configurable dashboards: widget CRUD, cross-board widgets, chart types, dashboard filters, PDF export.
15. Connect boards + Mirror, Formula, Time tracking, Progress tracking columns.
16. Teams (tables already exist): team assignment in People column, team mentions, team permissions.
17. Full board permission levels (edit content / edit assigned rows / view only), column permissions.
18. Push notifications (FCM/APNs), item following, granular notification settings, digests, reply-by-email.
19. Search Everywhere across updates, files and people; filters; recent searches; include archived.
20. Excel/CSV import with column mapping; Excel export with updates and subitems.
21. Google + Apple sign-in, 2FA.
22. Workspace management (rename, delete, folders, open/closed, owners).
23. i18n scaffold and at least ES + ZH (the designs already ship Chinese strings).

**P2 — Platform & enterprise**
24. Public API contract with personal/admin API tokens, versioning, rate limits; webhooks.
25. Integrations, starting with Slack, Google Calendar/Outlook sync, Gmail/Outlook item creation, GitHub/Jira; Zapier/Make connector.
26. WorkForms-style form view (public share, response → item).
27. Workdocs (real-time editor with board embeds) and doc column.
28. SAML SSO, SCIM, IP restrictions, session management UI, security audit log, password policy, panic mode.
29. Admin console: general settings (branding, date format, week start, timezone), usage stats, content directory, apps management, billing/plans.
30. Workload view and resource management; portfolio.
31. Desktop/web layout (sidebar, wide table) and packaged desktop builds; tablet layout.

**P3 — Differentiators / v1.1 as planned**
32. Sidekick-style assistant, AI columns, AI automations, MCP endpoint.
33. Canvas/whiteboard, agents, prompt-to-app builder.
34. Mobile extras: home-screen widgets, biometric lock, offline queue, share sheet, voice notes, document scan, QR login.

---

## 17. What Dayflow does that is at parity or ahead

Stated so the report is not read as "nothing works":

- The board type model (main / shareable / private, guest rules, last-owner rule) is a faithful implementation of monday's rules and is enforced on every write path, with 404-not-403 to avoid leaking board existence.
- Column value validation is stricter than monday's mobile client (real-calendar date checks, canonical shapes, server-side normalisation, http/https-only links).
- Email OTP login with a multi-account picker and rotating refresh tokens with reuse detection is a stronger default auth story than monday's password login for a mobile-first product.
- Realtime fan-out excludes the actor so optimistic updates never echo, with a visible degraded-mode banner and polling fallback on hosts without WebSockets.
- Motion system ported from monday's Vibe design tokens, with a dark theme from day one.
- Account deletion with a 30-day grace period and a purge job is implemented end to end.
- Update bodies are already stored as a structured document, so rich text is an editor/renderer change rather than a schema migration.

---

## 18. Sources

monday.com
- Pricing and plan feature matrix: https://monday.com/pricing
- Column types reference (36 API types): https://developer.monday.com/api-reference/reference/column-types-reference
- Available column types (support; refused automated fetch, list cross-checked against the developer reference): https://support.monday.com/hc/en-us/articles/115005310285-Available-column-types-on-monday-com
- The board views (support; refused fetch): https://support.monday.com/hc/en-us/articles/360001267945-The-board-views
- Gantt view and widget (support; refused fetch): https://support.monday.com/hc/en-us/articles/360015643840-The-Gantt-Chart-View-and-Widget
- Dependencies: https://support.monday.com/hc/en-us/articles/360007402599-Dependencies-on-monday-com
- Multiple levels of subitems: https://support.monday.com/hc/en-us/articles/29810815287570-Multiple-levels-of-subitems-on-monday-com
- Board permissions: https://support.monday.com/hc/en-us/articles/115005315809-Board-permissions and on Enterprise: https://support.monday.com/hc/en-us/articles/31152393208466-Board-permissions-on-Enterprise
- Column permissions: https://support.monday.com/hc/en-us/articles/360011926640-Column-permissions
- Conditional coloring: https://support.monday.com/hc/en-us/articles/360015468399-Conditional-Coloring
- Required columns: https://support.monday.com/hc/en-us/articles/27560733058706-Required-columns
- Item default value: https://support.monday.com/hc/en-us/articles/4409205384338-Item-default-value
- Batch actions: https://support.monday.com/hc/en-us/articles/115005335049-Batch-Actions
- How to undo: https://support.monday.com/hc/en-us/articles/360011810600-How-to-undo-something
- Export to Excel: https://support.monday.com/hc/en-us/articles/26989749858578-Export-from-monday-to-Excel
- Automation and integration actions: https://support.monday.com/hc/en-us/articles/360017556179-Automation-and-Integration-actions
- Workdocs: https://support.monday.com/hc/en-us/articles/360021702939-Get-started-with-monday-workdocs
- WorkForms launch: https://monday.com/blog/product/workforms-launch-monday-workdocs-version-history-and-other-improved-features/
- Everything monday AI can do in 2026: https://monday.com/blog/ai-agents/everything-monday-ai-can-do/
- Mobile apps (support): https://support.monday.com/hc/en-us/articles/115005317225-monday-com-mobile-apps-iPhone-iPad-tablet-and-Android and mobile board views: https://support.monday.com/hc/en-us/articles/360015740220-Mobile-app-board-views
- Secure configuration checklist: https://support.monday.com/hc/en-us/articles/34336185460498-monday-com-secure-configuration-checklist
- Dashboards guide (widgets, boards per plan): https://www.cloudwards.net/monday-com-dashboards/
- Enterprise permissions deep dive: https://www.fruitionservices.io/post/mondaycom-enterprise-permissions
- Integrations overview (200+, GraphQL, webhooks): https://www.oneio.cloud/blog/monday-com-integrations
- Pricing explainers: https://get-alfred.ai/blog/monday-pricing and https://costbench.com/software/project-management/monday/

Dayflow
- `README.md` ("What works today", "Not built yet"), `PRODUCTION_READINESS.md`, `PLAN.md` §2 feature inventory and "Deferred to v1.1+"
- `apps/api/src/db/schema/enums.ts` and the other schema files
- `apps/api/src/modules/*/*.controller.ts`, `apps/api/src/modules/boards/column-values.ts`, `apps/api/src/modules/boards/templates.catalog.ts`, `apps/api/src/modules/realtime/realtime.gateway.ts`, `apps/api/src/modules/access/board-access.service.ts`
- `apps/mobile/lib/app/router.dart`, `apps/mobile/lib/features/**`, `apps/mobile/android/app/src/main/AndroidManifest.xml`, `apps/mobile/ios/Runner/Info.plist`
