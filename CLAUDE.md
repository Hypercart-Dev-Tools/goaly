# Goaly

A goal/KPI/task operating system for Claude Code. Turn unstructured input into organized entries across Goals, KPIs, Tasks, Projects, and Brainstorms — stored as local markdown files with optional Notion sync.

## Setup

**First time?** Run `/goaly-setup` to generate your starter files (notion-mirror directories, sample goals/KPIs, config scaffolding).

The `notion-mirror/` directory is just markdown files on disk. **Notion is entirely optional** — Goaly works as a standalone local system. If you want Notion sync, configure it later via `tools/notion-sync/`.

To get started without the setup skill:
1. Create the `notion-mirror/` directories listed below
2. Fill in your goals, KPIs, and projects as markdown files with YAML frontmatter
3. Replace the placeholder database IDs in this file with your own (only needed if using Notion sync)
4. Customize the Project Routing Guide to match your projects

## Notion Mirror (Primary Interface)

All databases are accessible as local markdown files in `notion-mirror/`. This is the primary interface for all data — read, create, and edit files here. If Notion sync is configured, changes push automatically via post-commit hook.

### Directory Structure

```
notion-mirror/
├── tasks/           # Business tasks
├── personal-tasks/  # Personal tasks
├── goals/           # Goals
├── kpis/            # KPIs with targets
├── projects/        # Projects
├── brainstorms/     # Brainstorm sessions
├── clients/         # Client CRM data (optional)
├── contacts/        # Contact details (optional)
└── interactions/    # Meeting notes, emails, calls (optional)
```

### File Format

Each markdown file has YAML frontmatter with all properties and a body with page content. Relations use human-readable names. Example:

```yaml
---
title: Deploy staging environment
status: Planned this week
project: Client-A — Discovery Phase
goal: Build Portfolio of Internet Companies
impact: Needle Mover
energy: Deep Work
notion_id: ffff0000-0000-0000-0000-000000000001  # Only if using Notion sync
---

Page body content here...
```

### When to Use

- **Read** notion-mirror files for all data (fast, works offline)
- **Create** new items by writing markdown files with YAML frontmatter to the appropriate directory
- **Edit** existing items by modifying their markdown files
- **Search across databases** using grep/glob on the markdown files
- All changes are committed to git — post-commit hook can push to Notion if configured

### Notion Sync (Optional)

If you use Notion, configure database IDs below and set up `tools/notion-sync/`:

```bash
# Pull all databases from Notion
cd tools/notion-sync && npx tsx sync.ts pull

# Push local changes back to Notion
cd tools/notion-sync && npx tsx sync.ts push

# Check sync status
cd tools/notion-sync && npx tsx sync.ts status
```

#### Database IDs

Replace these with your Notion database IDs if using sync:

- Tasks: `collection://YOUR-TASKS-DATABASE-ID`
- Personal Tasks: `collection://YOUR-PERSONAL-TASKS-DATABASE-ID`
- Goals: `collection://YOUR-GOALS-DATABASE-ID`
- KPIs: `collection://YOUR-KPIS-DATABASE-ID`
- Projects: `collection://YOUR-PROJECTS-DATABASE-ID`
- Brainstorms: `collection://YOUR-BRAINSTORMS-DATABASE-ID`
- Clients: `collection://YOUR-CLIENTS-DATABASE-ID` <!-- CRM client records -->
- Contacts: `collection://YOUR-CONTACTS-DATABASE-ID` <!-- Individual people linked to clients -->
- Interactions: `collection://YOUR-INTERACTIONS-DATABASE-ID` <!-- All touchpoints: meetings, emails, calls -->

### Sync Automation

- **Post-commit hook** — Pushes `notion-mirror/` changes to Notion after each git commit (async, non-blocking). Skips `[sync]` commits to prevent loops.
- **Session start** — Run `git pull` to get latest notion-mirror changes from remote.

## How It Works

You say stuff. Claude parses it, classifies items, writes them to the appropriate `notion-mirror/` directory, links relationships where obvious, and reports what was created. No confirmation needed — just do it and summarize.

When any workflow needs your input, use the `AskUserQuestion` tool with structured options (2-4 choices with clear descriptions). Structured choices are easier to process than open-ended questions. Use tables not prose for presenting options.

## Code Intelligence (ask-self)

ask-self is a repo-grounded RAG tool that provides intelligent context and answers about this workspace.

