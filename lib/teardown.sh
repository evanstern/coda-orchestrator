#!/usr/bin/env bash
#
# teardown.sh -- persistent teardown report delivery for feature sessions
#
# A feature session ends when its tmux window/session is torn down. The
# orchestrator that owns the feature needs a durable postmortem even when
# it is not running at teardown time, so delivery must be filesystem-only
# (no `coda orch send`, no opencode HTTP calls).
#
# The report is written to:
#   <orch_dir>/inbox/<branch>.md
#
# One file per feature teardown. `inbox/` is additive -- the existing
# `inbox.md` message mechanism is untouched. If the same branch tears
# down twice (rare), the previous report is renamed with a .prev suffix
# so nothing is lost.

# Resolve a PR URL for the feature branch, or print "none" if not found.
# Uses `gh pr view` if available; falls back to "none" silently.
_orch_teardown_pr_url() {
    local worktree_dir="$1"
    local branch="$2"

    if ! command -v gh >/dev/null 2>&1; then
        echo "none"
        return 0
    fi

    local url=""
    url=$(cd "$worktree_dir" 2>/dev/null \
        && gh pr view "$branch" --json url --jq '.url' 2>/dev/null)

    if [ -n "$url" ]; then
        echo "$url"
    else
        echo "none"
    fi
}

# Get current commit SHA (short), or empty string if not in a git dir.
_orch_teardown_head_sha() {
    local worktree_dir="$1"
    (cd "$worktree_dir" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null) || true
}

# Build a minimal auto-generated report body for when the agent did not
# write TEARDOWN.md. The orchestrator still gets card/branch/PR/status
# context, just no implementation narrative.
_orch_teardown_auto_body() {
    cat <<'BODY'
status: unknown
pr: none

## What got done
- None (no TEARDOWN.md was written by the feature session)

## What did not get done
- None

## Decisions made
- None

## Issues / surprises / workarounds
- None

## Notes for the orchestrator
- Feature session ended without writing TEARDOWN.md. Implementation context
  is not available from the session itself. Check the worktree, branch, and
  any open PR for what was actually done.
BODY
}

# Write a teardown report into the orchestrator's inbox/ directory.
#
# Args:
#   $1 orch_dir       -- absolute path to orchestrator config dir
#   $2 branch         -- feature branch name
#   $3 worktree_dir   -- absolute path to the feature worktree
#   $4 card_id        -- card identifier (may be empty)
#   $5 project_name   -- project name (may be empty)
#
# Returns 0 on success, 1 on fatal error. Missing inputs are reported
# via the body (e.g. "pr: none") rather than failing.
_orch_write_teardown_report() {
    local orch_dir="$1"
    local branch="$2"
    local worktree_dir="$3"
    local card_id="${4:-}"
    local project_name="${5:-}"

    if [ -z "$orch_dir" ] || [ -z "$branch" ]; then
        echo "_orch_write_teardown_report: orch_dir and branch are required" >&2
        return 1
    fi

    if [ ! -d "$orch_dir" ]; then
        echo "_orch_write_teardown_report: orchestrator dir missing: $orch_dir" >&2
        return 1
    fi

    local inbox_dir="$orch_dir/inbox"
    mkdir -p "$inbox_dir" || return 1

    # Deterministic filename keyed off the branch -- grep-able and stable.
    local safe_branch="${branch//\//-}"
    local out_file="$inbox_dir/${safe_branch}.md"

    # Preserve any previous report for the same branch.
    if [ -f "$out_file" ]; then
        mv "$out_file" "${out_file}.prev"
    fi

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local pr_url="none"
    local head_sha=""
    local body=""
    local source="auto"

    if [ -n "$worktree_dir" ] && [ -d "$worktree_dir" ]; then
        head_sha=$(_orch_teardown_head_sha "$worktree_dir")
        pr_url=$(_orch_teardown_pr_url "$worktree_dir" "$branch")

        if [ -f "$worktree_dir/TEARDOWN.md" ]; then
            body=$(cat "$worktree_dir/TEARDOWN.md")
            source="self-report"
        fi
    fi

    if [ -z "$body" ]; then
        body=$(_orch_teardown_auto_body)
    fi

    {
        printf '%s\n' "# Feature teardown: $branch"
        printf '\n'
        printf '%s\n' "- card: ${card_id:-unknown}"
        printf '%s\n' "- branch: $branch"
        printf '%s\n' "- project: ${project_name:-unknown}"
        printf '%s\n' "- worktree: ${worktree_dir:-unknown}"
        printf '%s\n' "- head: ${head_sha:-unknown}"
        printf '%s\n' "- pr: $pr_url"
        printf '%s\n' "- time: $ts"
        printf '%s\n' "- source: $source"
        printf '\n---\n\n'
        printf '%s\n' "$body"
    } > "$out_file"

    echo "$out_file"
    return 0
}
