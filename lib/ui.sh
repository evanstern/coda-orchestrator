#!/usr/bin/env bash
#
# ui.sh — attach, watch, and status-line for tmux-native UX
#

_orch_attach() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch attach <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    if ! _orch_is_running "$name"; then
        echo "Orchestrator is not running: $name"
        echo "  Start with: coda orch start $name"
        return 1
    fi

    local port
    port=$(cat "$dir/port" 2>/dev/null)
    if [ -z "$port" ]; then
        echo "No port file for orchestrator: $name"
        return 1
    fi

    opencode attach "http://localhost:$port"
}

_orch_watch() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch watch <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    if ! _orch_is_running "$name"; then
        echo "Orchestrator is not running: $name"
        echo "  Start with: coda orch start $name"
        return 1
    fi

    local port
    port=$(cat "$dir/port" 2>/dev/null)
    if [ -z "$port" ]; then
        echo "No port file for orchestrator: $name"
        return 1
    fi

    local base="http://localhost:$port"
    local last_count=0

    echo "Watching $name (port $port) — Ctrl-C to stop"
    echo ""

    local session_id
    session_id=$(curl -sf "$base/session" \
        | jq -r 'sort_by(.time.created) | last | .id // empty' 2>/dev/null)

    if [ -z "$session_id" ]; then
        echo "No active session on $name"
        return 1
    fi

    last_count=$(curl -sf "$base/session/$session_id/message" \
        | jq 'length' 2>/dev/null)
    last_count=${last_count:-0}

    while true; do
        sleep 3

        local messages
        messages=$(curl -sf "$base/session/$session_id/message" 2>/dev/null)
        [ -z "$messages" ] && continue

        local count
        count=$(echo "$messages" | jq 'length' 2>/dev/null)
        count=${count:-0}

        if [ "$count" -gt "$last_count" ]; then
            echo "$messages" | jq -r --argjson skip "$last_count" '
                .[$skip:] | .[] |
                "[" + .info.role + "] " +
                ([.parts[] | select(.type == "text") | .text] | join(""))
            ' 2>/dev/null
            last_count=$count
        fi

        if ! _orch_is_running "$name" 2>/dev/null; then
            echo ""
            echo "[system] Orchestrator stopped."
            break
        fi
    done
}

# _orch_format_age <epoch>
# Outputs human-friendly age like "2h", "45m", "3d"
_orch_format_age() {
    local created="$1"
    local now
    now=$(date +%s)
    local diff=$((now - created))

    if [ "$diff" -lt 60 ]; then
        echo "${diff}s"
    elif [ "$diff" -lt 3600 ]; then
        echo "$((diff / 60))m"
    elif [ "$diff" -lt 86400 ]; then
        echo "$((diff / 3600))h"
    else
        echo "$((diff / 86400))d"
    fi
}

# _orch_print_session_table <pipe-delimited-lines>
# Renders a numbered session table from session_name|windows|created|oc_state lines
_orch_print_session_table() {
    local lines="$1"
    local idx=0

    printf "  %-4s %-45s %-12s %s\n" "#" "Session" "State" "Age"
    printf "  %-4s %-45s %-12s %s\n" "--" "-------" "-----" "---"

    while IFS='|' read -r sess_name windows created oc_state; do
        [ -z "$sess_name" ] && continue
        idx=$((idx + 1))
        local age
        age=$(_orch_format_age "$created")
        printf "  %-4s %-45s %-12s %s\n" "$idx" "$sess_name" "$oc_state" "$age"
    done <<< "$lines"
}

_orch_sessions() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch sessions <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    local scoped
    scoped=$(_orch_scoped_sessions "$name" --include-orch)

    if [ -z "$scoped" ]; then
        echo "No sessions found for: $name"
        return 0
    fi

    echo "Sessions managed by $name:"
    echo ""
    _orch_print_session_table "$scoped"
    echo ""
    echo "Switch: coda orch switch $name [#|name]"
}

_orch_switch() {
    local name="$1"
    local target="${2:-}"

    if [ -z "$name" ]; then
        echo "Usage: coda orch switch <name> [#|session]"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    local scoped
    scoped=$(_orch_scoped_sessions "$name" --include-orch)

    if [ -z "$scoped" ]; then
        echo "No sessions found for: $name"
        return 1
    fi

    local session_names=()
    while IFS='|' read -r sess_name _rest; do
        [ -n "$sess_name" ] && session_names+=("$sess_name")
    done <<< "$scoped"

    local selected=""

    if [ -z "$target" ]; then
        if command -v fzf &>/dev/null; then
            selected=$(printf '%s\n' "${session_names[@]}" | fzf --prompt="Switch to: " --height=40% --reverse)
        else
            echo "Sessions managed by $name:"
            echo ""
            _orch_print_session_table "$scoped"
            echo ""
            printf "Switch to [1-%d]: " "${#session_names[@]}"
            read -r target
        fi
    fi

    if [ -z "$selected" ] && [ -n "$target" ]; then
        if [[ "$target" =~ ^[0-9]+$ ]]; then
            if [ "$target" -ge 1 ] && [ "$target" -le "${#session_names[@]}" ]; then
                selected="${session_names[$((target - 1))]}"
            else
                echo "Invalid number: $target (1-${#session_names[@]})"
                return 1
            fi
        else
            local found=false
            for s in "${session_names[@]}"; do
                if [ "$s" = "$target" ]; then
                    selected="$s"
                    found=true
                    break
                fi
            done
            if ! $found; then
                echo "Session not found: $target"
                echo "Run 'coda orch sessions $name' to see available sessions."
                return 1
            fi
        fi
    fi

    if [ -z "$selected" ]; then
        return 1
    fi

    if [ -n "$TMUX" ]; then
        tmux switch-client -t "$selected"
    else
        tmux attach -t "$selected"
    fi
}

_coda_sessions_list() {
    local scoped
    scoped=$(_orch_all_coda_sessions)

    if [ -z "$scoped" ]; then
        echo "No coda sessions running."
        return 0
    fi

    echo "All coda sessions:"
    echo ""
    _orch_print_session_table "$scoped"
    echo ""
    echo "Switch: tmux switch-client -t <session>"
}

_orch_status_line() {
    if [ ! -d "$ORCH_BASE_DIR" ]; then
        return 0
    fi

    local parts=""

    for dir in "$ORCH_BASE_DIR"/*/; do
        [ -d "$dir" ] || continue

        local name
        name=$(basename "$dir")

        if ! _orch_is_running "$name" 2>/dev/null; then
            continue
        fi

        local scope_file="$dir/scope.json"
        local session_count=0

        if [ -f "$scope_file" ]; then
            local watch_patterns ignore_patterns
            watch_patterns=$(jq -r '.watch[]' "$scope_file" 2>/dev/null)
            ignore_patterns=$(jq -r '.ignore[]? // empty' "$scope_file" 2>/dev/null)

            local sessions
            sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)

            while IFS= read -r sess_name; do
                [ -n "$sess_name" ] || continue
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

                session_count=$((session_count + 1))
            done <<< "$sessions"
        fi

        parts="${parts}[${name}: ${session_count}s] "
    done

    [ -n "$parts" ] && printf '%s' "$parts"
}
