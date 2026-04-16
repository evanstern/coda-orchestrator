# Design: Feature Session Spawn Pattern

## Status: Validated
## Cards: #38, #39, #31

## Problem

Spawning a feature session and briefing it reliably requires:
1. A standard briefing format the session understands at boot
2. A reliable trigger mechanism (not tmux send-keys)
3. Atomic setup before the session starts

## Naming Convention

- **Branch name:** `<id>-<slug>` (e.g. `47-focus-id-in-branch-names`)
- **Session name:** `coda-<project>--<id>-<slug>` (e.g. `coda-coda-orchestrator--47-focus-id-in-branch-names`)

The focus card ID is always the leading element. This makes it trivial to
correlate branches, sessions, and PRs back to the card that tracks them.

## Key Discovery

`opencode run --attach http://localhost:<port> --format json "message"` works.

Verified live: sent a message to the running orchestrator session via its port
file and received a full streamed JSON response. No tmux. No pane targeting.
No Enter keystroke issues.

The ACP (Agent Client Protocol) stream emits JSON events:
- `{"type":"text", ..."text":"..."}` -- agent response chunks
- `{"type":"step_finish", ..."reason":"stop"}` -- completion signal

This is the mechanism for #38. tmux send-keys is retired.

## IMPLEMENT.md Brief Template

Every IMPLEMENT.md written for a spawned session MUST start with:

```markdown
# IMPLEMENT.md

You are a feature implementation agent. The brief below is complete.
Do NOT explore, research, or ask clarifying questions.
Build exactly what is described. If something is unclear, make a
reasonable assumption and note it in your PR description.

When you receive "execute", start immediately.
Report "PR ready: <url>" when done.

---
```

## PR Body Template

Every PR opened by a feature session should include:

```markdown
### Focus
Card: #<id>
Title: <card title>

### Summary
<what was done>
```

This links the PR back to its focus card and gives reviewers immediate
context without reading the full diff.

## Anti-Exploration Rule

The anti-exploration instruction is non-negotiable. Without it, sessions
tend to spend 10+ tool calls on research before writing a single line.
At scale with automated spawning, that burns tokens silently with no
human to intervene.

## The Pattern

### Phase 1: Prepare (before session boots)

```bash
# Write brief to worktree before coda feature start
cat > /path/to/worktree/IMPLEMENT.md << 'EOF'
# IMPLEMENT.md
You are a feature session. Read this file at boot.
When you receive "execute", carry out this task:
<task description>
Report back "PR ready: <url>" when done.
EOF

# Prepend AGENTS.md with feature-session header
cat - /path/to/worktree/AGENTS.md > /tmp/agents_tmp << 'EOF'
# FEATURE SESSION
Read IMPLEMENT.md at startup. Execute when triggered.
---
EOF
mv /tmp/agents_tmp /path/to/worktree/AGENTS.md

# Gitignore instance-level files
printf 'IMPLEMENT.md\nAGENTS.md\n*.feature-brief.md\n' >> /path/to/worktree/.gitignore
```

### Phase 2: Boot

```bash
source ~/projects/coda/main/shell-functions.sh
_coda_feature start <id>-<slug>
# Session boots with IMPLEMENT.md and AGENTS.md prepend already in place
```

### Phase 3: Trigger (via opencode run --attach)

```bash
# Wait for port file to appear
WORKTREE=/home/coda/projects/<project>/<id>-<slug>
while [ ! -f "$WORKTREE/port" ]; do sleep 1; done
PORT=$(cat "$WORKTREE/port")

# Send trigger and stream response
opencode run --attach http://localhost:$PORT --format json "execute"
```

### Phase 4: Monitor for completion

```bash
# Parse ACP stream for completion signal in text events
opencode run --attach http://localhost:$PORT --format json "execute" | \
  python3 -c "
import sys, json
for line in sys.stdin:
    try:
        event = json.loads(line)
        if event.get('type') == 'text':
            text = event['part'].get('text', '')
            print(text, end='', flush=True)
            if 'PR ready:' in text:
                sys.exit(0)
    except:
        pass
"
```

## The AGENTS.md Prepend Convention

The feature-session header that goes at the top of AGENTS.md:

```markdown
# FEATURE SESSION

You are a feature implementation agent, NOT the orchestrator.
Your task brief is in IMPLEMENT.md in this directory.
When you receive "execute", immediately run: read @IMPLEMENT.md and follow its instructions exactly.
Report back "PR ready: <url>" when done. Never ask clarifying questions.

---
```

The `@IMPLEMENT.md` reference is critical -- it forces the session to load
the file directly rather than interpreting "execute" ambiguously.

This must be gitignored -- it is instance-level context, not repo content.

## Future: coda orch spawn

Once phases 1-4 are reliable and scripted, wrap as:

```bash
coda orch spawn <id>-<slug> --brief IMPLEMENT.md [--wait] [--timeout 30m]
```

Internally this runs phases 1-4. With `--wait` it blocks until "PR ready:"
appears in the stream. Without it, fires and returns the session URL.

## Answers to Prior Open Questions

- **Does opencode expose an HTTP message API?** Yes -- `opencode run --attach`
  uses the ACP protocol on the serve port. Full JSON event stream.
- **Completion signal format?** Text event containing "PR ready: <url>"
  is sufficient. Can add structured signals later.
- **How does orchestrator know the port?** Port file at `<worktree>/port`,
  written by opencode on startup. Consistent and reliable.
- **tmux send-keys?** Retired. HTTP only going forward.
