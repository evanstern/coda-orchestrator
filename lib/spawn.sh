#!/usr/bin/env bash
#
# spawn.sh -- orchestrator task delegation via feature session spawning
#

_orch_spawn() {
    local orch_name=""
    local slug=""
    local brief=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --*) echo "Unknown flag: $1"; return 1 ;;
            *)
                if [ -z "$orch_name" ]; then
                    orch_name="$1"
                elif [ -z "$slug" ]; then
                    slug="$1"
                else
                    brief="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$orch_name" ] || [ -z "$slug" ] || [ -z "$brief" ]; then
        echo "Usage: coda orch spawn <name> <slug> <brief-text-or-file>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$orch_name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $orch_name"
        return 1
    fi

    # 1. Check concurrency limit
    local max_spawned
    max_spawned=$(jq -r '.max_spawned // 5' "$dir/scope.json" 2>/dev/null)
    max_spawned=${max_spawned:-5}

    local current_count
    current_count=$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep -c 'coda-.*--spawn-' || true)

    if [ "$current_count" -ge "$max_spawned" ]; then
        echo "Concurrency limit reached: $current_count/$max_spawned spawned sessions"
        echo "  Use 'coda orch spawns $orch_name' to see active spawns"
        return 1
    fi

    # 2. Resolve the project directory from scope
    local project_dir
    project_dir="${PROJECTS_DIR:-$HOME/projects}"

    # Determine project name from scope watch patterns
    local watch_pattern
    watch_pattern=$(jq -r '.watch[0] // empty' "$dir/scope.json" 2>/dev/null)
    local project_name
    # Extract project name: coda-<project>--* -> <project>
    if [[ "$watch_pattern" =~ ^coda-(.+)--\*$ ]]; then
        project_name="${BASH_REMATCH[1]}"
    else
        echo "Cannot determine project from scope: $watch_pattern"
        echo "  Scope watch pattern must be 'coda-<project>--*'"
        return 1
    fi

    local project_root="$project_dir/$project_name"
    if [ ! -d "$project_root" ]; then
        echo "Project directory not found: $project_root"
        return 1
    fi

    local branch="spawn/$slug"
    local worktree_dir="$project_root/$branch"

    # 3. Create the worktree
    if [ -d "$worktree_dir" ]; then
        echo "Worktree already exists: $worktree_dir"
        echo "  Clean up with: coda feature done $branch $project_name"
        return 1
    fi

    local base_branch
    base_branch=$(git -C "$project_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|refs/remotes/origin/||')
    base_branch=${base_branch:-main}

    echo "Creating worktree: $branch (from $base_branch)"
    if git -C "$project_root" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        git -C "$project_root" worktree add "$worktree_dir" "$branch" || return 1
    elif git -C "$project_root" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null; then
        git -C "$project_root" worktree add --track -b "$branch" "$worktree_dir" "origin/$branch" || return 1
    else
        git -C "$project_root" worktree add -b "$branch" "$worktree_dir" "$base_branch" || return 1
    fi

    # 4. Write IMPLEMENT.md to worktree
    if [ -f "$brief" ]; then
        cp "$brief" "$worktree_dir/IMPLEMENT.md"
    else
        cat > "$worktree_dir/IMPLEMENT.md" <<EOF
# IMPLEMENT.md

You are a feature session for the \`$project_name\` project.
Read this file at startup. When you receive "execute", carry out this task.
Report back "PR ready: <url>" when done.

## Your Task

$brief
EOF
    fi

    # 5. Prepend AGENTS.md with feature-session header
    local agents_header
    agents_header=$(cat <<'HEADER'
# FEATURE SESSION

You are a feature implementation agent, NOT the orchestrator.
Read IMPLEMENT.md for your task brief.
When you receive "execute", carry out the task.
Report back "PR ready: <url>" when done.

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

    # 6. Add to .gitignore
    local needs_ignore=false
    if [ ! -f "$worktree_dir/.gitignore" ] || ! grep -q 'IMPLEMENT.md' "$worktree_dir/.gitignore" 2>/dev/null; then
        needs_ignore=true
    fi
    if $needs_ignore; then
        printf '\n# Feature session files\nIMPLEMENT.md\nAGENTS.md\n*.feature-brief.md\n' >> "$worktree_dir/.gitignore"
    fi

    # 7. Start opencode serve in tmux session
    local session_name="${SESSION_PREFIX:-coda-}${project_name}--spawn-${slug}"
    local port
    port=$(_orch_find_free_port)
    if [ -z "$port" ]; then
        echo "No free ports in range ${ORCH_PORT_BASE}-$((ORCH_PORT_BASE + ORCH_PORT_RANGE))"
        return 1
    fi

    local permission='{"*":"allow"}'
    local serve_cmd="OPENCODE_PERMISSION='$permission' opencode serve --port $port"

    echo "$port" > "$worktree_dir/port"

    tmux new-session -d -s "$session_name" -c "$worktree_dir" "$serve_cmd; exec \$SHELL"

    # 8. Wait for opencode serve to be ready (poll with timeout)
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
        echo "Timed out waiting for opencode serve on port $port"
        tmux kill-session -t "$session_name" 2>/dev/null
        rm -f "$worktree_dir/port"
        return 1
    fi

    # 9. Send "execute" via opencode run --attach in background
    local log_dir="$dir/logs"
    mkdir -p "$log_dir"
    local log_file="$log_dir/spawn-${slug}.log"

    opencode run --attach "http://localhost:$port" --format json "execute" \
        > "$log_file" 2>&1 &
    local run_pid=$!
    disown $run_pid 2>/dev/null || true

    echo "Spawned: $session_name (port $port)"
    echo "  Worktree: $worktree_dir"
    echo "  Log:      $log_file"
    echo "  Attach:   opencode attach http://localhost:$port"
}

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