**Command:** `./scripts/ask-self-query.sh "your question here"`

Before grep-spelunking or asking the user to re-explain repo context, query ask-self first.

**When to use it:**
- Session-start orientation
- Unfamiliar subsystems
- Pronoun-heavy user references such as "that helper" or "the auth flow"
- Cross-file behavior questions

**When not to use it:**
- Trivial single-file reads
- Tight edit-test loops
- Questions about current uncommitted state

**Staleness note:** The index reflects the last ingest; it may lag active uncommitted work.
**Override note:** `ASK_SELF_PATH` can be overridden if needed.

## Skills (On-Demand)

Workflows are loaded on-demand as skills via `.claude/skills/`. Invoke with `/skill-name [args]`.

| Skill | Triggers | Purpose |
|-------|----------|---------|
| `/goaly-mission` | "plan my week", "weekly planning", "quick check" | Monday full planning (retro + energy budget + task ranking) or weekday pulse check |
| `/goaly-coaching-prep` | "prep for coaching", "coaching prep" | Pre-coaching agenda: goals, KPIs, metrics, standing items |
| `/goaly-review-meeting [client]` | "review notes from X", "review call" | Post-meeting: transcript to Interaction file, tasks, follow-up email |
| `/goaly-triage` | "check emails", "check calendar", "anything missing?" | Calendar + email triage, cross-reference with existing tasks |
| `/goaly-client-email [client]` | "email [client]", "reply to [client]" | Read/draft/reply client emails, log as Interaction |
| `/goaly-meeting-prep [client]` | "prep for meeting", "agenda for [client]" | Pre-meeting agenda from client history, open tasks, prior interactions |
| `/goaly-onboard-client [name]` | "new client", "onboard [client]" | Full onboarding: CRM, contacts, contract, project, time tracking |
| `/goaly-screen-lead` | "screen this lead", "reply to lead" | Research on inbound leads: profile, company, flags, fit, reply draft |
| `/goaly-ceo-review` | "review this plan", "strategic review" | Strategic plan review: scope challenge, ikigai filter, retainer check |

### Goaly Shared Conventions

`.claude/skills/_shared/` holds conventions referenced by all goaly skills. Skills reference these instead of duplicating.

| File | Contents |
|------|----------|
| `conventions.md` | Sync verification steps, git freshness check, baseline calendar ignore rule, null relation ID validation, "tables not prose" formatting rule |
| `gotchas.md` | Cross-skill gotchas: formula fields are read-only, pipe characters need `\|` escaping, `status` type options can't be added via API |

### Goaly Run Logs

Skills that run regularly append to `data/run-log.jsonl` in their skill folder (gitignored). Format:

```jsonl
{"date":"2026-03-19","mode":"MONDAY","meta_kpis":{"execution":72,"energy":65},"mrr_confirmed":18000,"flags":["stalled_project"]}
```

## Item Classification

- **Tasks (Business)**: Work actions, client tasks, business admin ("meeting with...", "deploy...", "invoice...") -> `notion-mirror/tasks/`
- **Tasks (Personal)**: Personal actions, chores, life admin ("dentist appointment", "renew passport", "grocery...") -> `notion-mirror/personal-tasks/`
- **Goals**: Strategic aspirations, long-term direction ("I want to build...", "My vision is...", "By 2027...") -> `notion-mirror/goals/`
- **KPIs**: Measurable outcomes with targets and deadlines ("reach 5K MRR", "get 10 customers", "1K monthly visitors") -> `notion-mirror/kpis/`
- **Projects**: Multi-step initiatives, bounded work ("The X project...", "We're building...") -> `notion-mirror/projects/`
- **Brainstorms**: Exploration, ideas ("What if...", "I'm thinking about...", "Maybe we could...") -- has Space, Category, Problem Category tags plus Client and Project relations -> `notion-mirror/brainstorms/`

When input contains multiple items, split them and classify each independently.

## Default Properties

