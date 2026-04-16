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
memory/        — daily observation logs
designs/       — feature design documents
scope.json     — session watch/ignore patterns
opencode.json  — opencode configuration
AGENTS.md      — operating instructions for the agent
```

## Current Priorities

1. **SOUL.md rewrite** — establish the PM/architect role and section
   schema (in progress)
2. **Soul-writer skill** (#29) — automate SOUL.md creation for new
   orchestrator instances
3. **Evolving personality system** (#30) — make the orchestrator's
   personality grow through accumulated experience

## Conventions

- Feature work happens on `coda feature` branches, not in the
  orchestrator session
- The orchestrator proposes, the user approves (propose-and-wait)
- Design docs go in `designs/<slug>.md`
- Focus cards track work items (when `focus` CLI is available)
- Daily memories go in `memory/YYYY-MM-DD.md`
