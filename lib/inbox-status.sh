#!/usr/bin/env bash
# Usage: inbox-status.sh <orchestrator-dir>
# Emits a tmux status-right badge when inbox.md has entries.

dir="${1:-}"
[ -n "$dir" ] || exit 0

inbox="$dir/inbox.md"
[ -f "$inbox" ] || exit 0
[ -s "$inbox" ] || exit 0

markers=$(grep -c '^---$' "$inbox" 2>/dev/null || echo 0)
count=$(( markers / 2 ))

[ "$count" -gt 0 ] || exit 0

printf '#[fg=yellow,bold][%d msg(s)]#[default] ' "$count"