**Tasks (Business) -> `notion-mirror/tasks/`:**
To create a task, write a markdown file to `notion-mirror/tasks/` with YAML frontmatter containing these properties:
- Status = "Not started"
- Detect Priority if mentioned
- Detect Due date if mentioned
- `Area` (multi_select): Finance, Marketing, Product, Operations, Legal, Sales, Engineering -- set when area is obvious from context
- `Timeframe` (select): This Week, This Month, This Quarter, Someday -- set if urgency/timing mentioned
- `Energy` (select): Deep Work, Quick Win, Admin, Waiting On, Research -- set if task type is clear
- `Projects` (relation): ALWAYS link to parent Project. Every task must belong to a Project for board sub-grouping.
- `Parent task` (relation): Set when creating a sub-task under a parent task
- `Impact` (select): Needle Mover, Supporting, Maintenance -- classify based on goal proximity (see Impact Classification below)
- **Ikigai alignment check** (before creating any task): Does this task score on at least 2 of 4 ikigai dimensions? (1) Energizes you, (2) Uses your strengths, (3) Creates real impact, (4) Generates revenue. If 0-1, flag it as potentially misaligned. Don't block creation -- just note the alignment in the task body.

**Tasks (Personal) -> `notion-mirror/personal-tasks/`:**
To create a personal task, write a markdown file to `notion-mirror/personal-tasks/` with YAML frontmatter:
- Status = "Not started"
- Detect Priority if mentioned
- Detect Due date if mentioned
- `Area` (multi_select): Health, Home, Finance, Family, Social, Learning, Travel -- set when area is obvious
- `Timeframe` (select): This Week, This Month, This Quarter, Someday -- set if timing mentioned
- `Energy` (select): Deep Work, Quick Win, Admin, Waiting On, Errand -- set if task type is clear

**Goals -> `notion-mirror/goals/`:**
To create a goal, write a markdown file to `notion-mirror/goals/`:
- Status = "Not started"
- `Area` (multi_select): Finance, Marketing, Product, Operations, Health, Personal Growth -- set when relevant
- `Horizon` (select): This Quarter, This Year, Multi-Year -- set if timeframe mentioned

**KPIs -> `notion-mirror/kpis/`:**
To create a KPI, write a markdown file to `notion-mirror/kpis/`:
- Lifecycle = "Active"
- `Unit` (select): EUR, Count, Percent, Hours, Score
- `Current Value` (number): starting measurement
- `Target Value` (number): SMART target
- `Confidence` (select): Conservative, Realistic, Stretch
- `Tracking Frequency` (select): Weekly, Monthly, Quarterly
- `Horizon` (select): This Quarter, This Year, Multi-Year
- `Area` (multi_select): Finance, Marketing, Product, Operations, Engineering, Growth, Content
- `Deadline` (date): SMART time-bound deadline
- `Goal` (relation): MUST link to parent Goal

**Projects -> `notion-mirror/projects/`:**
To create a project, write a markdown file to `notion-mirror/projects/`:
- Status = "Not started"
- `Area` (multi_select): Finance, Marketing, Product, Operations, Engineering, Growth -- set when relevant
- `Horizon` (select): This Quarter, This Year, Multi-Year -- set if timeframe mentioned

**Brainstorms -> `notion-mirror/brainstorms/`:**
To create a brainstorm, write a markdown file to `notion-mirror/brainstorms/`:
- Status = "New idea"
- Already has Space, Category, Problem Category -- use existing tags
- `Client` (relation): Link to Client when brainstorm is for/about a specific client
- `Project` (relation): Link to Project when brainstorm relates to a specific project

## Tag Management

Tags are not fixed. When creating items, if the existing tag options don't fit:
- Create new options on the fly for any multi_select property (Area, Space, Epic, etc.)
- Keep new tags concise and consistent with existing naming style
- Don't ask for permission -- just create the tag and mention it in the summary
- For select properties (Timeframe, Energy, Horizon, Priority), stick to existing options only

## Relationships

- Link KPIs to Goals (mandatory -- every KPI must have a parent Goal)
- Link tasks to KPIs or Goals when the connection is obvious
- Link projects to Goals when mentioned together
- Every business task MUST have a Project link -- use the project routing guide below
- Brainstorms can be promoted to goals when you say "let's do this" or similar
- When a Goal has no KPIs, flag it as "unmeasured" during coaching prep
- Link tasks to Projects (mandatory -- every business task must have a parent Project for board organization)

### Project Routing Guide

When creating tasks, assign the Project based on this priority. Customize this table for your projects:

| If the task is about... | Assign to Project |
|------------------------|-------------------|
| Client-A work | Client-A |
| Client-B work | Client-B |
| Coaching sessions, personal development, positioning | Professional Development |
| Blog posts, social media, lead flow, brand storytelling | Content & Brand |
| Networking, partnerships, lead screening, intros, events | Business Development |
| Side projects, experiments, prototypes | Experiments |
| Accounting, legal, admin, infrastructure, tooling | Operations |
| New client engagement | Create a new Project first |

