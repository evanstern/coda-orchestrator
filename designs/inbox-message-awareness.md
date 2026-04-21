# Design: Inbox-Based Inbound Message Awareness

**Card:** #117
**Status:** Implemented (PR #31)
**Repos:** coda-orchestrator

## Problem

Messages sent via `coda orch send` reach the receiver's opencode serve as a
new HTTP API turn, but the orchestrator agent sitting in an active
conversation never sees them. The user has to manually say "check your logs"
every time. Hook-delivered lifecycle notifications (`50-orch-notify`) have
the same blind spot — they fire `opencode run --attach`, which creates a
background turn the active conversation doesn't know about.

## Approach: Option 3 + Option 4

Two layers:

1. **Inbox file (Option 4):** `coda orch send` appends to the receiver's
   `inbox.md`. The file is listed in the orchestrator's `opencode.json`
   `instructions` array, so the agent sees it automatically on every turn.
   No poll loop, no file watcher, no mid-conversation injection needed.

2. **tmux status bar badge (Option 3):** A shell script counts unread
   entries in `inbox.md` and renders a colored badge in the orch session's
   `status-right`. The user sees new messages even when not actively
   talking to the agent.

The existing `opencode run --attach` path is preserved — the serve still
processes inbound messages as background turns. The inbox is additive.

### Why this works

Smoke-tested: opencode re-reads `instructions` files on every assistant
turn, not just on session start. Adding `inbox.md` to the instructions
array makes its contents visible to the agent whenever the user sends any
message. No upstream changes needed.

### Known limitation

The agent only sees the inbox when the user sends a message (triggering a
new turn). If the user is AFK, messages accumulate silently — the tmux
badge is the only signal. True push-into-active-conversation would require
opencode-level support (event injection or a plugin hook like
`chat.system.transform`). That's a future upstream ask, not in scope here.

## Detailed Design

### 1. Inbox format (`inbox.md`)

Append-only file in the orchestrator's config dir. Each entry:

```markdown
---
from: riley
time: 2026-04-19T22:15:00Z
---
The design review is done. PR #30 merged.
```

Delimiters are `---` lines (YAML-style). The `from` field is the sender's
orch name or `$USER` for non-orch callers. The `time` field is UTC ISO 8601.

When the file is empty (zero bytes), the agent sees nothing extra in its
system context. When entries exist, they appear as part of the instructions
injection — no special parsing needed, the agent reads them as natural text.

### 2. Inbox write in `_orch_send` (`lib/send.sh`)

New helper appended after the existing POST to the serve API:

```bash
_orch_inbox_append() {
    local dir="$1" sender="$2" message="$3"
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '\n---\nfrom: %s\ntime: %s\n---\n%s\n' \
        "$sender" "$ts" "$message" >> "$dir/inbox.md"
}
```

Called from `_orch_send` in both sync and async paths, after the POST
succeeds. The sender is derived from `$CODA_ORCH_NAME` (set in orch
sessions by `_orch_start`) with fallback to `$USER`.

The `opencode run --attach` call is **not replaced** — it still fires so
the serve processes the message in a background turn. The inbox write is
additive.

### 3. Inbox write in lifecycle hooks

Both `hooks/post-session-create/50-orch-notify` and
`hooks/pre-feature-teardown/50-orch-notify` currently only call
`opencode run --attach`. Add an `_orch_inbox_append` call alongside,
using `"hook"` as the sender name and the notification text as the message.

The hooks need access to `_orch_inbox_append`. Options:
- Source a shared `lib/inbox.sh` from the hooks
- Inline the append (it's 4 lines)

Recommendation: inline it in the hooks. They're standalone scripts that
don't currently source any lib modules, and the append logic is trivial.

### 4. `opencode.json` update

Add `inbox.md` to the instructions array. In `_orch_generate_project_config`
(`lib/lifecycle.sh:131`):

```bash
_orch_generate_project_config() {
    local name="$1"
    printf '{"instructions": ["SOUL.md", "MEMORY.md", "PROJECT.md", "inbox.md"]}\n'
}
```

`_orch_start` auto-patches existing `opencode.json` files: on start, if
`inbox.md` is not in the instructions array, append it via `jq`. This
follows the existing pattern at `lifecycle.sh:215-216` where missing
`AGENTS.md` and `opencode.json` are auto-generated. Non-destructive —
only adds, never removes.

### 5. tmux status bar badge (`lib/inbox-status.sh`)

New script:

```bash
#!/usr/bin/env bash
# Outputs a tmux-formatted badge if inbox.md has unread entries.
dir="${1:?}"
inbox="$dir/inbox.md"
[ -s "$inbox" ] || exit 0
count=$(grep -c '^---$' "$inbox" 2>/dev/null)
count=$(( count / 2 ))  # two --- lines per entry (open + close)
[ "$count" -gt 0 ] || exit 0
printf '#[fg=yellow,bold][%d msg%s]#[default] ' \
    "$count" "$([ "$count" -gt 1 ] && echo s)"
```

### 6. tmux `status-right` injection in `_orch_start`

After the `tmux new-session` call at `lib/lifecycle.sh:230`, set a
per-session `status-right` that includes the inbox badge:

```bash
tmux set-option -t "$session" status-right \
    "#($_ORCH_PLUGIN_DIR/lib/inbox-status.sh $dir) #(tmux list-sessions | wc -l | tr -d ' ') sessions | %H:%M"
```

This is per-session (not global), so it only affects orchestrator sessions.
The existing `status-interval 5` in `tmux.conf` means the badge refreshes
every 5 seconds.

### 7. boot-identity inbox read

Add a step to the boot-identity skill between "dreams" and "scope.json":

> ### 6.5. Inbox — pending messages
>
> Check `inbox.md`. If non-empty, these are messages from other agents or
> hooks that arrived while you were offline. Read them, acknowledge them
> in your response, and clear the file after processing.

### 8. Inbox clearing

Two mechanisms:

**Agent-side:** After the agent reads and processes inbox messages, it
truncates the file (writes empty string). This is a normal file write
the agent can do via its tools.

**CLI-side:** New subcommand `coda orch inbox <name> [clear]`:
- No args: prints inbox contents
- `clear`: truncates inbox.md

Registered in `coda-handler.sh` and `plugin.json` (MCP tool).

### 9. `CODA_ORCH_NAME` environment variable

For sender identification, `_orch_start` needs to export `CODA_ORCH_NAME`
into the tmux session environment so that `coda orch send` (called from
within an orch session) can identify who's sending:

```bash
tmux set-environment -t "$session" CODA_ORCH_NAME "$name"
```

The `_orch_send` function reads `$CODA_ORCH_NAME` for the `from` field,
falling back to `$USER`.

## Files Changed

| File | Change |
|------|--------|
| `lib/send.sh` | Add `_orch_inbox_append`, call after POST in both paths |
| `lib/inbox-status.sh` | New script — tmux badge formatter |
| `lib/lifecycle.sh` | Set `status-right` on orch session; set `CODA_ORCH_NAME` env; update `_orch_generate_project_config` to include `inbox.md` |
| `hooks/post-session-create/50-orch-notify` | Add inline inbox append |
| `hooks/pre-feature-teardown/50-orch-notify` | Add inline inbox append |
| `coda-handler.sh` | Add `inbox` subcommand routing |
| `plugin.json` | Register `coda_orch_inbox` MCP tool, add `inbox` to completions |
| `boot-identity` skill | Add inbox.md read step |

## Contract Verification

| Contract item | How it's met |
|---|---|
| Agent is notified when inbound message arrives | `inbox.md` in instructions — agent sees it on next turn automatically |
| No manual "check your logs" prompt required | tmux badge alerts user; instructions injection alerts agent |
| Works for messages via `coda orch send` from any source | Inbox write is in `_orch_send`, the sole send path. Hooks also append. |

## Out of Scope

- File watcher / inotifywait (option 1) — unnecessary given instructions re-read
- Poll loop (option 2) — adds message-queue complexity; instructions path is simpler
- opencode event injection (option 5) — upstream dependency
- Per-message read/unread tracking — clear-all is sufficient for now
- Auto-response to inbox messages without user interaction — requires upstream push support

## Resolved Questions

1. **Existing orchestrators:** `_orch_start` auto-patches `opencode.json`
   to add `inbox.md` if missing. Non-destructive jq append.

2. **Inbox size:** No cap. Agent clears after reading. If accumulation
   becomes a problem in practice, add a cap later.
