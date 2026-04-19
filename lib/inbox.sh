#!/usr/bin/env bash

_orch_inbox() {
    local name="${1:-}"
    local action="${2:-}"

    if [ -z "$name" ]; then
        echo "Usage: coda orch inbox <name> [clear]"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    local inbox="$dir/inbox.md"

    case "$action" in
        clear)
            : > "$inbox"
            echo "Inbox cleared: $name"
            ;;
        "")
            if [ ! -s "$inbox" ]; then
                echo "inbox is empty"
                return 0
            fi
            cat "$inbox"
            ;;
        *)
            echo "Unknown inbox action: $action"
            echo "Usage: coda orch inbox <name> [clear]"
            return 1
            ;;
    esac
}
