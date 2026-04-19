# coda-orchestrator

A [coda](https://github.com/evanstern/coda) plugin that turns AI sessions into
persistent, memory-bearing agents. Each orchestrator has its own identity,
memory, scope, and inbox — and survives across conversations.

## What it does

- **Multi-instance orchestration** — run several named orchestrators at once,
  each with its own personality and project scope
- **Persistent identity** — SOUL.md, MEMORY.md, and daily memory logs give
  each agent continuity across sessions
- **Agent-to-agent messaging** — `coda orch send` delivers messages to a
  running orchestrator; replies land in an inbox the agent sees automatically
- **Session lifecycle hooks** — orchestrators are notified when sessions in
  their scope are created or torn down
- **Session pruning** — stale opencode serve sessions are cleaned up
  automatically on start

## Requirements

- [coda](https://github.com/evanstern/coda) CLI installed
- [opencode](https://opencode.ai) installed and on `$PATH`
- `jq`, `git`, `tmux`

## Installation

```bash
coda plugin install git@github.com:evanstern/coda-orchestrator.git
```

This registers the `coda orch` subcommand family and installs lifecycle hooks.

## Usage

### Create and start an orchestrator

```bash
coda orch new riley --soul "Product manager and architect for coda-orchestrator" \
                   --scope "coda-coda-orchestrator--*"
coda orch start riley
```

This creates a config directory at `~/.config/coda/orchestrators/riley/` with
a SOUL.md, MEMORY.md, scope.json, and opencode.json, then starts an opencode
serve instance in a tmux session named `coda-orch--riley`.

### Send a message

```bash
# Synchronous (waits for response)
coda orch send riley "What's the status of the #90 milestone?"

# Async (fire and forget, response logged)
coda orch send riley "Design review needed on PR #31" --async
```

Messages are delivered to the orchestrator's opencode serve and also appended
to its `inbox.md`. The agent sees the inbox automatically on every turn
(opencode re-reads instruction files per turn).

### Check inbox

```bash
coda orch inbox riley        # show pending messages
coda orch inbox riley clear  # clear after reading
```

### Other commands

```bash
coda orch ls                     # list all orchestrators and status
coda orch status riley           # show sessions in scope
coda orch edit riley             # open SOUL.md in editor
coda orch prune riley            # clean up stale opencode sessions
coda orch done riley             # tear down and remove
coda orch done riley --archive   # tear down and archive
```

## Orchestrator anatomy

Each orchestrator lives at `~/.config/coda/orchestrators/<name>/`:

```
<name>/
  SOUL.md          # identity: name, role, personality, workflows
  MEMORY.md        # curated long-term memory
  PROJECT.md       # project vision and priorities (optional)
  AGENTS.md        # bootstrap instructions for the agent
  opencode.json    # instructions array, loaded by opencode serve
  scope.json       # glob patterns for session watch/ignore
  inbox.md         # inbound messages (auto-cleared by agent)
  port             # active serve port (present when running)
  session-id       # active opencode session ID
  memory/          # daily observation logs (YYYY-MM-DD.md)
  learnings/       # session insights pending promotion
  dreams/          # reflection artifacts
  logs/            # send/spawn logs
```

## Identity and memory

Orchestrators use the `/boot-identity` skill (installed automatically) to load
their identity at session start. The skill reads SOUL.md, MEMORY.md, PROJECT.md,
recent memory logs, learnings, dreams, and inbox in order.

Memory policy:
- `memory/` and `learnings/` — commit inline on main
- Everything else — feature branch + PR
- Commit every memory write immediately; memory loss on crash is unacceptable

## Hooks

The plugin registers two lifecycle hooks:

| Event | Hook | What it does |
|---|---|---|
| `post-session-create` | `50-orch-notify` | Notifies matching orchestrators when a new session is created |
| `pre-feature-teardown` | `50-orch-notify` | Notifies matching orchestrators before a feature session tears down |

Matching is done against `scope.json` watch patterns (glob, not regex).

## Feature sessions

To spawn a feature session scoped to an orchestrator:

```bash
coda feature start <branch> --orch <name>
```

This creates the worktree and session, injects an IMPLEMENT.md brief, and
auto-triggers the feature agent. The orchestrator is notified via hook.

> **Note:** The `--orch` flag requires a matching entry in the coda CLI.
> See card #100 if this flag appears broken.

## tmux status bar

When an orchestrator session is running, its tmux `status-right` shows a
yellow `[N msgs]` badge when `inbox.md` has unread entries. Refreshes every
5 seconds.

## Tests

```bash
bats tests/
```

Requires [bats-core](https://github.com/bats-core/bats-core).

## License

MIT
