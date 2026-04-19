#!/usr/bin/env bash
#
# send.sh -- prompt dispatch via opencode serve HTTP API
#

# Resolve the target session id for an orchestrator.
# Preference order:
#   1. $dir/session-id file (written on boot / updated by TUI hook)
#   2. Scoped lookup: /session entries whose .directory matches $dir,
#      most-recently-created wins
#   3. POST /session to create a new session (it will be scoped to $dir)
#
# Prints the session id on stdout. Returns 1 if no session could be
# resolved or created.
_orch_send_resolve_session() {
    local dir="$1"
    local base="$2"
    local session_id=""

    if [ -f "$dir/session-id" ]; then
        session_id=$(cat "$dir/session-id" 2>/dev/null | tr -d '[:space:]')
    fi

    if [ -z "$session_id" ]; then
        session_id=$(curl -sf "$base/session" 2>/dev/null \
            | jq -r --arg d "$dir" \
                '[.[] | select(.directory == $d)] | sort_by(.time.created) | last | .id // empty' \
                2>/dev/null)
    fi

    if [ -z "$session_id" ]; then
        session_id=$(curl -sf -X POST "$base/session" \
            -H 'Content-Type: application/json' -d '{}' 2>/dev/null \
            | jq -r '.id // empty' 2>/dev/null)
    fi

    if [ -z "$session_id" ]; then
        return 1
    fi

    echo "$session_id"
}

# Background poller for --async sends. Polls the session for a new
# assistant message and writes the text to $log_file. Exits when a new
# message is observed or after ~600s total wall time.
_orch_send_async_poll() {
    local base="$1"
    local session_id="$2"
    local msg_count_before="$3"
    local log_file="$4"

    local attempts=0
    local max_attempts=300   # 300 * 2s = 600s
    while [ $attempts -lt $max_attempts ]; do
        sleep 2
        local msg_count_now
        msg_count_now=$(curl -sf "$base/session/$session_id/message" 2>/dev/null \
            | jq '[.[] | select(.info.role == "assistant")] | length' 2>/dev/null)
        msg_count_now=${msg_count_now:-0}

        if [ "$msg_count_now" -gt "$msg_count_before" ]; then
            curl -sf "$base/session/$session_id/message" 2>/dev/null \
                | jq -r '[.[] | select(.info.role == "assistant")] | last | [.parts[] | select(.type == "text") | .text] | join("")' \
                    2>/dev/null >> "$log_file"
            printf '\n--- response received at %s ---\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log_file"
            return 0
        fi
        attempts=$((attempts + 1))
    done

    printf '\n--- timed out after %ds at %s ---\n' "$((max_attempts * 2))" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log_file"
    return 1
}

_orch_send() {
    local name=""
    local message=""
    local async_mode=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --async) async_mode=true; shift ;;
            --*) echo "Unknown flag: $1"; return 1 ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                else
                    message="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$name" ] || [ -z "$message" ]; then
        echo "Usage: coda orch send <name> <message> [--async]"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        # Check if it's a session (not an orchestrator)
        if tmux has-session -t "${SESSION_PREFIX:-coda-}$name" 2>/dev/null || \
           tmux has-session -t "$name" 2>/dev/null; then
            echo "'$name' is a session, not an orchestrator."
            echo "  Orchestrators live in: $(dirname "$dir")/"
            echo "  To send to a session, use: tmux send-keys or opencode run --attach"
        else
            echo "Orchestrator not found: $name"
        fi
        return 1
    fi

    if ! _orch_is_running "$name"; then
        echo "Orchestrator is not running: $name"
        echo "  Start with: coda orch start $name"
        return 1
    fi

    local port
    if [ -f "$dir/port" ]; then
        port=$(cat "$dir/port")
    else
        echo "No port file for orchestrator: $name"
        return 1
    fi

    local base="http://localhost:$port"

    local session_id
    session_id=$(_orch_send_resolve_session "$dir" "$base")

    if [ -z "$session_id" ]; then
        echo "Failed to get session from orchestrator: $name"
        return 1
    fi

    local msg_count_before
    msg_count_before=$(curl -sf "$base/session/$session_id/message" \
        | jq '[.[] | select(.info.role == "assistant")] | length' 2>/dev/null)
    msg_count_before=${msg_count_before:-0}

    if $async_mode; then
        mkdir -p "$dir/logs"
        local ts
        ts=$(date -u +%Y%m%dT%H%M%SZ)
        local log_file="$dir/logs/send-${name}-${ts}.log"

        {
            printf '--- send to %s at %s ---\n' "$name" "$ts"
            printf 'session: %s\n' "$session_id"
            printf 'message: %s\n' "$message"
            printf '\n'
        } >> "$log_file"

        # Fire-and-forget POST. Use a long --max-time so curl doesn't
        # cut the request before the server persists it, but never block
        # the caller: the request itself runs in the background.
        (
            curl -sf -X POST "$base/session/$session_id/message" \
                -H 'Content-Type: application/json' \
                -d "$(jq -n --arg msg "$message" '{parts: [{type: "text", text: $msg}]}')" \
                --max-time 600 > /dev/null 2>&1
        ) &

        # Detached background poller. Pass values as positional args
        # (not interpolated into the script string) so shell metachars
        # in log_file / session_id can't break parsing or inject.
        local poll_script
        poll_script="$(declare -f _orch_send_async_poll)
_orch_send_async_poll \"\$1\" \"\$2\" \"\$3\" \"\$4\""
        if command -v setsid >/dev/null 2>&1; then
            setsid bash -c "$poll_script" _ \
                "$base" "$session_id" "$msg_count_before" "$log_file" \
                < /dev/null > /dev/null 2>&1 &
        else
            nohup bash -c "$poll_script" _ \
                "$base" "$session_id" "$msg_count_before" "$log_file" \
                < /dev/null > /dev/null 2>&1 &
        fi
        disown 2>/dev/null || true

        echo "Sent async to $name"
        echo "  Log: $log_file"
        return 0
    fi

    # Sync POST blocks until the agent finishes responding
    local response
    response=$(curl -sf -X POST "$base/session/$session_id/message" \
        -H 'Content-Type: application/json' \
        -d "$(jq -n --arg msg "$message" '{parts: [{type: "text", text: $msg}]}')" \
        --max-time 300 2>/dev/null)

    if [ -n "$response" ]; then
        echo "$response" | jq -r '[.parts[] | select(.type == "text") | .text] | join("")' 2>/dev/null
        return 0
    fi

    # Fallback: poll for new assistant message
    local attempts=0
    while [ $attempts -lt 120 ]; do
        sleep 2
        local msg_count_now
        msg_count_now=$(curl -sf "$base/session/$session_id/message" \
            | jq '[.[] | select(.info.role == "assistant")] | length' 2>/dev/null)
        msg_count_now=${msg_count_now:-0}

        if [ "$msg_count_now" -gt "$msg_count_before" ]; then
            curl -sf "$base/session/$session_id/message" \
                | jq -r '[.[] | select(.info.role == "assistant")] | last | [.parts[] | select(.type == "text") | .text] | join("")' 2>/dev/null
            return 0
        fi
        attempts=$((attempts + 1))
    done

    echo "Timed out waiting for response from: $name"
    return 1
}
