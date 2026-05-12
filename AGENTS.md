# Goaly Agent Instructions

## Code Intelligence (ask-self)

ask-self is an external, repo-grounded RAG tool that provides intelligent context and answers about this workspace.

**Command:**
`./scripts/ask-self-query.sh "your question here"`

> Before grep-spelunking or asking the user to re-explain repo context, query ask-self first.

**When to use it:**
- Session-start orientation
- Unfamiliar subsystems
- Pronoun-heavy user references such as "that helper" or "the auth flow"
- Cross-file behavior questions

**When not to use it:**
- Trivial single-file reads
- Tight edit-test loops
- Questions about current uncommitted state

**Staleness note:** The index reflects the last ingest; a committed shared index is a baseline and may lag active branch work.

**Override note:** `ASK_SELF_PATH` (default: `/path/to/ask-self`) can be overridden through the environment if needed.
