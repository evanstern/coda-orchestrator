---
name: triage-work
description: Triage focus cards before acting. Determines whether each card needs design, a feature session, or inline work. Use when the user says "start work on X" or references one or more focus cards for implementation.
---

# Triage Work

When the user requests work on one or more focus cards, DO NOT jump
straight to spawning feature sessions. Run this triage first.

## Step 1: Load the cards

For each card ref the user mentioned, run `focus show <ref>` to get
the full card: title, status, contract items, body, files.

## Step 2: Triage each card

Apply this decision tree independently per card:

### Is the card specced?

A card is specced if it has:
- Contract items (clear definition of done)
- A body with enough detail to act on
- Files or areas of change identified

If NOT specced --> the card needs design work first. Do not spawn a
session. Tell the user what's missing and offer to help spec it.

### Is it big enough for a feature session?

A feature session means: branch + worktree + PR + Copilot review.
That overhead is justified when:
- Changes touch project repo code (not just config/memory)
- Multiple files or non-trivial logic changes
- A PR review adds value

If YES --> feature session. Follow the feature session flow below.

If NO --> inline work. Apply the inline vs. branch rule:
- `memory/`, `learnings/` -- safe to commit directly on main
- Everything else -- requires a feature branch and PR
- When unsure, default to branch

## Step 3: Propose the plan

Present a single triage summary to the user:

```
Triage: <N> card(s)

  #<id> <title>
    Verdict: <feature session | inline | needs design>
    Reason: <one line>

  #<id> <title>
    ...

Proposed action: <what you'll do>
```

Wait for user approval before taking any action.

## Feature session flow

When triage says "feature session" and the user approves:

1. `coda feature start <id>-<slug> <project_dir>` -- create branch +
   worktree + session
2. Write IMPLEMENT.md brief to the worktree. The brief MUST start with:
   "The brief is complete. Do not explore. Build what is described."
3. Prepend AGENTS.md if the project has one
4. Tell the user: session is ready, trigger with
   "read @IMPLEMENT.md and execute"
5. After PR opens, kick off copilot-review-watcher if available
6. After PR merges: `focus done <id> --force`, clean up worktree

## Multiple cards

When the user requests work on multiple cards at once:
- Triage ALL cards before acting on ANY
- Present one combined proposal
- Wait for approval on the whole plan
- Then execute in order

## When to use this skill

- User says "start work on #X" or "implement card X"
- User says "work on these cards" with multiple refs
- User asks to kick off a feature from a focus card
- Any transition from "card exists" to "work begins"
