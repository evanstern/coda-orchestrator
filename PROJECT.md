# PROJECT.md — coda-orchestrator

## Vision

coda-orchestrator is the project management layer for coda-managed
projects. It provides a persistent, personality-driven agent that
serves as Product Manager and Lead Architect — brainstorming with
the user, producing specs, coordinating feature sessions, and
maintaining architectural coherence across parallel work streams.

## Architecture

The orchestrator is configuration, not code. It runs as an opencode
session with personality and behavior defined by markdown files:

```
SOUL.md        — identity, role, attitude, workflows, boundaries
PROJECT.md     — project vision, architecture, priorities (this file)
MEMORY.md      — curated learnings and patterns
PERSONALITY.md — living personality (islands + core memories)
memory/        — daily observation logs
designs/       — feature design documents
scope.json     — session watch/ignore patterns
opencode.json  — opencode configuration
AGENTS.md      — operating instructions for the agent
```

## Current Priorities

1. **#90 Window milestone** (P1) — session windows (#92), attach/watch
   (#93), status-line (#94)
2. **#79 Monorepo path fix** (P1) — update orch tooling for
   personalities monorepo layout
3. **#85 Question/answer loop** (P2) — fill gaps via interactive Q&A

## Shipped

- **#29 Soul-writer skill** — SOUL.md template + generation (PR #26)
- **#30 Evolving personality** — reflection, dreams, personality
  islands (PR #26)
- **#76 Session pruning** — prune primitives for opencode serve (PR #29)
- **#77 Automated PR lifecycle** — Copilot review loop (PR #30)
- **#87 Feature session teardown** — self-report, postmortem, inbox
  delivery (PR #36)
- **#104-106 Wiki** — first-class memory protocol (PR #35)

## Conventions

- Feature work happens on `coda feature` branches, not in the
  orchestrator session
- The orchestrator proposes, the user approves (propose-and-wait)
- Design docs go in `designs/<slug>.md`
- Focus cards track work items (when `focus` CLI is available)
- Daily memories go in `memory/YYYY-MM-DD.md`