## SMART Enforcement Rules

Every KPI MUST satisfy all SMART criteria before creation:

| Criteria | Check | Action if Missing |
|----------|-------|-------------------|
| **Specific** | Clear metric name + description | Ask to clarify what's being measured |
| **Measurable** | Current Value + Target Value + Unit set | Ask for target number and unit |
| **Achievable** | Confidence level set | Default to "Realistic", flag if target seems extreme |
| **Relevant** | Goal relation linked | Ask which Goal this serves |
| **Time-bound** | Deadline set | Ask for a deadline |

### Enforcement at Every Layer

- **Goals**: Must have at least one KPI linked (flag unmeasured goals in coaching prep)
- **KPIs**: Full SMART validation required -- reject creation if any element is missing
- **Projects**: Must have a definition of done, a Horizon, and link to a Goal
- **Tasks**: Must have a Timeframe, an Energy level, a Project link, a Goal link, and an Impact classification

### Hierarchy

```
Goals (strategic direction -- "Where am I heading?")
  +-- KPIs (SMART outcomes -- "How do I know I'm getting there?")
       +-- Projects (bodies of work -- "What am I building?")
            +-- Tasks (actions -- "What do I do today?")
```

## Impact Classification

Every task gets an Impact rating based on how directly it advances active KPIs:

| Impact | Color | Definition | Examples |
|--------|-------|------------|----------|
| **Needle Mover** | Red | Directly advances a KPI measurement (closes revenue, ships product, grows audience) | Close client retainer, ship MVP, publish blog post |
| **Supporting** | Yellow | Enables or unblocks a Needle Mover (prep work, research, setup) | Prep for coaching session, research tech stack, write SOW |
| **Maintenance** | Gray | Keeps the lights on but doesn't move KPIs forward | Tax filing, bookkeeping, admin, tooling |

### Ikigai Alignment Filter

Every task gets a quick ikigai check before creation. Score against 4 dimensions:

| Dimension | Question | Source |
|-----------|----------|--------|
| **Love** (Energy) | Does this energize you or drain you? | What I Love in ikigai |
| **Good At** (Competence) | Are you the right person, or should this be delegated? | What I'm Good At in ikigai |
| **Needs** (Impact) | Does this create real value for someone? | What the World Needs in ikigai |
| **Paid For** (Revenue) | Does this generate or protect revenue? | What I Can Be Paid For in ikigai |

- **4/4 or 3/4**: Core work -- prioritize aggressively
- **2/4**: Supporting work -- acceptable, schedule appropriately
- **1/4**: Misaligned -- flag, consider delegating or declining
- **0/4**: Red flag -- ask before creating

This filter catches "vanity tasks" (organizing the board instead of doing the work) and misaligned tasks that linger because they don't connect to anything you care about. It is NOT a gate -- admin and maintenance tasks will score low and that's fine. The filter just makes the alignment visible.

### Auto-Classification Rules

When creating tasks, classify Impact automatically:
- Task linked to a KPI -> **Needle Mover**
- Task linked to a Goal but supporting (prep, research, setup) -> **Supporting**
- Task in Operations project with no Goal link -> **Maintenance**
- Client work that closes/grows revenue -> **Needle Mover**
- Client work that's admin/setup -> **Supporting**

### Weekly Impact Scoring

During Monday weekly planning, score each candidate "Planned this week" task against active KPIs:

| Question | Points |
|----------|--------|
| Does this move MRR? | +3 |
| Does this ship a product toward paying users? | +3 |
| Does this grow email subscribers / audience? | +2 |
| Does this have a hard deadline? | +1 |
| Is someone external waiting on this? | +1 |

Present tasks in ranked order. The top 3-5 tasks are the Pareto 20% -- protect time for these above all else.

## Response Format

After creating items (as markdown files in `notion-mirror/`), summarize concisely:
- What was created (type, title, key properties, file path)
- Any relationships established
- Anything ambiguous that wasn't captured

Changes sync to Notion automatically on commit (if configured). Keep it short. No preamble, no padding.

## Session Hygiene

### Task Sync

After every meaningful action (sending an email, logging a call, updating client files, completing work), check if any tasks in `notion-mirror/` need updating:

