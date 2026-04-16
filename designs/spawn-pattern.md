# Design: Feature Session Spawn Pattern

## Status: Draft
## Cards: #38, #39, #31

## Problem

Spawning a feature session and briefing it reliably requires:
1. A standard briefing format the session understands at boot
2. A reliable trigger mechanism (not tmux send-keys)
3. Atomic setup before the session starts

Today all three are manual and error-prone.

## The Pattern

### Phase 1: Prepare (before session boots)

```bash
# 1. Write brief
cat > worktree/IMPLEMENT.md << 'EOF'
# IMPLEMENT.md
You are a feature session. When you receive "execute", carry out this task:
<task description>
Report back "PR ready: <url>" when done.
EOF

# 2. Prepend AGENTS.md
cat > worktree/AGENTS.md.prepend << 'EOF'
# FEATURE SESSION
Read IMPLEMENT.md and execute when triggered.
---
EOF
cat worktree/AGENTS.md.prepend worktree/AGENTS.md > /tmp/agents_tmp
mv /tmp/agents_tmp worktree/AGENTS.md

# 3. Update .gitignore
echo -e 'IMPLEMENT.md\nAGENTS.md\n*.feature-brief.md' >> worktree/.gitignore
```

### Phase 2: Boot

```bash
coda feature start <name>
# Session reads AGENTS.md at startup -- brief is already in place
```

### Phase 3: Trigger (via HTTP API, not tmux)

```bash
# Wait for port file
while [ ! -f worktree/port ]; do sleep 1; done
PORT=$(cat worktree/port)
curl -s http://localhost:$PORT/api/message \
  -X POST -H 'Content-Type: application/json' \
  -d '{"content": "execute"}'
```

### Phase 4: Monitor

```bash
# Poll for completion signal via API or port-based log stream
# Session reports "PR ready: <url>" when done
```

## Future: coda orch spawn

Once phases 1-4 are reliable and automated, wrap them as:

```bash
coda orch spawn <name> --brief IMPLEMENT.md [--wait]
```

The lessons from manual implementation inform what spawn needs:
- Brief-before-boot (not brief-as-message)
- HTTP API trigger (not tmux)
- Structured completion signal ("PR ready: <url>")
- Optional --wait flag for blocking vs. fire-and-forget

## Open Questions

- Does opencode expose an HTTP message API on the port? Need to verify.
- Should the completion signal be a specific string or a structured response?
- How does the orchestrator know which port belongs to which session?
  (Answer: port file in the worktree, named consistently)
