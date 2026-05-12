# Goaly — Repo Summary

> Sourced from the ask-self vector index over this repo (553 indexed chunks, last ingest 2026-05-12). Focused on **business coaching** and **project prioritization**, with the rest of the system summarized to give context.

## What Goaly Is

A goal-oriented operating system for running a one-person business with [Claude Code](https://claude.com/claude-code). The entire data model lives as local markdown files with YAML frontmatter — no database, no SaaS subscription, no required API keys. Claude Code skills reason over those files to plan, prioritize, prep meetings, and pressure-test decisions.

Optional Notion sync ([tools/notion-sync/](tools/notion-sync/)) keeps the same markdown mirrored to Notion if you want it, but Goaly works fully standalone.

## Hierarchy (the model everything else hangs off)

```
Goals       — strategic direction ("Where am I heading?")
  └── KPIs        — SMART outcomes ("How do I know I'm getting there?")
        └── Projects   — bodies of work ("What am I building?")
              └── Tasks      — actions ("What do I do today?")
```

Every layer below has hard creation rules — see [CLAUDE.md](CLAUDE.md):

- **Goals** must have ≥1 KPI or they get flagged as "unmeasured" during coaching prep.
- **KPIs** must satisfy full SMART criteria (Specific, Measurable, Achievable, Relevant, Time-bound) — creation is rejected otherwise.
- **Projects** must have a definition of done, a Horizon, and a Goal link.
- **Tasks** must have Timeframe, Energy, Project link, Goal link, and an Impact classification.

## The Skill Set (10 skills + Linear add-on)

| Skill | What It Does | Trigger |
|-------|--------------|---------|
| [`/mission`](.claude/skills/goaly-mission/SKILL.md) | Monday weekly planning OR weekday pulse check | "plan my week", "quick check" |
| [`/goaly-coaching-prep`](.claude/skills/goaly-coaching-prep/SKILL.md) | Pre-coaching agenda with KPIs, accountability, standing items | "prep for coaching" |
| [`/goaly-ceo-review`](.claude/skills/goaly-ceo-review/SKILL.md) | Strategic plan review — challenges scope before you build | "review this plan" |
| [`/goaly-triage`](.claude/skills/goaly-triage/SKILL.md) | Calendar + email triage against existing tasks | "anything I'm missing?" |
| [`/goaly-review-meeting`](.claude/skills/goaly-review-meeting/SKILL.md) | Transcript → action items → tasks → follow-up email | "review notes from X" |
| [`/goaly-meeting-prep`](.claude/skills/goaly-meeting-prep/SKILL.md) | Pre-meeting agenda from client history | "prep for [client] meeting" |
| [`/goaly-client-email`](.claude/skills/goaly-client-email/SKILL.md) | Multi-channel client comms (email, Slack, WhatsApp) | "email [client]" |
| [`/goaly-screen-lead`](.claude/skills/goaly-screen-lead/SKILL.md) | Deep research + vetting on inbound leads | "screen this lead" |
| [`/goaly-onboard-client`](.claude/skills/goaly-onboard-client/SKILL.md) | End-to-end onboarding: CRM, contract, project, time tracking | "new client [name]" |
| [`/goaly-setup`](.claude/skills/goaly-setup/SKILL.md) | 5-question first-run wizard that generates all starter files | "set up goaly" |

Every skill runs a **three-phase pattern**: Collect data in parallel → Analyze with no further I/O → Interact with the user. This keeps latency low and prevents the model from re-reading files mid-reasoning.

---

## Business Coaching — How It Works

Coaching is treated as a distinct lane from regular planning. `/mission` is explicit about it: "Coaching is separate. Use `/goaly-coaching-prep` for [Coach] sessions." Even `/goaly-meeting-prep` redirects: a "prep for [Coach]" trigger stops immediately and points to `/goaly-coaching-prep`.

### [`/goaly-coaching-prep`](.claude/skills/goaly-coaching-prep/SKILL.md) — Pre-Session Agenda

Builds the structured agenda for a bi-weekly coaching session. Eight steps:

1. **Freshness check** — verify `notion-mirror/` is committed.
2. **Parallel data collection** — fired simultaneously across four groups:
   - **A. qmd semantic queries** — last commitments, progress/blockers, deprioritized items
   - **B. Grep frontmatter** — active goals/KPIs/projects, done/in-progress/planned/deprioritized tasks, plus any task containing a `## Coaching Accountability` section (the "frog" tasks)
   - **C. File reads** — MEMORY.md + most recent Granola coaching transcript
   - **D. Read all matched files** in parallel after B/C return
3. **Flag unmeasured goals & deprioritized items** — any active goal with zero linked KPIs gets flagged as `(unmeasured)`. Stalled tasks (`_notion_edited` > 14 days) surface for discussion.
4. **Collect KPI values** via `AskUserQuestion` — structured choices per active KPI. **MRR is a standing question every session** (never assumed, never derived from rate × hours).
5. **Update KPI files** — edit only `current_value:`, never the read-only `_` fields. Commit KPI updates separately so the sync stays clean.
6. **Standing items** — pulled live from the "Coaching Prep — Standing Items" section of MEMORY.md (not hardcoded).
7. **Coaching Accountability Surface** — tasks with `## Coaching Accountability` sections in their body are tracked across sessions:

   | Task | Status | Sessions | First Committed | Days Stalled | Frog Type |
   |------|--------|----------|-----------------|--------------|-----------|

   Sorted by sessions-committed DESC. Anything committed 3+ sessions is flagged: *"RECURRING STALL — discuss pattern, not just task"*. Anything completed since last session is celebrated: *"FROG EATEN: [task]"*.
8. **Memory enrichment** — after the session, new insights flow back into `dan-profile.md`, `revenue-strategy.md`, or new standing items in MEMORY.md.

### Key Coaching Gotchas

From [.claude/skills/goaly-coaching-prep/gotchas.md](.claude/skills/goaly-coaching-prep/gotchas.md):

- Always ask for MRR — never assume it.
- Always check for unmeasured goals (goal with zero KPIs).
- Always re-read standing items from MEMORY.md fresh — they change between sessions.
- Granola queries must include deprioritized items to avoid resurrecting dead work.
- Commit KPI value changes as a separate commit from anything else.

### Coaching Loop in `/mission`

`/mission` doesn't run the coaching agenda itself, but it feeds it via the **Frog Streak** pattern detector in Step 5:

> Coaching-tagged tasks still "Not started" with sessions-committed > 1 → flag.
> Output: "X frog tasks stalled across Y coaching sessions."

And Step 5b surfaces **today's frog**:

```
🐸 TODAY'S FROG: [task title]
   Committed: [N] coaching sessions ([dates])
   Days stalled: [N]
   First step: [from "First micro-step" in task body]
```

Selection priority: highest sessions-committed → oldest `_notion_edited` → energy match for the day.

---

## Project Prioritization — How It Works

Prioritization is concentrated in three places: the **Impact classification** rules in [CLAUDE.md](CLAUDE.md), the **task ranking + pattern detection** in `/mission`, and the **scope challenge** in `/goaly-ceo-review`.

### 1. Impact Classification (applied at task creation)

Every task gets one of three Impact ratings, auto-assigned where possible:

| Impact | Color | Definition | Examples |
|--------|-------|------------|----------|
| **Needle Mover** | Red | Directly advances a KPI | Close retainer, ship MVP, publish post |
| **Supporting** | Yellow | Enables/unblocks a Needle Mover | Prep, research, SOW writing |
| **Maintenance** | Gray | Keeps the lights on | Tax filing, bookkeeping, tooling |

Auto-classification rules:
- Task linked to a KPI → **Needle Mover**
- Task linked to a Goal but supporting (prep/research/setup) → **Supporting**
- Task in Operations project with no Goal link → **Maintenance**
- Client work that closes/grows revenue → **Needle Mover**
- Client work that's admin/setup → **Supporting**

### 2. Ikigai Alignment Filter (applied to every new task)

Score each task against 4 dimensions ([.claude-memory/ikigai.md](.claude-memory/ikigai.md)):

| Dimension | Question |
|-----------|----------|
| **Love** (Energy) | Does this energize me? |
| **Good At** (Competence) | Am I the right person? |
| **Needs** (Impact) | Does this create real value? |
| **Paid For** (Revenue) | Does this generate revenue? |

| Score | Verdict |
|-------|---------|
| 4/4 or 3/4 | Core work — prioritize aggressively |
| 2/4 | Supporting work — acceptable |
| 1/4 | Misaligned — consider delegating or declining |
| 0/4 | Red flag — ask before creating |

This filter is **visibility, not a gate** — admin/maintenance tasks legitimately score low. Its purpose is to catch *vanity tasks* (organizing the board instead of doing the work) and tasks that linger because they aren't connected to anything that matters.

### 3. Weekly Task Ranking (`/mission` MONDAY mode, Step 9)

Candidate set: every task with status `Not started`, `Planned this week`, or `In progress`. Each is scored on a 10-point scale:

| Criteria | Points |
|----------|--------|
| Moves MRR | +3 |
| Ships product toward paying users | +3 |
| Grows audience/subscribers | +2 |
| Has a hard deadline | +1 |
| Someone external waiting | +1 |

Presented as `Rank | Task | Project | Impact | Energy | Score`, then `AskUserQuestion` with multiSelect (pre-selected by score). Confirmed picks → `Planned this week`. The rest → `Not started`.

> The top 3-5 tasks are the **Pareto 20%** — protected time above all else.

### 4. Pattern Detection (`/mission` Step 5, all modes)

Six failure-mode detectors run on every mission, with no extra I/O — they reuse the data already collected in Step 2:

| Check | Flag When |
|-------|-----------|
| **Portfolio Concentration** | Any client > 50% MRR, or < 3 revenue sources |
| **KPI Staleness** | `_notion_edited` overdue vs tracking_frequency |
| **Initiation Avoidance** | `_notion_edited` > 14 days on active tasks |
| **Killed Mammoth** | No interaction with a client 14+ days, or accepted lead with no follow-up |
| **Frog Tasks** | Planned/Not started with `_notion_edited` > 14 days |
| **Frog Streak** | Coaching-tagged tasks still "Not started" across multiple coaching sessions |

### 5. Energy Budget (`/mission` MONDAY mode, Step 7)

Compares deep-work capacity against committed deep-work tasks for the week:

```
Available Deep Work slots = (free weekdays - meeting days) × 2
Committed                 = count of energy: Deep Work tasks in Planned/In progress
Remaining                 = Available - Committed
```

Output is a table plus a recommendation (`Room for N more` or `Overcommitted by N`).

### 6. The Spear-Sharpening Check (`/mission` retro)

If 3+ tasks shipped last week but **zero KPIs moved**, the system fires a single line: *"You're sharpening the spear instead of hunting the mammoth."* This is the highest-signal anti-busywork detector in the system — it short-circuits the temptation to feel productive while not actually advancing anything that matters.

### 7. Strategic Plan Review — [`/goaly-ceo-review`](.claude/skills/goaly-ceo-review/SKILL.md)

A read-only "fractional CTO" lens. Used **before** you start building something. Three explicit postures (chosen up front, never blended):

| Mode | Posture |
|------|---------|
| **SCOPE EXPANSION** | Dream big — what's the 10-star version? |
| **HOLD SCOPE** | Maximum rigor — find critical gaps, missing acceptance criteria, rollback plans |
| **SCOPE REDUCTION** | Strip to essentials — produce a "cut" and "keep" list, find gold-plating |

Step 1 is the **Nuclear Scope Challenge** — five questions that pressure-test the premise before the plan itself:

1. "What is the 10-star version of this?"
2. "What would you build with zero existing code?" *(sunk-cost check)*
3. "Who specifically will use this, and what will they stop doing?" *(no named user = hypothesis, not feature)*
4. "What's the simplest version that would make someone say 'holy shit'?" *(not MVP — minimum impressive version)*
5. "Is this a feature, a product, or a business?"

After that: ikigai scoring, single-source-revenue check, and a handoff to `/brainstorm` or `/plan`. The skill **never writes code, never creates tasks**. All outputs are advisory text.

Key guardrails from [.claude/skills/goaly-ceo-review/gotchas.md](.claude/skills/goaly-ceo-review/gotchas.md):
- Challenge scope creep — ask "is this [Owner]'s problem to solve?" and "what's being sacrificed?"
- Score every plan against ikigai. Below 2/4 → do not proceed without explicit confirmation.
- Flag single-source revenue risk. Principle: 3-4 revenue sources minimum.
- Postures don't blend — mixing them produces incoherent advice.

---

## Supporting Infrastructure

- **Memory system** — [.claude-memory/](.claude-memory/) holds durable patterns: `MEMORY.md` (index), `profile.md`, `revenue-strategy.md`, `lead-screening.md`, `ikigai.md`. Updated in real-time during sessions, not just at the end.
- **ask-self** (this tool) — repo-grounded RAG over the codebase + notion-mirror, queried via [scripts/ask-self-query.sh](scripts/ask-self-query.sh). Used for session-start orientation and cross-file questions.
- **Run logs** — Each frequently-run skill appends a JSONL row to its own `data/run-log.jsonl` (gitignored) so meta-KPIs (execution rate, energy, MRR confirmed, flags) can be tracked over time.
- **Three-layer test suite** per skill: bash computations, promptfoo LLM eval, and a manual smoke-test checklist.
- **External tools (all optional)** — `gog` (Gmail/Calendar CLI), `qmd` (semantic search over markdown), Granola MCP (meeting transcripts), Notion MCP, branded-PDF generator.

## Index Stats

- 229 files indexed, ~49,792 LOC
- Markdown (125 files) and TypeScript (45 files) dominate
- Branch at ingest: `main` @ `dab385e` (2026-03-23)
- Embed model: `Qwen/Qwen3-Embedding-0.6B` (dim=1024), 553 chunks
