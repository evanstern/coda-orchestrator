# coda-orchestrator

A coda plugin that implements the **orchestrator pattern**: named, scoped, personality-driven agents that observe and manage slices of your coda sessions.

## Core Concepts

- **Orchestrator** = a named `opencode serve` instance in its own tmux session (`coda-orch--<name>`)
- **Soul** = SOUL.md defining personality, tone, boundaries, generated from plain speech or hand-written
- **Scope** = tmux session name glob patterns (e.g. `coda-myapp--*`) defining what it watches
- **Memory** = plain markdown files the agent reads/writes for continuity across sessions

## Architecture

```
plugin.json              # Manifest: commands, hooks, MCP tools
coda-handler.sh          # Shell dispatcher for `coda orch <sub>`
lib/
  lifecycle.sh           # new, start, stop, ls, done
  soul.sh                # Soul generation + editing
  observe.sh             # Session status collection within scope
  send.sh                # Prompt dispatch via opencode run --attach
defaults/
  SOUL.md.tmpl           # Default soul template
  scope.json.tmpl        # Default scope (all sessions, ignore services)
hooks/
  post-session-create/   # Notify orchestrators on new sessions
  pre-feature-teardown/  # Notify orchestrators on feature cleanup
```

Per-orchestrator runtime state lives at `~/.config/coda/orchestrators/<name>/`.

## Key Invariants

- Orchestrators use `opencode serve` as primary interaction mechanism, NOT `tmux send-keys`
- Scope is defined by tmux session name globs — the naming convention IS the addressing scheme
- Multiple orchestrators can run simultaneously with independent scopes
- Soul/memory are plain files — no database, no hidden state
- The plugin doesn't touch coda core — everything goes through the plugin system

## Testing

Test lifecycle paths: new, start (verify port file + tmux session), stop (verify cleanup), done (verify removal), done --archive (verify archive).
