---
title: Goaly — Lovable Implementation Plan
status: Draft
version: 0.1
date: 2026-05-11
stack:
  frontend: React 18 + Vite + TypeScript
  routing: TanStack Router
  data: TanStack Query
  backend: Supabase (Postgres + Auth + RLS + Realtime + Storage)
  ai: Lovable AI (custom actions/tools wired to Supabase)
  hosting: Lovable
tenancy: multi-workspace, multi-user per workspace
source_of_truth: Supabase (notion-mirror markdown becomes optional export)
ports_from: .claude/skills/* (each SKILL.md becomes one or more AI actions + UI route)
---

# Goaly — Lovable Implementation Plan

Port of the Goaly Claude Code skill suite into a standalone web app. Preserves the goal → KPI → project → task hierarchy, the impact/ikigai prioritization model, and the pattern-detection intelligence, while removing the dependency on a local terminal + Claude Code harness.

## Table of Contents

1. [Overview & Goals](#overview--goals)
2. [Architecture Decisions](#architecture-decisions)
3. [Data Model](#data-model)
4. [Multi-Tenant RLS Strategy](#multi-tenant-rls-strategy)
5. [Lovable AI Integration](#lovable-ai-integration)
6. [Intake Form — Workspace Bootstrap](#intake-form--workspace-bootstrap)
7. [Phase 1 — MVP Core Loop](#phase-1--mvp-core-loop)
8. [Phase 2 — Intelligence & Integrations](#phase-2--intelligence--integrations)
9. [Open Questions](#open-questions)
10. [Appendix A — Algorithms & Rules (Executable Spec)](#appendix-a--algorithms--rules-executable-spec)

> **Spec authority:** Where the body of this doc and Appendix A disagree on a number, threshold, formula, or rule, **Appendix A wins**. The body is sequencing and architecture; the appendix is the contract the code must satisfy.

---

## Overview & Goals

**What we are building:** A web app where each user (or team) gets a workspace containing goals, KPIs, projects, tasks, clients, and interactions. A weekly Mission dashboard surfaces a traffic-light KPI scorecard, ranks tasks by impact, and runs pattern detectors (frog tasks, killed mammoth, spear-sharpening). A coaching agenda module and a CEO scope-review module mirror the existing skills.

**What we are explicitly NOT porting in v1:**
- The `notion-mirror/` markdown-as-SoT model — Supabase is the source of truth, with optional export
- The Granola / qmd / gog / branded-PDF integrations — replaced by direct OAuth integrations later
- The Claude Code harness — replaced by Lovable's embedded AI with custom actions

**Success criteria for v1:**
- A new user can complete the intake form in under 5 minutes and land on a populated dashboard
- The Mission view loads in under 2 seconds with 500 entities in the workspace
- The Lovable AI assistant can create/update tasks, KPIs, and goals via natural language, respecting all validation rules
- RLS is enforced at the database layer — no client-side filtering for tenancy

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tenancy model | Workspace as tenant boundary, users join multiple workspaces via memberships | Mirrors how the Claude Code version implicitly handles one operator |
| RLS enforcement | All policies derived from `is_workspace_member(workspace_id)` helper | Single source of policy logic, easy to audit |
| Routing | TanStack Router (file-based) | Type-safe params + search-state for filter URLs |
| Data fetching | TanStack Query with Supabase client | Cache invalidation per entity, optimistic mutations |
| Real-time | Supabase Realtime channels on `tasks`, `kpis`, `interactions` | Live dashboard updates for multi-user workspaces |
| AI orchestration | Lovable AI actions (declared functions) call Supabase via service role from edge functions | Keeps prompts + business logic server-side, RLS still enforced by passing user JWT |
| Validation | Zod schemas shared between forms, AI actions, and edge functions | Single definition for SMART/ikigai/impact rules |
| Styling | Tailwind + shadcn/ui (Lovable default) | Speed; matches Lovable's generated patterns |

---

## Data Model

Core entities (all rows have `workspace_id uuid not null`, `created_at`, `updated_at`, `created_by uuid`):

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `workspaces` | `id`, `name`, `owner_id` | One per tenant |
| `workspace_members` | `workspace_id`, `user_id`, `role` (`owner`/`admin`/`member`) | Bridge table |
| `profiles` | `user_id`, `display_name`, `working_style jsonb`, `ikigai jsonb` | Extends `auth.users` |
| `goals` | `title`, `status`, `area text[]`, `horizon`, `lifecycle` | Status enum mirrors Goaly |
| `kpis` | `goal_id`, `title`, `current_value`, `target_value`, `unit`, `confidence`, `tracking_frequency`, `deadline`, `lifecycle` | Computed `progress` and `gap` as generated columns |
| `projects` | `title`, `status`, `area text[]`, `horizon`, `goal_id`, `definition_of_done` | DoD required by validation |
| `tasks` | `title`, `status`, `project_id` (required), `goal_id`, `kpi_id`, `energy`, `impact`, `timeframe`, `due_date`, `parent_task_id`, `ikigai_score jsonb`, `coaching_accountability jsonb` | `impact` auto-set if `kpi_id` not null |
| `personal_tasks` | Mirror of `tasks` minus `project_id` requirement | Separate table to keep filters clean |
| `clients` | `name`, `status`, `rate`, `monthly_revenue_estimate` | For portfolio-concentration detector |
| `contacts` | `client_id`, `name`, `role`, `email`, `notes` | |
| `interactions` | `client_id`, `type` (`meeting`/`email`/`call`), `occurred_at`, `summary`, `transcript_ref` | Used by killed-mammoth detector |
| `brainstorms` | `title`, `status`, `category`, `client_id`, `project_id` | |
| `run_logs` | `module` (`mission`/`coaching`/`review`), `mode`, `payload jsonb`, `run_at` | Powers meta-KPI charts |
| `note_sources` | `provider` (`notion`/`obsidian`/`upload`), `oauth_token_ref`, `last_synced_at`, `config jsonb` | Phase 2 |
| `note_blobs` | `source_id`, `source_ref`, `raw_markdown`, `embedding vector(1024)` | Phase 2 — needs pgvector |
| `extraction_suggestions` | `source_blob_id`, `entity_type`, `payload jsonb`, `status` (`pending`/`accepted`/`rejected`), `confidence` | Phase 2 — review queue |
| `ai_action_audit` | `actor_user_id`, `action_name`, `args jsonb`, `result jsonb`, `error` | Debug surface for AI calls |

Enums match Goaly conventions: task `status` (`Not started`/`Planned this week`/`In progress`/`Done This Week`/`Done`/`Deprioritized`), `energy` (`Deep Work`/`Quick Win`/`Admin`/`Waiting On`/`Research`), `impact` (`Needle Mover`/`Supporting`/`Maintenance`).

---

## Multi-Tenant RLS Strategy

**Pattern: every workspace-owned table uses the same four policies, derived from one helper function.**

```sql
-- Helper: is the authenticated user a member of this workspace?
create function is_workspace_member(w uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from workspace_members
    where workspace_id = w and user_id = auth.uid()
  );
$$;

-- Applied to every workspace-scoped table:
alter table tasks enable row level security;

create policy "members read"   on tasks for select using (is_workspace_member(workspace_id));
create policy "members insert" on tasks for insert with check (is_workspace_member(workspace_id));
create policy "members update" on tasks for update using (is_workspace_member(workspace_id));
create policy "members delete" on tasks for delete using (is_workspace_member(workspace_id));
```

**Special cases:**
- `workspaces` — select if `owner_id = auth.uid()` OR member; only owners can delete
- `workspace_members` — owners/admins can insert/delete; members can select
- `profiles` — users can only select/update their own row
- `ai_action_audit` — only the actor can read their own rows

**RLS test plan (Phase 1 exit criteria):**
- Automated test: User A in workspace W1 cannot select/insert/update/delete any row in workspace W2 via the Supabase JS client, even with crafted payloads
- Manual test: Confirm AI actions invoked by User A only operate on rows visible to User A (edge function uses user JWT, not service role, for entity ops)

---

## Lovable AI Integration

Lovable's embedded AI assistant is wired with custom actions (declared functions) that the AI calls in response to user prompts. Each action is a typed contract: name, JSON schema for args, server-side handler that calls Supabase under the user's JWT.

**Action catalog (Phase 1):**

| Action | Args | What it does |
|--------|------|--------------|
| `create_goal` | title, area?, horizon? | Inserts goal, enforces "must be tied to at least one KPI" by prompting follow-up |
| `create_kpi` | goal_id, title, current, target, unit, deadline, frequency | Full SMART validation; rejects if any field missing |
| `create_project` | title, goal_id, horizon, definition_of_done | Requires DoD |
| `create_task` | title, project_id, energy, impact?, timeframe?, due_date? | Auto-classifies impact if kpi_id supplied; runs ikigai scoring |
| `update_kpi_value` | kpi_id, new_value | Edits `current_value` only; logs to run audit |
| `update_task_status` | task_id, status | Triggers cleanup automation when set to `Done This Week` |
| `score_against_ikigai` | text | Returns 4-dim score with reasoning (read-only) |
| `rank_tasks_for_week` | workspace_id | Returns scored candidate list (10-pt scale from `/mission` Step 9) |
| `detect_patterns` | workspace_id | Returns flags from the 6-detector matrix |
| `prep_coaching_agenda` | workspace_id, coach_name? | Builds full agenda; surfaces frogs + standing items |
| `challenge_plan` | plan_text, posture | CEO review — 3 postures, never writes |

**System prompt for the assistant:**
Baked into Lovable's AI config. Establishes:
- The hierarchy (Goal → KPI → Project → Task) and that creation MUST cascade up
- SMART enforcement rules for KPIs
- Impact + ikigai classification for every task
- "Tables not prose" formatting
- Ask clarifying questions before creating ambiguous entities (do not guess)

**Confirmation rules:**
- Reads and single-entity creates: no confirm
- Bulk operations (e.g., archive 12 Done tasks): confirm
- Status changes that affect ranking: confirm
- Deletes: always confirm

**Why this matters:** the AI replaces the Claude Code skill orchestration but preserves the same business rules. A user typing "add a task to call BigCorp tomorrow" should end up with the same row as if `/goaly-mission` had created it — Project link, Energy, Impact, ikigai score, all populated.

---

## Intake Form — Workspace Bootstrap

Mirrors `/goaly-setup` but as a 5-step web wizard. Lives at `/intake` and is forced for any authenticated user with zero workspaces.

**Step 1 — Identity & Workspace**
- Workspace name (default: `<First Name>'s Workspace`)
- Your role (free text)
- Company / org name (optional)
- Submit → creates `workspace` + `workspace_members` row (`owner`) + `profile` row

**Step 2 — Strategic Goals (1-5)**
- Repeating field: Title + one-sentence description
- Optional: area (multi-select from Finance/Marketing/Product/Operations/Health/Personal Growth)
- Optional: horizon (This Quarter / This Year / Multi-Year)
- Submit → inserts goals

**Step 3 — KPIs (1 per goal, prompted)**
For each goal, ask: "How will you measure progress on '<Goal>'?"
- Metric name (required)
- Current value (required, number)
- Target value (required, number)
- Unit (required — EUR / Count / Percent / Hours / Score / Other)
- Deadline (required, date)
- Tracking frequency (Weekly / Monthly / Quarterly)
- Validation: full SMART check before save
- Submit → inserts KPIs linked to goals

**Step 4 — Clients & Projects**
- Repeating field: project name + type (Client / Internal) + one-line description
- For client projects: also capture client name, monthly revenue estimate, status
- For each project, auto-generate 2-3 starter tasks ("Define scope for X", "Schedule kickoff for X", "Set up tracking for X")
- Submit → inserts clients (where applicable) + projects + starter tasks

**Step 5 — Working Style**
Three single-select questions:
- Deep work capacity per day (1-2h / 2-4h / 4-6h / 6+h)
- Structure preference (Structured / Flexible)
- Best time for deep work (Morning / Afternoon / Evening)
- Submit → updates `profiles.working_style`

**Post-intake:**
- Redirect to `/dashboard` (Mission view)
- Insert a `run_logs` entry: `{module: 'intake', completed_at: ...}`
- Show first-run tooltip pointing at the AI assistant: *"Type a task in natural language to add it instantly."*

**Idempotency:** If the user revisits `/intake` with existing data, show "Restart from scratch" (destructive — confirm) vs "Edit current setup" (links to settings).

---

## Phase 1 — MVP Core Loop

Goal: a single user can sign up, complete intake, see a populated Mission dashboard, manage entities, and use the AI assistant for natural-language CRUD. Multi-tenant + RLS verified.

### Infrastructure
- [ ] Provision Supabase project; enable Auth (email + Google + GitHub)
- [ ] Create initial migration: enums, helper functions, all Phase 1 tables
- [ ] Write `is_workspace_member()` helper + apply RLS policies to every workspace-scoped table
- [ ] Seed migration for default options (areas, energies, impacts, statuses) where stored in lookup tables
- [ ] Wire Supabase types codegen into the Vite build (`supabase gen types typescript`)
- [ ] Set up TanStack Query client with Supabase auth-aware fetcher
- [ ] Set up TanStack Router with file-based routing and auth guard

### RLS Verification
- [ ] Write `tests/rls.test.ts` — programmatic check that User A cannot read/write any row in Workspace B for every table
- [ ] Add CI step that runs the RLS suite against a throwaway Supabase project
- [ ] Document the "every new table needs the 4 policies" checklist in repo

### Auth & Workspaces
- [ ] Sign-up / sign-in pages using Supabase Auth UI (or custom)
- [ ] Post-auth redirect: if zero workspaces → `/intake`, else `/dashboard`
- [ ] Workspace switcher in nav (for users in multiple workspaces)
- [ ] Workspace settings page: rename, invite members (by email), member list, leave/delete

### Intake Form
- [ ] Build 5-step wizard with step indicator + back/forward + persisted draft in localStorage
- [ ] Implement validation at each step (Zod schemas reused server-side)
- [ ] Auto-generate starter tasks per project at Step 4
- [ ] On submit, insert all rows in a single Supabase RPC (transactional)
- [ ] First-run tooltip pointing at AI assistant

### Entity CRUD UI
- [ ] List + detail + create/edit pages for: goals, KPIs, projects, tasks, personal tasks, clients, interactions
- [ ] Inline edit for `current_value` on KPI cards
- [ ] Kanban-style board view for tasks grouped by `status`, sub-grouped by project
- [ ] Filter URL state via TanStack Router search params
- [ ] Validation rules enforced in forms + repeated on edge functions (defense in depth)

### Mission Dashboard (`/dashboard`)
- [ ] Strategic Scorecard: traffic-light KPI table (Green ≥75% / Yellow 25-74% / Red <25%)
- [ ] Staleness indicator per KPI (Weekly >10d / Monthly >35d / Quarterly >100d)
- [ ] Portfolio Concentration card (any client >50% MRR → flag)
- [ ] Pattern Detection section: stalled tasks (>14d), frog tasks, killed mammoth (>14d no interaction)
- [ ] Task Ranking section: 10-point scoring with "Top 5 = Pareto 20%" highlight
- [ ] Energy Budget card (deep-work slots available vs committed)
- [ ] Spear-Sharpening Check banner (fires when ≥3 tasks shipped but zero KPIs moved)
- [ ] Daily Frog widget (one frog task surfaced per day)

### Lovable AI — Action Wiring
- [ ] Define system prompt covering hierarchy + SMART + impact + ikigai rules
- [ ] Implement action handlers as Supabase edge functions (one per action in catalog)
- [ ] Wire actions into Lovable AI config with JSON schemas
- [ ] Confirm dialog for bulk/destructive actions
- [ ] `ai_action_audit` table logging on every call (with error capture)
- [ ] Demo prompts in onboarding: "Add a task to ship the staging deploy by Friday", "What's my MRR target?", "Rank my tasks for this week"

### Realtime
- [ ] Subscribe Dashboard to `tasks` + `kpis` channels for the active workspace
- [ ] Optimistic updates on mutations; reconcile on channel events

### Phase 1 exit criteria
- [ ] RLS test suite passes
- [ ] Intake → populated Dashboard in under 5 minutes for a fresh user
- [ ] AI assistant can create a fully-validated task from a natural-language prompt
- [ ] All Phase 1 entities visible, editable, and deletable through both UI and AI
- [ ] Deployed to Lovable hosting with custom domain

---

## Phase 2 — Intelligence & Integrations

Goal: parity with the full Goaly skill set + ingest user notes from Notion/Obsidian via a shared extraction pipeline.

### Coaching Module (`/coaching`)
- [ ] Coaching Agenda view: standing items, KPI snapshot, frog streak, unmeasured goals
- [ ] "Coaching Accountability" sub-section per task — track sessions-committed across runs
- [ ] AI action: `prep_coaching_agenda` returns full agenda + suggested AskUserQuestion prompts
- [ ] Post-session enrichment flow: update profile notes, revenue strategy, standing items

### CEO Review Module (`/review`)
- [ ] Plan input form (paste/upload) + posture picker (SCOPE EXPANSION / HOLD SCOPE / SCOPE REDUCTION)
- [ ] AI action: `challenge_plan` runs Nuclear Scope Challenge + ikigai scoring + single-source-revenue check
- [ ] Output as structured review card (Critical Gaps / Warnings / Recommended Next Step)
- [ ] Hand-off button: "Convert to project" → pre-fills project form

### Meeting Prep + Review
- [ ] Per-client view aggregates: open tasks, prior interactions, recent emails
- [ ] AI action: `prep_meeting_agenda(client_id)` produces structured agenda
- [ ] AI action: `review_meeting(transcript)` extracts action items as task suggestions

### Notion Sync
- [ ] Notion OAuth flow: install integration, select databases to import
- [ ] Server-side worker pulls Notion pages → `note_blobs` (normalize blocks → markdown)
- [ ] Polling job (15min) + manual "Sync now" button
- [ ] Display ingested notes under `/notes` with source attribution
- [ ] Settings page for managing connected Notion sources

### Obsidian Sync
- [ ] V1 adapter: "Connect cloud-synced folder" — user grants browser File System Access API permission to point at Obsidian vault inside iCloud/Dropbox/Drive
- [ ] V2 adapter: tiny CLI / desktop watcher that pushes vault changes to a workspace-scoped endpoint with a per-workspace API token
- [ ] Both write into the same `note_blobs` pipeline
- [ ] Conflict handling: re-ingest by `source_ref` (replace blob, re-embed)

### RAG + Extraction Pipeline
- [ ] Enable pgvector on the Supabase project
- [ ] Embed `note_blobs` on insert (background queue → embedding API → write to vector column)
- [ ] Semantic search endpoint scoped by `workspace_id` (RLS enforced)
- [ ] Extraction worker: LLM pass over new blobs → propose `extraction_suggestions` (action items, commitments with dates)
- [ ] Narrow v1 scope: only "explicit action items" and "stated commitments with dates" — no inferred KPIs/goals
- [ ] Review queue UI at `/notes/inbox` — accept/edit/reject suggestions
- [ ] Accepted suggestions materialize as `tasks` (or `interactions`) via existing AI actions

### Email & Calendar (optional, gated by demand)
- [ ] Google OAuth (Gmail + Calendar) per user
- [ ] Calendar feed → Mission energy budget (count meeting days, exclude baseline calendars)
- [ ] Gmail triage feed → flag emails from active clients with no logged reply
- [ ] Per-message "Convert to task" action

### Polish + Analytics
- [ ] Mobile-responsive layouts (dashboard, tasks board, AI assistant drawer)
- [ ] Workspace export: dump entire workspace to a downloadable ZIP of markdown (parity with `notion-mirror/` format) — closes the lock-in concern
- [ ] Workspace import: ingest a Goaly markdown export → populate a fresh workspace
- [ ] Run-log dashboard: meta-KPI charts (execution rate, energy, MRR confirmed, flag frequency over time)
- [ ] Pricing + billing (Stripe), free tier with one workspace, paid tier with multi-member + integrations

### Phase 2 exit criteria
- [ ] Notion sync + Obsidian (cloud-folder) sync both ingesting into one review queue
- [ ] Extracted action items can become tasks in two clicks
- [ ] Coaching + CEO Review modules feature-complete vs current SKILL.md files
- [ ] Workspace export round-trips (export → import → no data loss)

---

## Open Questions

1. **Per-user vs per-workspace ikigai.** Today ikigai is one operator's framework. In a shared workspace, does each user have their own ikigai filter (yes — store on `profiles`), and how are tasks tagged when a workspace has multiple members?
2. **Coaching cadence in shared workspaces.** Frog-streak tracking is single-actor. In a team, do we track per-assignee streaks or roll up to workspace level?
3. **Lovable AI cost ceiling.** Each AI action call is a model invocation. Need to estimate per-active-user cost and decide whether bulk operations (rank, detect_patterns) should be cached/batched.
4. **MRR estimation source.** The Claude Code version pulls from `MEMORY.md` Active Leads. In the web app, do we have a dedicated `revenue_streams` table, or compute from `clients.monthly_revenue_estimate`? Decision needed before Phase 1 Scorecard.
5. **Export format compatibility.** Should the workspace export exactly match the current `notion-mirror/` YAML conventions so users can migrate between the CLI Goaly and the Lovable Goaly? Recommended yes — preserves user choice.
6. **Audit & retention.** How long do we keep `ai_action_audit` and `run_logs`? Default 90 days, configurable per workspace.

---

## Appendix A — Algorithms & Rules (Executable Spec)

Every threshold, formula, scoring weight, and validation matrix the system must enforce. Ported verbatim from `.claude/skills/*/SKILL.md`, `.claude/skills/goaly-mission/references/*.md`, and `CLAUDE.md`. Use this section as the test-case source for Phase 1 and Phase 2 acceptance.

### A.1 — Canonical Hierarchy & Cascade Rules

```
Goals          (strategic direction)
  └── KPIs           (SMART outcomes — every KPI MUST link to one Goal)
        └── Projects     (bodies of work — every Project MUST link to one Goal)
              └── Tasks        (actions — every business task MUST link to one Project, MAY also link to Goal and KPI)
```

Hard rules enforced at every layer:

| Layer | Mandatory Link | Failure Mode If Missing |
|-------|----------------|-------------------------|
| Goals | ≥1 active KPI | Goal flagged `(unmeasured)` during coaching prep |
| KPIs | Parent Goal | Reject creation |
| Projects | Parent Goal + `definition_of_done` + Horizon | Reject creation |
| Tasks (business) | Project + Goal + Impact + Timeframe + Energy | Reject creation |
| Tasks (personal) | Timeframe + Energy | (Project not required) |
| Brainstorms | None required, but optional Client/Project links | — |

### A.2 — SMART KPI Validation Matrix

Every KPI MUST satisfy all five criteria before insert. Failure on any row blocks creation.

| Criteria | Field Check | If Missing |
|----------|-------------|------------|
| **Specific** | Title set + non-empty description body | Prompt: clarify what's being measured |
| **Measurable** | `current_value` AND `target_value` AND `unit` set | Prompt for target number and unit |
| **Achievable** | `confidence` ∈ {Conservative, Realistic, Stretch} | Default to `Realistic`, flag if target appears extreme vs current |
| **Relevant** | `goal_id` non-null and references active Goal | Prompt: which Goal does this serve? |
| **Time-bound** | `deadline` set (date) | Prompt for deadline |

### A.3 — Default Properties (creation defaults per entity)

Business Task: `status = "Not started"`. Auto-derive: Impact (see A.5), ikigai score (see A.6). Required: Project. Detect from input if mentioned: Priority, Due date, Area, Timeframe, Energy.

Personal Task: `status = "Not started"`. Required: Timeframe, Energy. Areas: Health / Home / Finance / Family / Social / Learning / Travel.

Goal: `status = "Not started"`. Horizon: This Quarter / This Year / Multi-Year.

KPI: `lifecycle = "Active"`. All A.2 fields required.

Project: `status = "Not started"`. Area, Horizon, parent Goal, definition_of_done required.

Brainstorm: `status = "New idea"`. Optional Client/Project links.

### A.4 — Status Enums (canonical)

| Entity | Status values |
|--------|---------------|
| Business Task | `Not started`, `Planned this week`, `In progress`, `Done This Week`, `Done`, `Deprioritized` |
| Personal Task | Same as Business Task |
| Goal | `Not started`, `Active`, `Done`, `Deprioritized` (use `lifecycle` for active/archived) |
| KPI | Uses `lifecycle`: `Active`, `Paused`, `Archived` |
| Project | `Not started`, `Active`, `Done`, `Deprioritized` |
| Brainstorm | `New idea`, `Exploring`, `Promoted`, `Parked` |

Energy enum (Business): `Deep Work`, `Quick Win`, `Admin`, `Waiting On`, `Research`.
Energy enum (Personal): `Deep Work`, `Quick Win`, `Admin`, `Waiting On`, `Errand`.
Impact enum: `Needle Mover`, `Supporting`, `Maintenance`.
Timeframe enum: `This Week`, `This Month`, `This Quarter`, `Someday`.
Horizon enum: `This Quarter`, `This Year`, `Multi-Year`.

### A.5 — Impact Auto-Classification Rules

Run in order at task create/update. First match wins.

| If | Then Impact = |
|----|---------------|
| Task has `kpi_id` non-null | `Needle Mover` |
| Task is client work that closes/grows revenue (project is a Client project AND title/body mentions invoice, close, retainer, ship, deliver) | `Needle Mover` |
| Task has `goal_id` non-null but no `kpi_id`, and matches "prep/research/setup/draft" patterns in title | `Supporting` |
| Task is client work that is admin/setup (kickoff, SOW, scheduling) | `Supporting` |
| Project area = `Operations` AND `goal_id` is null | `Maintenance` |
| Default fallback (no rule matched) | `Supporting` (and flag for manual review) |

### A.6 — Ikigai 4-Dimension Scoring

Run on every Task at create time. Output is a `jsonb` with `{love: 0|1, good_at: 0|1, needs: 0|1, paid_for: 0|1, total: 0..4, reasoning: string}`.

| Dimension | Question (asked of the task title + context) |
|-----------|----------------------------------------------|
| **Love** (Energy) | Does this energize the actor? Will they want to do it on a Tuesday morning? |
| **Good At** (Competence) | Is the actor the right person, or should this be delegated? |
| **Needs** (Impact) | Does this create real value? Can you name who benefits? |
| **Paid For** (Revenue) | Does this generate or protect revenue? Move MRR? Justify a retainer? |

Thresholds:

| Total | Treatment |
|-------|-----------|
| 4/4 or 3/4 | Core work — prioritize aggressively |
| 2/4 | Supporting — acceptable, schedule appropriately |
| 1/4 | Misaligned — flag, consider delegating or declining |
| 0/4 | Red flag — confirm before creating |

The filter is **visibility, not a gate**. Admin/maintenance tasks legitimately score low. Do not block creation based on score alone.

### A.7 — Weekly Task Ranking (Impact Scoring, 15-point scale)

Candidates: all tasks with `status ∈ {Not started, Planned this week, In progress}`.

| Question | Points |
|----------|--------|
| Does this move MRR? (client work, revenue-generating) | +3 |
| Does this ship a product toward paying users? | +3 |
| Does this grow audience/subscribers? | +2 |
| Does this have a hard deadline (`due_date` set)? | +1 |
| Is someone external waiting on this? (`energy = Waiting On`, or client task) | +1 |
| **Is this a coaching commitment?** (`coaching_accountability` non-null) | **+3** |
| **Coaching sessions committed ≥ 3?** (recurring stall — highest priority frog) | **+2 bonus** |
| **Coaching sessions committed = 2?** | **+1 bonus** |

**Maximum score: 15 points.** (Not 10 — coaching bias is intentional. The body of the doc says "10-point scoring"; the appendix supersedes it.)

### A.8 — Pareto Selection & Coaching Commitment Floor

Top 3-5 tasks by score are the **Pareto 20%**.

**Floor rule (non-negotiable):** At least ONE coaching commitment task MUST appear in the top 5 every week. If pure scoring doesn't surface one, manually insert the highest-sessions-committed frog into position 3, 4, or 5.

**Rationale:** client work moves naturally (external accountability); coaching commitments stall naturally (no external accountability). Without the bias and the floor, frogs ALWAYS lose to client tasks and the system reinforces avoidance.

**Presentation:**

```
🐸 COACHING COMMITMENTS (must pick at least 1):
| Rank | Task | Sessions | Days Stalled | First Step |
```
…then the regular ranked list grouped by Project.

**After user selection:** chosen → `status: Planned this week`; previously-`Planned this week` but not chosen → `status: Not started` (demote). For chosen frog tasks, prompt user to add a calendar block (date + time). **No calendar block = task won't happen.**

### A.9 — Six Pattern Detectors

Run on every Mission dashboard load. No external I/O — pure functions over already-loaded workspace data.

| # | Detector | Flag Condition | Detection Logic |
|---|----------|----------------|-----------------|
| 1 | **Portfolio Concentration** | Any client > 50% MRR, OR fewer than 3 revenue sources | `max(client.monthly_revenue_estimate) / sum(...) > 0.5` OR `count(clients where status='Active' and rate > 0) < 3` |
| 2 | **KPI Staleness** | `updated_at` overdue vs `tracking_frequency` | See A.11 staleness thresholds |
| 3 | **Initiation Avoidance** | Active task with `updated_at > 14 days ago` AND status ∈ {Not started, Planned this week, In progress} | Surfaces tasks the user keeps not starting |
| 4 | **Killed Mammoth** | No interaction with an Active client for 14+ days, OR accepted lead with no follow-up interaction | Per active client: `max(interactions.occurred_at) < today - 14 days` |
| 5 | **Frog Tasks** | Status `Not started` or `Planned this week` AND `updated_at > 14 days ago` | `weeks_stalled = floor((today - updated_at) / 7)` |
| 6 | **Frog Streak** | Coaching-tagged task still `Not started` AND `coaching_accountability.sessions_committed > 1` | Surface message: `"X frog tasks stalled across Y coaching sessions"` |

If no detector fires: output `"No flags. Portfolio, KPIs, and pipeline all healthy."`

### A.10 — Daily Frog Selection Algorithm

Selects ONE frog task per day to surface as "Today's Frog." Run during PULSE and MONDAY mode dashboard load.

Selection priority (apply in order, first non-tied winner):

1. **Highest `coaching_accountability.sessions_committed`** count (most overdue coaching commitment wins)
2. **If tied:** oldest `updated_at` date (longest untouched wins)
3. **If energy mismatch** (e.g., `energy = Deep Work` frog selected for a meeting-heavy day per calendar): skip to next eligible

Output format:

```
🐸 TODAY'S FROG: [task title]
   Committed: [N] coaching sessions ([dates])
   Days stalled: [N]
   First step: [from "First micro-step" field in task body]
```

MONDAY mode: after task ranking (A.7), prompt user to add calendar blocks for the top 3 frogs of the week.
PULSE mode: check if yesterday's frog was eaten (status changed from `Not started` since last pulse). Log to `run_logs.payload.frog_eaten`.

### A.11 — Traffic Light & Staleness Thresholds

**KPI Progress traffic lights:**

| Light | Condition |
|-------|-----------|
| 🟢 Green | progress ≥ 75% |
| 🟡 Yellow | 25% ≤ progress < 75% |
| 🔴 Red | progress < 25% |

Where `progress = (current_value - starting_value) / (target_value - starting_value)`, clamped to [0, ∞).

**KPI Staleness (per `tracking_frequency`):**

| Frequency | Stale if `updated_at` older than |
|-----------|----------------------------------|
| Weekly | 10 days |
| Monthly | 35 days |
| Quarterly | 100 days |

PULSE mode: surface KPIs only if **critically stale** (≥ 2× the threshold). MONDAY mode: surface all stale KPIs and prompt for updates.

### A.12 — Energy Budget Formula

Computed during MONDAY mode (Step 7 in `/mission`).

```
remaining_weekdays  = count of weekdays from today to Friday (inclusive)
meeting_days        = count of distinct weekdays containing at least 1 external meeting (calendar source, exclude baseline calendars)
free_days           = remaining_weekdays - meeting_days
available_slots     = free_days × 2          # two deep-work slots per free day
committed_slots     = count of tasks where energy = "Deep Work" AND status ∈ {Planned this week, In progress}
remaining_slots     = available_slots - committed_slots
```

Output a 1-line recommendation:
- `remaining_slots > 0` → `"Room for N more deep-work tasks this week."`
- `remaining_slots == 0` → `"Calendar fully committed. Add nothing new."`
- `remaining_slots < 0` → `"Overcommitted by N deep-work slots — defer or demote."`

### A.13 — Meta-KPI Formulas + Spear-Sharpening Trigger

Computed during MONDAY retro (Step 8). **Ephemeral — display only, do not persist into KPI tables.** Optionally cache the final values into the MONDAY `run_logs.payload` row for trend charts.

| Meta-KPI | Formula | Target | Warning Threshold |
|----------|---------|--------|-------------------|
| **Execution Score** | `shipped / (shipped + wasted)` | > 70% | < 50% |
| **High-Leverage Ratio** | `count(shipped where impact='Needle Mover') / count(shipped)` | > 40% | < 20% |
| **Deep Work Ratio** | `count(shipped where energy='Deep Work') / count(shipped)` | > 50% | < 30% |

Where:
- `shipped` = tasks with `status = "Done This Week"` (captured BEFORE the auto-cleanup step archives them)
- `wasted` = tasks with `status = "Planned this week"` AND `updated_at > 7 days ago` (planned but untouched)

**Spear-Sharpening Trigger:**

After computing the meta-KPIs, check whether any active KPI's `current_value` actually changed in the past 7 days.

```
if shipped >= 3 AND kpis_with_value_change_in_last_7d == 0:
    emit_banner("(spear-sharpening) Lots of activity (N tasks shipped) but no KPI movement — are you sharpening the spear instead of hunting the mammoth?")
```

Common cause when triggered: all shipped tasks have `impact ∈ {Supporting, Maintenance}`, or shipped tasks have no Goal/KPI link.

### A.14 — CEO Review: Nuclear Scope Challenge (8 Questions)

Asked in Step 1 of the review, before any plan-specific analysis. All five base questions are always asked; questions 6-8 are added when the plan involves client work.

**Base (always asked):**

1. **"What is the 10-star version of this?"** — Dream version, then work back to the buildable 7-star version.
2. **"What would you build with zero existing code?"** — Sunk-cost check.
3. **"Who specifically will use this, and what will they stop doing?"** — No named user = hypothesis, not feature.
4. **"What's the simplest version that would make someone say 'holy shit'?"** — Not MVP. Minimum impressive version.
5. **"Is this a feature, a product, or a business?"** — Scope creep happens when features are treated as products.

**Client engagement only (added when plan is for a Client project):**

6. **"Does this expand or contract the engagement?"** — Prefer plans that create recurring need.
7. **"Does this create dependency on the actor or make the actor replaceable?"** — Strategic = good for retainer. CRUD = replaceable.
8. **"Is this the actor's problem to solve?"** — Fractional CTO value is strategic. Implementation should be delegated.

After the questions, present three postures via single-select. Do not proceed until the user picks one.

### A.15 — CEO Review: Three Postures (per-posture output rules)

Postures NEVER blend. Each has its own checklist and output format.

**SCOPE EXPANSION**
- *Use for:* Experiments, product vision, new client discovery, brainstorming.
- *Checklist:* Vision big enough for 3 years? Adjacent opportunities? Platforms not features? Network effects? Data generation? Moat?
- *Output:* Vision document expanding the plan. 2-3 "what if" directions. Recommend `/brainstorm` for exploration.

**HOLD SCOPE**
- *Use for:* Active client work with agreed scope, mid-sprint, committed deliverables.
- *Checklist:* Acceptance criteria? Error states enumerated? Data flows explicit? Edge cases named? Observability planned? Dependencies identified? Rollback strategy? Performance constraints? Security surface mapped?
- *Output:* List of gaps, risks, missing specifications. Ordered by severity. **No implementation suggestions.**

**SCOPE REDUCTION**
- *Use for:* Overcommitment, dragging projects, low energy, full calendar.
- *Checklist:* What can be cut? Deferred to v2? Gold-plating? Built "for later"? Off-the-shelf replacement? 1-day vs 1-week version? Manual workaround?
- *Output:* Stripped-down plan with explicit "cut" and "keep" lists. Each cut gets a one-line justification.

### A.16 — CEO Review: Ikigai Score Thresholds

Score the plan 0-4 against the dimensions in A.6.

| Score | Action |
|-------|--------|
| 3-4/4 | Core work — proceed |
| 2/4 | Supporting — flag missing dimensions |
| 0-1/4 | Misaligned — challenge hard, **do not proceed without explicit user confirmation** |

### A.17 — CEO Review: Retainer Awareness Check (client work only)

Skip for personal experiments. For client plans, all four must be addressed in the review output:

1. Does this create ongoing value justifying a monthly retainer? (Strategic architecture > one-off deliverables.)
2. Is the actor positioned as strategic or tactical? **Target: 80% strategic / 20% tactical.**
3. Does this create follow-on work? Dead-end plans kill retainers.
4. Is there a "leave behind"? Best fCTO work makes the team more capable. Indispensable for strategy, dispensable for execution.

If any answer is no, present alternatives that pass.

### A.18 — CEO Review: Prime Directives Audit

Non-negotiable engineering checks applied regardless of posture:

- **Zero silent failures** — every operation that can fail has an explicit failure path (timeouts, retries, circuit breakers, DLQ, actionable user errors)
- **Every error has a name** — typed, categorized, traceable errors with context at every boundary
- **Data flows have shadow paths** — missing data, stale data, wrong data, too much data all handled
- **Interactions have edge cases** — double-submit, back button, concurrent modification, session expiry, offline
- **Observability is scope** — success/failure metrics, alerting thresholds, debuggable without SSH

For non-trivial flows, a diagram is required (Mermaid: sequence / state machine / data flow / architecture).

### A.19 — Coaching Accountability Rules

The `tasks.coaching_accountability` jsonb has the shape `{sessions_committed: int, dates_committed: date[], frog_type: string, first_micro_step: string}`.

| Rule | When |
|------|------|
| **Sort agenda accountability table by `sessions_committed` DESC** | Always |
| **Flag `"RECURRING STALL — discuss pattern, not just task"`** | `sessions_committed >= 3` AND status still ∈ {Not started, Planned this week} |
| **Celebrate `"FROG EATEN: <task title>"`** | Task was on accountability list last session AND `status` is now `Done This Week` or `Done` |
| **Daily Frog priority** | See A.10 |
| **Ranking bias** | See A.7 (+3 base, +2 if sessions≥3, +1 if sessions=2) |
| **Top-5 floor** | See A.8 (at least one coaching commitment in top 5) |

### A.20 — Standing Items Source of Truth

The coaching agenda's "Standing Items" checklist is read **live** from `MEMORY.md` (or its database equivalent: a `workspace_settings.coaching_standing_items text[]` column). **Do not hardcode** the list anywhere in the application. It changes between sessions.

Render as checkboxes (markdown `- [ ]`) in the agenda. The first item is always: `Current MRR: <value> (confirmed in Step 4)`.

### A.21 — MRR Computation Rule (CRITICAL)

**MRR is the sum of monthly revenue estimates per active client, NOT rate × hours.**

```
MRR = sum(clients.monthly_revenue_estimate where status = 'Active')
```

Always ask the user to confirm MRR at the start of MONDAY and at every coaching prep. Never compute from `rate` × estimated hours. The system explicitly captures `monthly_revenue_estimate` per client to make this unambiguous.

### A.22 — Three-Phase Execution Pattern

Every AI action that loads multiple data sources MUST follow:

1. **Collect** — fire all reads in parallel. No analysis yet. Single round-trip to the database.
2. **Analyze** — reason over collected data. No further I/O. No new queries, no late reads.
3. **Interact** — present output; ask follow-up questions; apply mutations only after confirmation.

This pattern preserves the latency profile of the Claude Code version (Mission loads in under 2 seconds) and prevents the LLM from drifting mid-reasoning.

### A.23 — Project Routing Guide (template)

Used by AI actions when classifying ambiguous new tasks. The table is workspace-configurable — store as `workspace_settings.project_routing jsonb`. Default template:

| If the task is about… | Assign to Project |
|------------------------|-------------------|
| Client-A work | Client-A |
| Client-B work | Client-B |
| Coaching sessions, personal development, positioning | Professional Development |
| Blog posts, social media, lead flow, brand storytelling | Content & Brand |
| Networking, partnerships, lead screening, intros, events | Business Development |
| Side projects, experiments, prototypes | Experiments |
| Accounting, legal, admin, infrastructure, tooling | Operations |
| New client engagement | Create a new Project first (do not infer) |

### A.24 — Tag Management Rules

| Field Type | Behavior |
|------------|----------|
| `multi_select` (Area, Space, Epic, etc.) | New values may be created on the fly; keep concise and consistent with existing naming. Do not ask permission — create and mention in the response. |
| `select` (Timeframe, Energy, Horizon, Priority, Status, Impact) | **Locked.** Use only existing options. Surface a validation error if user provides an unknown value; do not invent new options. |

### A.25 — Coaching-Tagged Task Detection

A task is "coaching-tagged" (and therefore enters Daily Frog selection, ranking bonuses, and accountability surface) if **any** of the following are true:

- `tasks.coaching_accountability` is non-null
- Task body contains a `## Coaching Accountability` markdown section (legacy / import-from-markdown compatibility)
- Task has `tags @> '["coaching"]'::jsonb` (if a tag system is added)

Materialize a `tasks.is_coaching_commitment generated always as (...) stored` boolean column for fast filtering.

### A.26 — Mode Detection for Mission

| Mode | Trigger Condition | Steps to Execute |
|------|-------------------|------------------|
| **PULSE** | Default weekday OR explicit "quick check" trigger | Scorecard (A.11), Pattern Detection (A.9), Today's Frog (A.10), in-progress + actionable emails |
| **MONDAY** | Day of week = Monday OR explicit "plan my week" / "weekly planning" trigger | All of PULSE, plus Auto-Cleanup, Energy Budget (A.12), Retro + Meta-KPIs (A.13), Task Ranking (A.7), Pareto Selection (A.8), commit |
| **COACHING** | Explicit "prep for coach" / "coaching prep" trigger | Use `/goaly-coaching-prep` flow, NOT mission |

**PULSE interaction rule:** zero prompts unless a KPI is critically stale (≥ 2× the staleness threshold). Target: 2-3 minutes wall-clock.

**MONDAY interaction rule:** structured prompts (2-4 options each) for non-auto KPIs, energy retro, task selection, frog calendar blocks.

### A.27 — Auto-Cleanup Rule (MONDAY only)

At the start of MONDAY mode, before computing the retro:

```sql
update tasks
set status = 'Done'
where status = 'Done This Week'
  and workspace_id = :w;

update personal_tasks
set status = 'Done'
where status = 'Done This Week'
  and workspace_id = :w;
```

Capture the count BEFORE the update for use in retro/meta-KPI calculations (the `shipped` value in A.13).

### A.28 — Validation Sequence at Task Create

When the AI assistant or a form attempts to insert a task, apply checks in this order. Stop at first failure.

1. Workspace membership check (RLS — handled by Postgres, not application)
2. Required fields present (Title, Project for business tasks; A.3)
3. Project link resolves to active Project in same workspace
4. Goal link resolves to active Goal in same workspace (if provided)
5. KPI link resolves to active KPI in same workspace (if provided)
6. Run A.5 impact auto-classification → set `impact`
7. Run A.6 ikigai scoring → set `ikigai_score`
8. Insert row
9. If `impact = "Needle Mover"`, append to `ai_action_audit` with reasoning
10. Return created row

### A.29 — Run Log Schema

Every Mission, Coaching, and Review run appends one row to `run_logs`.

```json
{
  "module": "mission" | "coaching" | "review",
  "mode": "MONDAY" | "PULSE" | "EXPANSION" | "HOLD" | "REDUCTION",
  "run_at": "2026-03-19T09:00:00Z",
  "payload": {
    "meta_kpis": {"execution": 72, "high_leverage": 40, "deep_work": 50},
    "mrr_confirmed": 18000,
    "flags": ["stalled_project", "killed_mammoth"],
    "frog_eaten": true,
    "frog_streak": 3,
    "tasks_planned": 5,
    "spear_sharpening_fired": false
  }
}
```

This table feeds the Phase 2 run-log dashboard (meta-KPI trends over time).
