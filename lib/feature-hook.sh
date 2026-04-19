#!/usr/bin/env bash
#
# feature-hook.sh -- hook invoked by `coda feature start --orch <name>`
#
# NOTE: As of card #91, this function is the legacy path.
# When `coda feature start --orch <name>` is used, the serve + brief setup
# is handled by hooks/post-session-create/60-feature-spawn-setup, which
# receives feature context via CODA_* env vars exported by
# _coda_feature_start (coda CLI PR #44). The tmux window itself is created
# by _coda_attach via CODA_ORCH_WINDOW_MODE=1 + CODA_ORCH_TARGET (coda CLI
# PR #40) before any hook fires.
#
# This function remains for direct invocation compatibility (older coda
# CLIs, scripts that call _coda_feature_orch_hook directly).
#
# After coda creates the worktree, it calls `_coda_feature_orch_hook` with:
#   $1 orch_name      -- orchestrator whose config directs the spawn
#   $2 branch         -- feature branch name (e.g. "42-fix-thing")
#   $3 project_name   -- project name
#   $4 worktree_dir   -- absolute path to the newly-created worktree
#   $5 project_root   -- absolute path to the project's primary worktree
#
# The hook wires the worktree up as a briefed feature session: it moves a
# staged brief into IMPLEMENT.md, prepends AGENTS.md with the feature-session
# header, starts `opencode serve` in a tmux session named using the standard
# feature-session convention, and auto-triggers the agent when a brief is
# present.
#
# Window mode (CODA_ORCH_WINDOW_MODE=1):
#   Instead of creating a new top-level tmux session, the feature is spawned
#   as a tmux window inside the orchestrator's existing session via the
#   configured layout's `_layout_spawn`. opencode serve still runs detached
#   so `opencode run --attach` works. See designs/features-as-orchestrator-windows.md.
#

