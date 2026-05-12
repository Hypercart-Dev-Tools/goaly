# Goaly

A goal-oriented operating system for running a one-person business with Claude Code. 9 skills that keep you oriented around goals, KPIs, and the actions that actually move them.

Everything is markdown files. No database required. No SaaS subscription. Just folders of `.md` files with YAML frontmatter and Claude Code skills that reason over them.

## Quick Start

```bash
git clone https://github.com/Danm72/goaly.git
cd goaly
```

Then in Claude Code:

```
/goaly-setup
```

Answer 5 questions about your goals, KPIs, clients, and working style. The wizard generates all your starter files. Then:

```
/mission
```

Get your first scorecard, task ranking, and spear-sharpening check. No Notion, no API keys, no setup beyond this.

![Cockpit dashboard showing KPI scorecard, task ranking, and spear-sharpening alert](docs/images/goaly-cockpit-dashboard.png)

## What You Get

### 10 Skills

| Skill | What It Does | Trigger |
|-------|-------------|---------|
| `/mission` | Weekly planning (Monday) + daily pulse check | "plan my week", "quick check" |
| `/goaly-triage` | Surface actionable items from calendar + email | "anything I'm missing?" |
| `/goaly-coaching-prep` | Structured agenda for coaching sessions | "prep for coaching" |
| `/goaly-review-meeting` | Transcript → action items → tasks → follow-up | "review notes from [meeting]" |
| `/goaly-meeting-prep` | Build agenda from client history | "prep for [client] meeting" |
| `/goaly-client-email` | Multi-channel client comms (email, Slack, WhatsApp) | "email [client]" |
| `/goaly-screen-lead` | Deep research on inbound leads | "screen this lead" |
| `/goaly-onboard-client` | End-to-end: CRM, contacts, contract, project | "new client [name]" |
| `/goaly-ceo-review` | Strategic scope challenge before building | "review this plan" |
| `/goaly-setup` | First-run wizard — generates all starter files | "set up goaly" |

Plus `linear-product-ops` for Linear board management.

### The Mission

The flagship skill. Every Monday it:

1. **Pulls data** — KPIs, tasks, calendar, email, git activity (all in parallel)
2. **Builds a scorecard** — traffic-light KPI table (green/yellow/red)
3. **Detects patterns** — portfolio concentration, stalled tasks, killed-mammoth syndrome
4. **Budgets energy** — deep work slots available vs committed
5. **Runs a retro** — what shipped, what was planned but untouched, meta-KPIs
6. **Ranks tasks** — impact scoring (max 10 points):

| Criteria | Points |
|----------|--------|
| Moves MRR | +3 |
| Ships product toward paying users | +3 |
| Grows audience/subscribers | +2 |
| Has a hard deadline | +1 |
| Someone external is waiting | +1 |

Top 3-5 tasks become the **Pareto 20%**.

7. **The Spear-Sharpening Check** — if 3+ tasks shipped but zero KPIs moved, it flags: *"You're sharpening the spear instead of hunting the mammoth."*

![Spear sharpening: 14 tasks shipped, 1 KPI moved](docs/images/goaly-spear-sharpening.png)

Weekday pulse mode: just the scorecard, flags, and today's tasks. 2-3 minutes, zero interaction.

## Code Intelligence

This repository integrates **ask-self**, a repo-grounded RAG tool that answers questions about the codebase with citations.

- **Query:** `./scripts/ask-self-query.sh "your question here"`
- **Ingest (Refresh Index):** `./scripts/ask-self-ingest.sh`

Each developer must run the ingest command once before querying; the index lives under `temp/rag/` and is gitignored.

No API key is required for retrieval. It uses Qwen local embeddings (`qwen-local`, requiring `pip install sentence-transformers`). Synthesis defaults to Gemini, but can be skipped using `--retrieval-only` or fully localized.
`ASK_SELF_PATH` can be overridden if ask-self is installed elsewhere.

## Architecture

### Everything Is Markdown

```
notion-mirror/
├── tasks/           # Business actions (YAML frontmatter + markdown body)
├── goals/           # Strategic goals
├── kpis/            # Measurable outcomes with targets
├── projects/        # Bodies of work
├── clients/         # Client CRM data
├── contacts/        # People
├── interactions/    # Meeting notes, emails, calls
├── brainstorms/     # Ideas and exploration
└── personal-tasks/  # Personal actions
```

