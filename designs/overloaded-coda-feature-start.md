# Design: Overloaded `coda feature start` with `--orch` flag

## Status: Draft
## Cards: #68 (umbrella), #59 (worktree base), #64 (naming convention)

## Problem

Today there are two ways to start a feature session:

1. **`coda feature start <branch>`** — vanilla CLI. Creates worktree,
   attaches a tmux session with a shell. No IMPLEMENT.md, no AGENTS.md
   prepend, no opencode serve, no auto-trigger. The user manually sets
   everything up.

2. **`coda orch spawn <slug> <brief>`** — orchestrator plugin. Creates
   worktree, writes IMPLEMENT.md, prepends AGENTS.md, starts opencode
   serve, auto-triggers execution. Fully automated but uses its own
   naming convention (`spawn/<slug>`) and duplicates worktree creation
   logic from feature.sh.

This split causes:
- Duplicated worktree/branch creation logic (feature.sh vs spawn.sh)
- Different naming conventions (feature sessions vs spawn sessions)
- No way for a user to say "start a feature session that the orchestrator
  manages" — you either go vanilla or go spawn.
- `coda feature start` doesn't know about orchestrators; `coda orch spawn`
  doesn't reuse the feature command.

## Solution

Add an `--orch <name>` flag to `coda feature start`. When present,
after normal worktree creation, delegate to a well-known hook function
that the orchestrator plugin defines.

### Two execution paths

```
coda feature start 42-auth
  → vanilla path (unchanged)
  → worktree + tmux shell + attach

coda feature start 42-auth --orch zach
  → vanilla worktree creation (reuses all existing logic)
  → then: call _coda_feature_orch_hook()
  → orchestrator plugin writes IMPLEMENT.md, prepends AGENTS.md,
    starts opencode serve, auto-triggers
```

## Changes Required

### 1. coda CLI: `feature.sh` (5-10 lines)

**File:** `~/projects/coda/main/lib/feature.sh`

Parse `--orch <name>` from `_coda_feature_start()` arguments. After
worktree creation and `post-feature-create` hooks (line 86), if
`--orch` was set, call the hook:

```bash
_coda_feature_start() {
    # ... existing arg parsing ...
    local orch_name=""

    # Parse --orch flag from args
    local positional=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --orch) orch_name="$2"; shift 2 ;;
            *)      positional+=("$1"); shift ;;
        esac
    done
    set -- "${positional[@]}"

    local branch="${1:-}"
    local base="${2:-}"
    local project_name="${3:-}"

    # ... existing worktree creation (unchanged) ...

    # Post-create hooks (existing)
    CODA_PROJECT_NAME="$project_name" CODA_PROJECT_DIR="$project_root" \
    CODA_FEATURE_BRANCH="$branch" CODA_WORKTREE_DIR="$worktree_dir" \
        _coda_run_hooks post-feature-create

    # Orchestrator hook (new)
    if [ -n "$orch_name" ] && declare -f _coda_feature_orch_hook &>/dev/null; then
        _coda_feature_orch_hook "$orch_name" "$branch" "$project_name" "$worktree_dir" "$project_root"
        return $?
    fi

    # Vanilla: just attach
    _coda_attach "${project_name}--${branch}" "$worktree_dir"
}
```

Key points:
- `--orch` is parsed before positional args so it can appear anywhere
- If `--orch` is set but no plugin defines the hook function, fall
  through to vanilla attach (graceful degradation)
- The hook receives everything it needs: orch name, branch, project
  name, worktree dir, project root
- When the hook is called, `_coda_attach` is **skipped** — the
  orchestrator manages its own session lifecycle (opencode serve
  instead of shell)

### 2. coda-orchestrator plugin: hook function

**File:** `~/projects/coda-orchestrator/main/lib/spawn.sh` (or new
file `lib/feature-hook.sh`)

Define `_coda_feature_orch_hook()` that replaces the worktree-creation
half of `_orch_spawn()` (which is now handled by `coda feature start`)
and keeps the orchestrator-specific setup:

```bash
_coda_feature_orch_hook() {
    local orch_name="$1"
    local branch="$2"
    local project_name="$3"
    local worktree_dir="$4"
    local project_root="$5"

    local dir="$CODA_ORCH_DIR/$orch_name"
    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $orch_name"
        return 1
    fi

    # 1. Write IMPLEMENT.md (if orchestrator has one staged)
    local staged_brief="$dir/staged-brief.md"
    if [ -f "$staged_brief" ]; then
        cp "$staged_brief" "$worktree_dir/IMPLEMENT.md"
        rm "$staged_brief"
    fi

    # 2. Prepend AGENTS.md with feature-session header
    # (reuse existing logic from _orch_spawn)

    # 3. Add to .gitignore
    # (reuse existing logic from _orch_spawn)

    # 4. Start opencode serve (not tmux shell)
    # (reuse existing logic from _orch_spawn)

    # 5. Auto-trigger if IMPLEMENT.md exists
    # (reuse existing logic from _orch_spawn)
}
```