- Edit task files to mark completed tasks as "Done This Week" (update `status` in frontmatter)
- Update in-progress task descriptions with latest status
- Create new task files in `notion-mirror/tasks/` for any action items that emerged
- Verify Goal and Project relations in frontmatter on any new/updated tasks

Don't batch these up -- edit files as you go. Changes sync to Notion on commit (if configured).

### Git Sync

Commit and push changes regularly throughout the session -- don't let local changes pile up. Committing `notion-mirror/` changes triggers automatic push to Notion via post-commit hook (if configured). Commit after:

- Creating or editing notion-mirror files (tasks, goals, KPIs, projects, etc.)
- Logging client communications (emails, meeting notes)
- Updating client memory files
- Updating CLAUDE.md or memory files
- Creating or modifying documents in client folders

Use conventional commit messages: `chore:` for logs/notes, `docs:` for CLAUDE.md/memory updates, `feat:` for new client folders or templates.

Push to origin after each commit so nothing is lost if the session ends unexpectedly.

## Skill Testing

Each skill in `.claude/skills/` has a three-layer test suite in `tests/<skill>/`:

| Layer | File | Purpose | Run |
|-------|------|---------|-----|
| 1 | `test-computations.sh` | Deterministic bash tests (mode detection, grep patterns, validation rules) | `bash tests/<skill>/test-computations.sh` |
| 2 | `promptfooconfig.yaml` | LLM eval with assertions (contains, not-contains, llm-rubric) | `promptfoo eval -c tests/<skill>/promptfooconfig.yaml` |
| 3 | `SMOKE-TEST.md` | Manual checklist for live verification | Human walkthrough |

### Running Tests

```bash
# Run all Layer 1 tests
for d in tests/*/; do bash "$d/test-computations.sh" 2>/dev/null; done

# Run one skill
bash tests/coaching-prep/test-computations.sh

# Run Layer 2 eval for one skill
promptfoo eval -c tests/mission/promptfooconfig.yaml
```

### Fixtures

- `tests/<skill>/fixtures/` -- Skill-specific fixtures (don't modify -- backward compatibility)
- `tests/shared-fixtures/` -- Shared fixtures for all skills (notion-mirror, clients, memory)

### Skill Evolution

After any skill failure or unexpected behavior, add the failure mode to that skill's `gotchas.md` before closing the session. When a `feedback.log` entry represents a recurring error (not just a preference), promote it to `gotchas.md`.

### After Editing a Skill

1. **Layer 0 -- Structure**: `bash tests/validate-skill-structure.sh .claude/skills/<skill>/` -- folder structure, gotchas.md, description trigger check
2. **Layer 1 -- Deterministic**: `bash tests/<skill>/test-computations.sh` -- all must pass
3. **Layer 2 -- LLM eval**: `promptfoo eval -c tests/<skill>/promptfooconfig.yaml` -- compare to baseline with `--compare`
4. **Layer 3 -- Smoke test**: Walk through `tests/<skill>/SMOKE-TEST.md` if the change is significant

Layer 0 is mandatory for every skill edit. Layers 1-3 apply when tests exist for that skill.

## External Tools (Optional)

These tools extend Goaly but are not required. Each has alternatives:

| Tool | Purpose | Alternative |
|------|---------|-------------|
| `gog` CLI | Gmail and Google Calendar access (`gog gmail`, `gog calendar`) | Use any email/calendar integration, or manage manually |
| `qmd` | Semantic search across local markdown files | Use grep/glob for keyword search |
| Granola MCP | Meeting transcripts and AI summaries | Paste transcripts manually into interaction files |
| Branded PDF tool | Generate client-facing PDF documents | Use any PDF generator or skip |
| Notion MCP | Direct Notion API access (optional -- notion-mirror is preferred) | Work entirely with local markdown files |

## Memory System

Persistent memory lives in `.claude-memory/` at the project root. These files carry context across sessions.

| File | Purpose | Update When |
|------|---------|-------------|
| `MEMORY.md` | Concise index loaded into every session (max 200 lines) | New patterns, IDs, or workflow changes |
| `profile.md` | Your personality, preferences, working patterns | New personal insights, preference changes |
| `revenue-strategy.md` | Revenue diversification, pipeline, contract terms | Pipeline changes, new clients, pricing decisions |
| `lead-screening.md` | Red/green flags, screening checklist | New screening patterns or lead types |

Memory files store durable patterns and preferences -- not session-specific state. Update in real-time during sessions, not just at the end.
