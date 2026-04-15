#!/usr/bin/env bash
#
# send.sh u2014 prompt dispatch via opencode run --attach
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

    opencode run --attach "http://localhost:$port" "$message"
}
