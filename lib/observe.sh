#!/usr/bin/env bash
#
# observe.sh -- session status collection for orchestrator scope
#

_orch_status() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch status <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    local scope_file="$dir/scope.json"
    if [ ! -f "$scope_file" ]; then
        echo "No scope defined for: $name"
        return 1
    fi

    local watch_patterns ignore_patterns
    watch_patterns=$(jq -r '.watch[]' "$scope_file" 2>/dev/null)
    ignore_patterns=$(jq -r '.ignore[]? // empty' "$scope_file" 2>/dev/null)

    if [ -z "$watch_patterns" ]; then
        echo "Empty watch scope for: $name"
        return 1
    fi

    echo "Orchestrator: $name"
    if _orch_is_running "$name"; then
        local port=""
        [ -f "$dir/port" ] && port=$(cat "$dir/port")
        echo "Status: running (port ${port:-unknown})"
    else
        echo "Status: stopped"
    fi
    echo ""
    echo "Scoped sessions:"

    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_created}' 2>/dev/null)

    if [ -z "$sessions" ]; then
        echo "  (no tmux sessions)"
        return 0
    fi

    local matched=false
    while IFS='|' read -r sess_name windows created; do
        local match=false
        while IFS= read -r pattern; do
            # shellcheck disable=SC2254
            case "$sess_name" in $pattern) match=true ;; esac
        done <<< "$watch_patterns"

        $match || continue

        local ignored=false
        if [ -n "$ignore_patterns" ]; then
            while IFS= read -r pattern; do
                # shellcheck disable=SC2254
                case "$sess_name" in $pattern) ignored=true ;; esac
            done <<< "$ignore_patterns"
        fi
        $ignored && continue

        matched=true

        local oc_state="unknown"
        local pane_id
        pane_id=$(tmux list-panes -t "$sess_name" -F '#{pane_id}' 2>/dev/null | head -1)
        if [ -n "$pane_id" ]; then
            local capture
            capture=$(tmux capture-pane -t "$pane_id" -p -S -5 2>/dev/null)
            if echo "$capture" | grep -qE 'OpenCode [0-9]+\.' 2>/dev/null; then
                if echo "$capture" | grep -q 'esc interrupt' 2>/dev/null; then
                    oc_state="processing"
                else
                    oc_state="idle"
                fi
            else
                oc_state="no-opencode"
            fi
        fi

        local created_human
        created_human=$(date -d "@$created" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$created")

        printf "  %-30s  %dw  %-12s  %s\n" "$sess_name" "$windows" "$oc_state" "$created_human"
    done <<< "$sessions"

    if ! $matched; then
        echo "  (no sessions match scope)"
    fi
}