Each file has YAML frontmatter with properties and a markdown body. See `notion-mirror/README.md` for the full format.

![Goals cascade to KPIs to Projects to Tasks](docs/images/goaly-goal-hierarchy.png)

**Notion is optional.** You can:
- Write files by hand
- Generate them with `/goaly-setup`
- Sync from Notion with `tools/notion-sync`
- Export from any tool that outputs markdown

### Three-Phase Execution

Every skill follows the same pattern:

1. **Collect** — gather all data in parallel (no serial API calls)
2. **Analyze** — reason over collected data (no further I/O)
3. **Interact** — present findings and ask structured questions

![Three-phase execution pattern](docs/images/goaly-three-phase.png)

### Shared Conventions

All skills read `_shared/conventions.md` on startup:
- Local-first search (grep markdown files before hitting APIs)
- Tables not prose (scannable output, structured choices)
- Semantic deduplication (grep before creating)
- Run logging (every skill appends to a run log)
- Session learning (corrections saved to feedback.log, read back next session)

### Memory System

`.claude-memory/` provides persistent context across sessions:
- `MEMORY.md` — concise index loaded every session
- `owner-profile.md` — your working style, strengths, preferences
- `revenue-strategy.md` — pricing, pipeline, diversification rules
- `lead-screening.md` — red/green flags for vetting leads
- `ikigai.md` — 4-dimension alignment filter for tasks and opportunities

## Optional Tools

The core system works with just markdown files and Claude Code. These tools add capabilities:

| Tool | Purpose | Required? |
|------|---------|-----------|
| `tools/notion-sync` | Two-way sync between markdown and Notion | No |
| `tools/email-sync` | Sync Gmail threads to local markdown | No |
| `tools/granola-sync` | Sync meeting transcripts to local markdown | No |
| `gog` CLI | Gmail and Google Calendar access | No — check manually |
| `qmd` | Semantic search across markdown files | No — use grep |
| Granola | Meeting transcripts | No — paste transcripts manually |

## Customization

### Modify Scoring

Edit `.claude/skills/goaly-mission/references/scoring-rules.md` to change how tasks are ranked. The default weights MRR and product shipping highest.

### Add Your Own Skills

Follow the pattern in `.claude/skills/`:
```
.claude/skills/your-skill/
├── SKILL.md       # Instructions and flow
├── gotchas.md     # Failure modes (mandatory)
├── references/    # Supporting data
└── templates/     # Output formats
```

Run `bash tests/validate-skill-structure.sh .claude/skills/your-skill/` to verify structure.

### Change Entity Types

Edit `CLAUDE.md` to modify:
- Default properties for tasks, goals, KPIs, projects
- Impact classification rules
- Project routing table
- SMART enforcement criteria

## Testing

```bash
# Validate all skill structures
for d in .claude/skills/goaly-*/; do bash tests/validate-skill-structure.sh "$d"; done

# Run computation tests for a specific skill
bash tests/mission/test-computations.sh

# Run LLM eval (requires promptfoo)
promptfoo eval -c tests/mission/promptfooconfig.yaml
```

## Project Structure

```
goaly/
├── CLAUDE.md                    # The operating system config
├── .claude/skills/              # 10 skills + shared conventions
├── .claude-memory/              # Persistent memory templates
├── notion-mirror/               # Your business data (markdown files)
├── email-mirror/                # Optional: synced email threads
├── granola-mirror/              # Optional: meeting transcripts
├── dashboards/                  # Generated mission dashboards
├── tools/                       # Notion, email, and Granola sync
├── tests/                       # Skill tests and fixtures
├── clients/templates/           # Contract and meeting templates
├── docs/                        # Reference documentation
└── scripts/                     # Utility scripts
```

## License

MIT

## Credits

Built by [Dan Malone](https://dan-malone.com). Read the full story: [Every Monday I Type /mission — 9 Claude Code Skills That Run My Business](https://dan-malone.com/blog/goaly-9-claude-code-skills-that-run-my-business).
