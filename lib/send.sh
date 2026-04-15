#!/usr/bin/env bash
#
# send.sh u2014 prompt dispatch via opencode serve HTTP API
#

_orch_send() {
    local name=""
    local message=""

    while [ $# -gt 0 ]; do
        case "$1" in
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
        echo "Usage: coda orch send <name> <message>"
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
    if [ -f "$dir/port" ]; then
        port=$(cat "$dir/port")
    else
        echo "No port file for orchestrator: $name"
        return 1
    fi

    local base="http://localhost:$port"

    local session_id
    session_id=$(curl -sf "$base/session" \
        | jq -r 'sort_by(.time.created) | last | .id // empty' 2>/dev/null)

    if [ -z "$session_id" ]; then
        session_id=$(curl -sf -X POST "$base/session" \
            -H 'Content-Type: application/json' -d '{}' \
            | jq -r '.id // empty' 2>/dev/null)
    fi

    if [ -z "$session_id" ]; then
        echo "Failed to get session from orchestrator: $name"
        return 1
    fi

    local msg_count_before
    msg_count_before=$(curl -sf "$base/session/$session_id/message" \
        | jq '[.[] | select(.info.role == "assistant")] | length' 2>/dev/null)
    msg_count_before=${msg_count_before:-0}

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