_coda_feature_orch_hook() {
    local orch_name="$1"
    local branch="$2"
    local project_name="$3"
    local worktree_dir="$4"
    local project_root="$5"

    if [ -z "$orch_name" ] || [ -z "$branch" ] || [ -z "$project_name" ] \
        || [ -z "$worktree_dir" ] || [ -z "$project_root" ]; then
        echo "_coda_feature_orch_hook: missing required argument" >&2
        return 1
    fi

    # 1. Resolve and validate orchestrator config directory
    local base_dir="${ORCH_BASE_DIR:-${CODA_ORCH_DIR:-$HOME/.config/coda/orchestrators}}"
    local dir="$base_dir/$orch_name"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $orch_name (expected $dir)" >&2
        return 1
    fi

    if [ ! -d "$worktree_dir" ]; then
        echo "Worktree directory not found: $worktree_dir" >&2
        return 1
    fi

    # 2. Move staged brief into IMPLEMENT.md if present
    if [ -f "$dir/staged-brief.md" ]; then
        mv "$dir/staged-brief.md" "$worktree_dir/IMPLEMENT.md"
    fi

    # 3. Prepend AGENTS.md with feature-session header
    local agents_header
    agents_header=$(cat <<'HEADER'
# FEATURE SESSION

You are a feature implementation agent, NOT the orchestrator.
Read IMPLEMENT.md for your task brief.
When you receive "read @IMPLEMENT.md and execute", start immediately.
Report "PR ready: <url>" when done.

---
HEADER
)

    if [ -f "$worktree_dir/AGENTS.md" ]; then
        local tmp
        tmp=$(mktemp)
        printf '%s\n\n' "$agents_header" > "$tmp"
        cat "$worktree_dir/AGENTS.md" >> "$tmp"
        mv "$tmp" "$worktree_dir/AGENTS.md"
    else
        printf '%s\n' "$agents_header" > "$worktree_dir/AGENTS.md"
    fi

    # 4. Add IMPLEMENT.md/AGENTS.md to .gitignore if not already there
    if [ ! -f "$worktree_dir/.gitignore" ] \
        || ! grep -q 'IMPLEMENT.md' "$worktree_dir/.gitignore" 2>/dev/null; then
        printf '\n# Feature session files\nIMPLEMENT.md\nAGENTS.md\n*.feature-brief.md\n' \
            >> "$worktree_dir/.gitignore"
    fi

    # 5. Allocate a free port for opencode serve
    if ! command -v _orch_find_free_port >/dev/null 2>&1; then
        echo "_orch_find_free_port unavailable -- is the orchestrator plugin loaded?" >&2
        return 1
    fi

    local port
    port=$(_orch_find_free_port)
    if [ -z "$port" ]; then
        local port_base="${ORCH_PORT_BASE:-4200}"
        local port_range="${ORCH_PORT_RANGE:-20}"
        echo "No free ports in range ${port_base}-$((port_base + port_range))" >&2
        return 1
    fi

    echo "$port" > "$worktree_dir/port"

    # 6. Start opencode serve -- dual path on CODA_ORCH_WINDOW_MODE.
    local permission='{"*":"allow"}'
    local session_name

    if [ "${CODA_ORCH_WINDOW_MODE:-}" = "1" ]; then
        # --- Window mode: spawn a window inside the orchestrator session ---

        local orch_session="${SESSION_PREFIX:-coda-}orch--${orch_name}"

        # Auto-start the orchestrator session if it isn't running.
        if ! tmux has-session -t "$orch_session" 2>/dev/null; then
            if command -v _orch_start >/dev/null 2>&1; then
                _orch_start "$orch_name" >/dev/null 2>&1 || true
            fi
            if ! tmux has-session -t "$orch_session" 2>/dev/null; then
                echo "Orchestrator session not running and could not be started: $orch_session" >&2
                rm -f "$worktree_dir/port"
                return 1
            fi
        fi

        # Start opencode serve detached (not in tmux) so the window hosts the
        # TUI for humans while serve handles programmatic access.
        (
            cd "$worktree_dir" || exit 1
            OPENCODE_PERMISSION="$permission" opencode serve --port "$port" \
                >"$worktree_dir/serve.log" 2>&1 &
            disown $! 2>/dev/null || true
        )

        # Spawn the feature window via the configured layout.
        if ! command -v _layout_spawn >/dev/null 2>&1; then
            echo "_layout_spawn unavailable -- is a coda layout sourced?" >&2
            rm -f "$worktree_dir/port"
            return 1
        fi

        local window_target="${orch_session}:${branch}"
        CODA_LAYOUT_TARGET="$window_target" _layout_spawn "$orch_session" "$worktree_dir"

        # session_name uses slash form for path/log readability.
        session_name="${orch_session}/${branch}"
    else
        # --- Legacy mode: top-level feature-session tmux session ---

        session_name="${SESSION_PREFIX:-coda-}${project_name}--${branch}"
        local serve_cmd="OPENCODE_PERMISSION='$permission' opencode serve --port $port"

        if ! tmux new-session -d -s "$session_name" -c "$worktree_dir" \
            "$serve_cmd; exec \$SHELL"; then
            echo "Failed to create tmux session: $session_name" >&2
            rm -f "$worktree_dir/port"
            return 1
        fi
    fi

    # 7. Wait for opencode serve to be ready
    local wait_secs=30
    local elapsed=0
    echo "Waiting for opencode serve on port $port..."
    while [ $elapsed -lt $wait_secs ]; do
        if curl -sf "http://localhost:$port/session" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ $elapsed -ge $wait_secs ]; then
        echo "Timed out waiting for opencode serve on port $port" >&2
        if [ "${CODA_ORCH_WINDOW_MODE:-}" = "1" ]; then
            local orch_session="${SESSION_PREFIX:-coda-}orch--${orch_name}"
            tmux kill-window -t "${orch_session}:${branch}" 2>/dev/null || true
        else
            tmux kill-session -t "$session_name" 2>/dev/null
        fi
        rm -f "$worktree_dir/port"
        return 1
    fi

    # 8. Auto-trigger if IMPLEMENT.md is present
    if [ -f "$worktree_dir/IMPLEMENT.md" ]; then
        local log_dir="$dir/logs"
        mkdir -p "$log_dir"
        local log_file="$log_dir/feature-${branch//\//-}.log"

        opencode run --attach "http://localhost:$port" --format json \
            "read @IMPLEMENT.md and execute" \
            > "$log_file" 2>&1 &
        local run_pid=$!
        disown $run_pid 2>/dev/null || true

        echo "Feature session: $session_name (port $port)"
        echo "  Worktree: $worktree_dir"
        echo "  Log:      $log_file"
        echo "  Attach:   opencode attach http://localhost:$port"
    else
        echo "Feature session: $session_name (port $port)"
        echo "  Worktree: $worktree_dir"
        echo "  Attach:   opencode attach http://localhost:$port"
        echo "  (no IMPLEMENT.md -- no auto-trigger)"
    fi
}
