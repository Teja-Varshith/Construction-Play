# Chennapatanam (BuildTrack)

Construction CRM whose main user is the **CEO**: one place to see every project's progress, delays and money.
Flutter (web, Android, iOS) + Firebase (Auth email/password, Firestore, Storage). Project `cptmn-dd372`.
State: Riverpod 3. Routing: go_router with role guards (`lib/core/router`). The full product plan is in
`build_plan_text.txt` (text of `BuildTrack Build Plan.pdf`).

## Roles
- **CEO** – lands on the portfolio dashboard (`CeoPortfolioScreen`), reads everything, approves expenses.
- **Admin** (office) – creates users/projects, settings, budgets, can void expenses, loads demo data.
- **Manager** – edits their own projects (phases, budget, expenses). **Supervisor** – daily reports, issues, documents.
- Managers, supervisors and staff land on **My day** (`lib/features/home/`): tasks computed by `MyDay.forProject`
  from their projects' records (today's report, backfill, assigned issues, indents to approve, late deliveries,
  low stock, late phases without a reason, unbooked deliveries, rejected expenses), each with one action, plus
  quick actions (daily report, issue, material, expense). New recurring job for site staff = add a `DayTask` there.
  Managers reach the portfolio tracker at `/portfolio`. The CEO home starts with `_LeaderBrief` (decisions waiting,
  top risks) above the portfolio.
- Principle: the app must save site staff time. Pre-fill from the last entry, default sensibly, keep the day's main
  action one tap away on phones, and show people what to do rather than charts to interpret.
- Managers/supervisors only see projects whose `memberIds` contain them; their queries must filter on it.

## Core data (Firestore)
- `projects/{pid}` – project; `stage` + `statusIndex` mirror the status config (rules check them). `holdPeriods` pause the schedule clock.
  - `phases/{id}` – name, order, weight, plannedStart/End, actualPct, `budgetPaise`, `delayReason`.
  - `dprs/{YYYY-MM-DD}` – daily progress report (id is the date, needs ≥1 photo, backdate window).
  - `issues/{id}`, `documents/{id}`, and `*/revisions/*` history docs.
  - `budget/{categoryId}` – planned amount per expense category, with revision history.
  - `indents/{id}` – material requests: `pending → approved|rejected`, `approved → received|closed`.
    Approved by the project manager or CEO/admin (rules enforce it); the requester can withdraw a pending one
    (soft delete). `grns/{id}` – goods received (vendor, rates). Several GRNs can fill one indent (part
    deliveries); the one that completes it marks it `received`. `closed` = closed short with a `closeNote`.
    `materialIssues/{id}` – stock issued to the work. Stock = GRN qty − issued qty, never stored
    (`InventorySummary`, `lib/features/inventory/`). Also derived there: received-per-indent, on order,
    days of stock left (last 14 days of issues), average/last rate, stock value, material used by phase.
    A GRN can be booked as an expense (`expenses.grnId`, via `ExpenseDraft` in the expense editor).
- `expenses/{id}` – top-level; `projectId`, optional `phaseId`, `categoryId`, amount, status
  `pending|approved|rejected|void`. Only **approved** counts as spent.
- `config/*` – company settings, lists (statuses, categories, priorities...), phase templates, custom fields.
- `activity/{id}` – audit trail, written in the same batch/transaction as the change.

## Rules of the codebase
- Money is integer **paise** (`Money` in `core/utils/money.dart`). Never doubles for amounts.
- Dates for daily things are `YYYY-MM-DD` work-day keys in company time (`WorkDay`).
- **No Cloud Functions.** Every total/health/forecast is recomputed from source at read time
  (`ProjectAnalysis`, `ProjectInsight`, `FinanceSummary`), never stored and incremented.
- `firestore.rules` is the only server-side guard (approval state machine, audit stamps, soft deletes). When you
  add a field to a written document, check the rule's `changedOnly([...])` / validation lists.
- Nothing is hard-deleted: `deleted: true` or archive. Config items are archived, ids never change.
- Every write stamps `auditCreate/auditUpdate` and adds an `ActivityEntry`.
- Optimistic concurrency via `revision` (rules require `revision == old + 1`).

## Where things are
- `lib/features/projects/domain/project_analysis.dart` – planned vs actual %, days behind, health.
- `lib/features/projects/domain/project_insight.dart` – per-phase status/budget, delay factors, forecast finish.
- `lib/features/projects/presentation/ceo_portfolio_screen.dart` – CEO home + project list.
- `lib/features/projects/presentation/project_dashboard.dart` – project Overview tab.
- `lib/features/finance/` – expenses, budgets, approvals, `FinanceSummary`.
- `lib/features/projects/presentation/insight_charts.dart` – fl_chart donut / plan-vs-actual bars / spend curve.
- `lib/features/demo/` – demo portfolio + one demo login per role (Settings → Demo data, admin only).
  Password `Demo@2026`; accounts in `demo_accounts.dart`. The login page always shows one-tap demo sign-in
  buttons (user's choice). Removing demo data archives demo projects and deactivates demo logins.

## Delay tracking & drill-down framework
- Every problem is a `ProjectFactor` (in `ProjectInsight.calculate`) with a `ProjectLink` (`domain/project_nav.dart`):
  a tab plus a focus string, and an `action` label. New kinds of delay = add a factor with a link; nothing else.
- Project screen is URL-driven: `/projects/:id?tab=<slug>&focus=<focus>` (`ProjectLink.path`). Inside the screen,
  `openProjectLink()` switches tab in place via `ProjectNavScope` (`presentation/project_nav_scope.dart`).
- Each tab reads `ProjectNavScope.focusFor(tab)` and applies it once per `seq` (filters, `FocusHighlight` scroll +
  outline). Focus values: timeline `phase:<id>`; reports `missing`|`output`; issues `urgent`|`open`|`issue:<id>`;
  money `pending`|`payables`|`phase:<id>`|`overspend`; materials `pending`|`late`|`low`|`unbooked`|`indent:<id>`|`phase:<id>`;
  issues also `phase:<id>`; info `holds`. Daily progress slug is `daily`; `reports` is PDF report generation.
- Three headline measures per project: cost overrun (spent − budget × % done), payables (approved, unpaid
  expenses; overdue after 30 days) and speed (% per week vs % per week needed).
- CEO dashboard "Delay & risk watchlist" lists every factor across projects; tracker "Main factor" also deep-links.
- Materials factors: late deliveries, indents stuck in approval, and materials about to run out with nothing
  ordered (`materials low`).
- Rules have a 1000-expression budget per request: in multi-branch `allow update` rules, test the cheap status
  transition first and the role functions last (see `indents`).

## UI conventions
- Chairman/CEO wording comes from `PlainProject` (`presentation/project_plain.dart`): one verdict (At risk / Needs
  attention / On track; "at risk" only for serious time or money problems), progress ("50% built · should be 54% by
  now"), and time / money / bills sentences. Home tiles, the project summary and the sidebar all use it, so they never
  disagree. Prefer sentences over metric jargon (no "cost overrun", "%/wk" on the CEO's first screens).
- Clean, flat, rounded surfaces (`AppRadius`, `AppColors.line`, `appSoftShadow` in `app_theme.dart`); no NeoPop.
- `HoverCard` / `NeoMetricCard` / `StageTile` in `ceo_ui.dart` are the shared card primitives.
- Status colours (`context.statusColors`) only mean ok/warn/bad and always come with a text label.

## Working agreements
- Don't write tests; the user builds features and runs tests themselves.
- Run `flutter analyze` after changes.
