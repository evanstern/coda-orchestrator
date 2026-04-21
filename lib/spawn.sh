#!/usr/bin/env bash
#
# spawn.sh -- orchestrator spawn status/wait helpers
#
# The spawn-and-trigger flow is handled by `coda feature start --orch <name>`
# via the hook in lib/feature-hook.sh. This module only provides status and
# completion-waiting helpers for sessions already running.
#

_orch_spawn_status() {
    local orch_name="$1"

    if [ -z "$orch_name" ]; then
        echo "Usage: coda orch spawns <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$orch_name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $orch_name"
        return 1
    fi

    local log_dir="$dir/logs"

    echo "Spawned sessions for: $orch_name"
    echo ""

    local candidate_sessions
    candidate_sessions=$(tmux list-sessions -F '#{session_name}|#{session_created}' 2>/dev/null \
        | grep '.*--spawn-' || true)

    local sessions=""
    while IFS='|' read -r sess_name created; do
        [ -z "$sess_name" ] && continue
        local slug
        slug=$(echo "$sess_name" | sed 's/.*--spawn-//')
        if [ -d "$log_dir" ] && [ -f "$log_dir/spawn-${slug}.log" ]; then
            sessions="${sessions}${sess_name}|${created}
"
        fi
    done <<< "$candidate_sessions"

    if [ -z "$sessions" ]; then
        echo "  (no active spawned sessions)"
        return 0
    fi

    while IFS='|' read -r sess_name created; do
        [ -z "$sess_name" ] && continue
        local slug
        slug=$(echo "$sess_name" | sed 's/.*--spawn-//')

        local port="unknown"
        local pane_id
        pane_id=$(tmux list-panes -t "$sess_name" -F '#{pane_id}' 2>/dev/null | head -1)

        local worktree_dir=""
        if [ -n "$pane_id" ]; then
            worktree_dir=$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null)
        fi
        if [ -n "$worktree_dir" ] && [ -f "$worktree_dir/port" ]; then
            port=$(cat "$worktree_dir/port")
        fi

        local age=""
        if [ -n "$created" ]; then
            local now
            now=$(date +%s)
            local diff=$((now - created))
            if [ $diff -lt 60 ]; then
                age="${diff}s"
            elif [ $diff -lt 3600 ]; then
                age="$((diff / 60))m"
            else
                age="$((diff / 3600))h"
            fi
        fi

        local last_line=""
        if [ -d "$log_dir" ] && [ -f "$log_dir/spawn-${slug}.log" ]; then
            last_line=$(tail -1 "$log_dir/spawn-${slug}.log" 2>/dev/null \
                | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        if e.get('type') == 'text':
            print(e.get('part', {}).get('text', '')[:60], end='')
    except: pass
" 2>/dev/null || true)
        fi

        printf "  %-35s  port:%-5s  age:%-5s  %s\n" "$sess_name" "$port" "$age" "$last_line"
    done <<< "$sessions"
}

_orch_spawn_wait() {
    local slug="$1"
    local timeout="${2:-600}"
    local orch_name="${3:-}"

    if [ -z "$slug" ]; then
        echo "Usage: coda orch spawn-wait <slug> [timeout-seconds] [orch-name]"
        return 1
    fi

    # Find the log file
    local log_file=""
    if [ -n "$orch_name" ]; then
        local dir
        dir="$(_orch_dir "$orch_name")"
        log_file="$dir/logs/spawn-${slug}.log"
    else
        # Search all orchestrator dirs for the log
        for d in "$ORCH_BASE_DIR"/*/logs; do
            if [ -f "$d/spawn-${slug}.log" ]; then
                log_file="$d/spawn-${slug}.log"
                break
            fi
        done
    fi

    if [ -z "$log_file" ] || [ ! -f "$log_file" ]; then
        echo "No log file found for spawn: $slug"
        return 1
    fi

    echo "Waiting for completion of spawn/$slug (timeout: ${timeout}s)..."

    local result
    set -o pipefail
    result=$(timeout "$timeout" tail -f "$log_file" 2>/dev/null | _orch_parse_acp_completion)
    local status=$?
    set +o pipefail

    if [ $status -eq 124 ]; then
        echo "Timed out after ${timeout}s"
        return 1
    elif [ $status -ne 0 ]; then
        echo "Spawn log ended without a completion marker for: $slug"
        return 1
    fi

    echo "$result"
}

_orch_parse_acp_completion() {
    python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get('type') == 'text':
        text = event.get('part', {}).get('text', '')
        sys.stdout.write(text)
        sys.stdout.flush()
        if 'PR ready:' in text or 'done:' in text:
            sys.exit(0)
sys.exit(1)
"
}

# Bootstrap sibling modules that coda-handler.sh does not source directly.
# Loading status.sh here makes `_orch_status` (tree view) available to callers
# of spawn.sh.
_orch_spawn_dir="${BASH_SOURCE%/*}"
if [ -f "$_orch_spawn_dir/status.sh" ]; then
    # shellcheck source=/dev/null
    source "$_orch_spawn_dir/status.sh"
fi
unset _orch_spawn_dir
