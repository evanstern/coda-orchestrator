# Copilot Instructions -- coda-orchestrator

## What This Repo Is

This is an orchestrator config repo, not a typical code project.
It contains configuration and personality files for "Zach" -- an AI
orchestrator instance that acts as PM and Lead Architect for the
coda-orchestrator project.

The orchestrator plugin may install managed files into this repo's working
tree, but they are gitignored and not tracked. Only config-layer files are
tracked here.

## Tracked Files (config layer)

- `SOUL.md` -- Zach's identity and personality (two-zone: Core Identity + Personality)
- `PROJECT.md` -- project vision, architecture, priorities
- `MEMORY.md` -- curated learnings
- `memory/` -- daily session logs
- `learnings/` -- raw session insights
- `designs/` -- feature design documents
- `scope.json` -- session watch/ignore patterns
- `opencode.json` -- opencode configuration
- `lib/spawn.sh` -- spawn functionality (tracked)
- `tests/` -- test files for tracked functionality

## Intentionally Gitignored (never flag as missing)

These files exist on disk but are NOT tracked by git:
- `coda-handler.sh` -- plugin entrypoint (managed by plugin install)
- `lib/lifecycle.sh`, `lib/observe.sh`, `lib/send.sh`, `lib/soul.sh`, `lib/ui.sh` -- plugin code
- `plugin.json` -- plugin manifest
- `hooks/` -- lifecycle hooks
- `defaults/` -- default templates (except SOUL.md.tmpl which is tracked)
- `tests/lifecycle.bats` -- plugin tests
- `AGENTS.md` -- instance-level operating instructions (gitignored by design)
- `IMPLEMENT.md` -- feature session briefs (gitignored by design)
- `*.feature-brief.md` -- scratch files
- `port` -- runtime state

Do NOT flag any of the above as missing or suggest adding them.

## SOUL.md Two-Zone Convention

SOUL.md has two zones:
- **Core Identity** -- locked, only the user modifies this
- **Personality** -- evolves through `/reflect` proposals, approved by user, committed via branch+PR

Changes to SOUL.md always require a branch + PR. Never commit directly to main.

## Inline vs. Branch Rule

See `designs/inline-vs-branch.md` for the full rule.
Short version:
- `memory/`, `learnings/` -- safe to commit inline on main
- Everything else -- requires a feature branch and PR

## git rm Safety

Always use `git rm --cached` to untrack files.
Never use plain `git rm` -- it deletes files from disk and breaks the live plugin.

## Spawn Naming Convention

Spawned feature branches follow `spawn/<slug>` pattern.
Session names become `coda-<project>--spawn-<slug>`.

## Testing

Run tests with: `bats tests/`
Tests live in `tests/*.bats`.
