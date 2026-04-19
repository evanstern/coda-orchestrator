# Cross-repo patch: `coda feature done` session cleanup

**Status:** Design artifact / handoff. **NOT a PR from this repo.**
**Target repo:** `evanstern/coda` (coda-core).
**Tracks:** card #76 (session pruning).

## Handoff note

This file describes a change that belongs in `evanstern/coda`, which is
coda-core's repo, not ours. Escalate to Zach (cross-repo coordinator)
for routing before opening a PR. This orchestrator-side work lands
first; the bridge follows once coda-core signs off.

## What needs to change in `coda/lib/feature.sh`

`_coda_feature_done` tears down a worktree (session + git worktree +
branch) but leaves behind every opencode session that was ever scoped
to that worktree directory. Those directories never come back in the
same form, so the sessions are permanently orphaned.

Add a helper that, after the worktree is removed, walks every running
orchestrator's port, health-checks it, and asks it to hard-delete any
sessions still scoped to that directory. The orchestrator-side
primitive (`_orch_prune_dir`) already enforces `?directory=<dir>` on
every call, so this can safely target just the torn-down worktree.

Guard the call with `command -v _orch_prune_dir` so coda works fine
when the orchestrator plugin isn't installed.

## Proposed patch

```diff
--- a/lib/feature.sh
+++ b/lib/feature.sh
@@ _coda_feature_done() {
     if [ -d "$worktree_dir" ]; then
         echo "  Removing worktree: $worktree_dir"
         git -C "$project_root" worktree remove "$worktree_dir" --force
     fi

     if git -C "$project_root" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
         echo "  Deleting branch: $branch"
         git -C "$project_root" branch -D "$branch"
     fi

+    # Hard-delete any opencode sessions that were scoped to this
+    # worktree directory across every running orchestrator. Silent
+    # no-op if the orchestrator plugin isn't loaded.
+    _coda_prune_sessions_for_dir "$worktree_dir"
+
     echo "Done."
 }
+
+# Walk every orchestrator port, health-check it, and ask it to
+# hard-delete sessions scoped to $1. Safe when no orchestrators run
+# and when the plugin isn't installed.
+_coda_prune_sessions_for_dir() {
+    local worktree_dir="$1"
+    [ -n "$worktree_dir" ] || return 0
+
+    if ! command -v _orch_prune_dir >/dev/null 2>&1; then
+        return 0
+    fi
+
+    local base_dir="${ORCH_BASE_DIR:-$HOME/.config/coda/orchestrators}"
+    [ -d "$base_dir" ] || return 0
+
+    local pf port
+    for pf in "$base_dir"/*/port; do
+        [ -f "$pf" ] || continue
+        port=$(cat "$pf")
+        case "$port" in
+            ''|*[!0-9]*) continue ;;
+        esac
+        if ! curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1; then
+            continue
+        fi
+        _orch_prune_dir "$port" "$worktree_dir" --hard --keep 0 --days 0 \
+            >/dev/null 2>&1 || true
+    done
+}
```

Apply the same helper call inside `_coda_feature_finish` (which
backgrounds its teardown work) for symmetry:

```diff
--- a/lib/feature.sh
+++ b/lib/feature.sh
@@ _coda_feature_finish() {
     (
         sleep 1
         if tmux has-session -t "$session" 2>/dev/null; then
             tmux kill-session -t "$session"
         fi
         if [ -d "$worktree_dir" ]; then
             git -C "$project_root" worktree remove "$worktree_dir" --force 2>/dev/null
         fi
         if git -C "$project_root" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
             git -C "$project_root" branch -D "$branch" 2>/dev/null
         fi
+        _coda_prune_sessions_for_dir "$worktree_dir"
         CODA_PROJECT_NAME="$project_name" CODA_FEATURE_BRANCH="$branch" \
             _coda_run_hooks post-feature-finish
     ) &
     disown
```

## Why this shape

- **Guarded by `command -v`.** Coda is usable without the orchestrator
  plugin; the helper must be a silent no-op in that configuration.
- **Bridge iterates ports, not orchestrators.** Port files are already
  the source of truth for "is the serve alive?" (`coda orch ls` uses
  them). No extra lookup needed.
- **Directory scoping lives in `_orch_prune_dir`.** The orchestrator
  repo owns that invariant; the bridge only passes the worktree path.
- **Policy `--hard --keep 0 --days 0`.** The worktree is gone for
  good; there's nothing to soft-archive toward. Aggressive cleanup
  is the right default here, different from the periodic prune on
  orch start.

## Verification plan (once the bridge lands)

1. `coda orch new smoke && coda orch start smoke`
2. `coda feature start scratch` (creates a worktree + session)
3. `coda orch send smoke "hello"` a few times to accumulate sessions
4. Confirm the new sessions are visible:
   `curl 'http://localhost:<port>/session?directory=<worktree>' | jq length`
5. `coda feature done scratch`
6. Re-run the same curl against the original worktree directory; the
   count should be zero.
7. Other orchestrators' session counts must be unchanged (take a
   snapshot before step 5, compare after).

## Dependencies

- `_orch_prune_dir` must be callable from the coda shell. The
  orchestrator plugin's `lib/shell-init.sh` sources `lib/prune.sh`,
  which exposes `_orch_prune_dir` at shell init. Nothing else needed.
- Requires the orchestrator PR for card #76 to be merged first.