The key refactor: extract the orchestrator-specific setup (IMPLEMENT.md,
AGENTS.md prepend, .gitignore, opencode serve, auto-trigger) from
`_orch_spawn()` into `_coda_feature_orch_hook`. Then delete
`_orch_spawn` entirely -- it's replaced by
`coda feature start <branch> --orch <name>`.

### 3. Naming convention convergence

Today:
- Vanilla: `coda-<project>--<branch>` (tmux session), `<branch>` (git)
- Spawn: `coda-<project>--spawn-<slug>` (tmux), `spawn/<slug>` (git)

After:
- All feature sessions: `coda-<project>--<branch>` (tmux), `<branch>` (git)
- The `spawn/` prefix and `--spawn-` infix are retired
- Branch naming follows the focus card convention: `<id>-<slug>`
  (e.g. `42-auth-system`)

The `--orch` flag doesn't change the branch or session name — it only
changes what happens *inside* the session (opencode serve vs shell,
IMPLEMENT.md injection, auto-trigger).

`_orch_spawn` is deleted. `coda feature start <branch> --orch <name>`
is the only way to create orchestrator-managed feature sessions.
The orchestrator stages the brief, then calls `coda feature start`.
`coda orch spawn` subcommand is removed from the plugin.

## Session naming

No change to the `coda-<project>--<branch>` convention. The orchestrator
name is NOT embedded in the session name. The orchestrator discovers its
managed sessions via `scope.json` watch patterns, not naming.

This is simpler than the originally proposed
`coda-orch--<orch>--<project>--<branch>` format from the card. That
format was over-specified — the orchestrator already knows which
sessions are its own via scope.json's `watch` field.

## Brief staging

The orchestrator writes IMPLEMENT.md *after* `coda feature start`
creates the worktree, inside `_coda_feature_orch_hook`. Two options
for getting the brief content there:

**Option A: File staging (recommended)**
Orchestrator writes the brief to `$CODA_ORCH_DIR/<name>/staged-brief.md`
before calling `coda feature start`. The hook picks it up and moves
it into the worktree.

**Option B: Pipe/argument**
Pass the brief path as an additional `--brief <path>` flag. Adds
complexity to the coda CLI arg parsing for a plugin concern.

Option A keeps the coda CLI clean — it only knows about `--orch`,
not about briefs.

## Migration

1. Ship the `--orch` flag in coda CLI (small PR, ~10 lines) --
   hand off to coda-core orchestrator. Includes open question
   about hook function loading (eager vs lazy plugin sourcing).
2. Ship `_coda_feature_orch_hook` in coda-orchestrator plugin,
   delete `_orch_spawn` and `coda orch spawn` subcommand.
3. Retire the `spawn/` branch prefix convention.

Steps 1-2 ship as a paired PR across two repos. Step 3 is automatic
(no more code generates `spawn/` prefixes after step 2).

## What this folds in

- **#59 (worktree base):** Vanilla `coda feature start` already creates
  worktrees with files present from the base branch. No additional
  work needed — the bug was that `_orch_spawn` was doing its own
  worktree creation differently. Convergence fixes this.
- **#64 (naming convention):** Retiring `spawn/` prefix. All feature
  sessions use `<id>-<slug>` branch names regardless of whether
  `--orch` is set.

## What this does NOT do

- Plugin command overrides (generic mechanism for plugins to wrap
  built-in commands). That's a bigger lift and not needed here.
- Change to `coda feature done` / `coda feature finish`. Those work
  the same regardless of `--orch`.
- Auto-request Copilot review. That's the orchestrator's job after
  the session opens a PR, not part of session creation.

## Resolved questions

1. **`_orch_spawn` is deleted.** Not deprecated, not wrapped. Replaced
   entirely by `coda feature start <branch> --orch <name>`. The
   `coda orch spawn` subcommand is removed from the plugin.

2. **Hook function loading (answered by coda-core):** The plugin system
   does NOT support an init script today. Plugin handlers are sourced
   lazily on first dispatch via `_coda_plugin_dispatch`. The fix is to
   add an `"init"` field to plugin.json -- e.g.
   `"init": "lib/shell-init.sh"` -- and have `_coda_plugin_load` source
   it during `_coda_plugin_load_all` at shell init. This is ~3 lines
   in `lib/plugin.sh` (coda CLI repo). The orchestrator plugin would
   define `_coda_feature_orch_hook` in its init script so it's available
   before `coda feature start` runs.
   **Prerequisite PR:** coda CLI needs the init field support first.
   Hand off to coda-core orchestrator.

3. **Multiple orchestrators:** The `--orch <name>` flag is explicit --
   you name exactly which orchestrator. No ambiguity.
