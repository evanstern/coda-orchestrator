# Copilot Instructions -- coda-orchestrator

## What This Repo Is

This is the coda-orchestrator plugin. It provides the `coda orch` command
family for managing persistent, memory-bearing AI orchestrator instances.

## Tracked Files

Everything in this repo is tracked unless explicitly listed in .gitignore.
Key areas:

- `coda-handler.sh` -- plugin entrypoint (command dispatcher)
- `plugin.json` -- plugin manifest
- `AGENTS.md` -- instance-level operating instructions
- `lib/` -- all modules: lifecycle, soul, send, spawn, inbox, inbox-status,
  prune, status, shell-init, feature-hook
- `hooks/` -- lifecycle hooks (post-session-create)
- `tests/` -- bats test files
- `designs/` -- feature design documents
- `defaults/` -- templates (SOUL.md.tmpl, PERSONALITY.md.tmpl, scope.json.tmpl)
  and skills (boot-identity, triage-work)
- `bin/` -- utility scripts (safe-commit.sh)
- Core config: `SOUL.md`, `PROJECT.md`, `MEMORY.md`, `opencode.json`,
  `scope.json`, `README.md`
- `memory/`, `learnings/`, `dreams/` -- observation and reflection logs

## Gitignored (do NOT flag as missing)

- `node_modules/`, swap files (*.swp, *.swo, *~), `.DS_Store`
- `port` -- runtime state file (written by `coda orch start`)
- `IMPLEMENT.md` -- ephemeral feature session briefs
- `*.feature-brief.md` -- scratch planning files

## SOUL.md Two-Zone Convention

SOUL.md has two zones:
- **Core Identity** -- locked, only the user modifies this
- **Personality** -- evolves through `/reflect` proposals, approved by user,
  committed via branch+PR

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
