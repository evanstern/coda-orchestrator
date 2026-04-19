#!/usr/bin/env bash
#
# prune.sh -- prune stale opencode sessions scoped to an orchestrator directory
#
# Every opencode serve instance shares a single on-disk session store.
# Sessions accumulate without bound. This module prunes old sessions
# while respecting directory scoping so one orchestrator never deletes
# another's sessions.
#

# Prune sessions for a single orchestrator directory.
#
# Usage:
#   _orch_prune_dir <port> <directory> [--hard] [--dry-run] [--keep N] [--days D]
#
# Defaults:
#   --keep  ${CODA_ORCH_KEEP:-5}
#   --days  ${CODA_ORCH_KEEP_DAYS:-14}
#
_orch_prune_dir() {
    local port="" directory=""
    local hard=false dry_run=false
    local keep="${CODA_ORCH_KEEP:-5}"
    local days="${CODA_ORCH_KEEP_DAYS:-14}"

    # Parse positional + flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --hard)    hard=true; shift ;;
            --dry-run) dry_run=true; shift ;;
            --keep|--days)
                if [ $# -lt 2 ] || [ -z "$2" ]; then
                    echo "prune: $1 requires a value" >&2
                    return 1
                fi
                case "$2" in
                    ''|*[!0-9]*)
                        echo "prune: $1 must be a non-negative integer, got: $2" >&2
                        return 1
                        ;;
                esac
                if [ "$1" = "--keep" ]; then keep="$2"; else days="$2"; fi
                shift 2
                ;;
            --*)       echo "Unknown flag: $1" >&2; return 1 ;;
            *)
                if [ -z "$port" ]; then
                    port="$1"
                elif [ -z "$directory" ]; then
                    directory="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$port" ] || [ -z "$directory" ]; then
        echo "Usage: _orch_prune_dir <port> <directory> [--hard] [--dry-run] [--keep N] [--days D]" >&2
        return 1
    fi

    # Safety: port must be numeric
    case "$port" in
        ''|*[!0-9]*)
            echo "prune: port must be numeric: $port" >&2
            return 1
            ;;
    esac

    # Safety: directory must be an absolute path
    case "$directory" in
        /*) ;;
        *)
            echo "prune: directory must be an absolute path: $directory" >&2
            return 1
            ;;
    esac

    local base="http://localhost:$port"
    local encoded_dir
    encoded_dir=$(_orch_prune_urlencode "$directory")

    # 1. Get active session IDs
    local status_json
    status_json=$(curl -sf "$base/session/status?directory=$encoded_dir" 2>/dev/null) || status_json="{}"

    local active_ids
    active_ids=$(printf '%s' "$status_json" | jq -r 'keys[]' 2>/dev/null || true)

    # 2. Get all sessions for this directory, sorted by time.updated desc
    local sessions_json
    sessions_json=$(curl -sf "$base/session?directory=$encoded_dir" 2>/dev/null) || sessions_json="[]"

    # Parse sessions into id|updated|parentID lines, sorted newest first
    local session_lines
    session_lines=$(printf '%s' "$sessions_json" | jq -r '
        [.[] | {
            id: .id,
            updated: (.time.updated // .time.created // 0),
            parentID: (.parentID // "")
        }] | sort_by(-.updated) | .[] |
        "\(.id)|\(.updated)|\(.parentID)"
    ' 2>/dev/null || true)

    if [ -z "$session_lines" ]; then
        echo "pruned: kept=0 archived=0 deleted=0 (dir=$(basename "$directory"))"
        return 0
    fi

    # Calculate cutoff timestamp (now - days, in milliseconds)
    local now_s
    now_s=$(date +%s)
    local now_ms=$((now_s * 1000))
    local cutoff_ms=$(( (now_s - days * 86400) * 1000 ))
    local hard_cutoff_ms=$(( (now_s - days * 2 * 86400) * 1000 ))

    local kept=0 archived=0 deleted=0
    local eligible_rank=0
    local id updated parent_id

    while IFS='|' read -r id updated parent_id; do
        [ -z "$id" ] && continue

        # Keep active sessions
        if [ -n "$active_ids" ] && printf '%s\n' "$active_ids" | grep -qx "$id" 2>/dev/null; then
            kept=$((kept + 1))
            continue
        fi

        # Keep child sessions (parentID set)
        if [ -n "$parent_id" ]; then
            kept=$((kept + 1))
            continue
        fi

        # Track rank among eligible (non-active, non-child) sessions
        eligible_rank=$((eligible_rank + 1))

        # Keep within top N eligible sessions
        if [ "$eligible_rank" -le "$keep" ]; then
            kept=$((kept + 1))
            continue
        fi

        # Keep if within the retention window (now - days)
        if [ "$updated" -gt "$cutoff_ms" ] 2>/dev/null; then
            kept=$((kept + 1))
            continue
        fi

        if $dry_run; then
            local action="archive"
            if $hard || [ "$updated" -lt "$hard_cutoff_ms" ] 2>/dev/null; then
                action="delete"
                deleted=$((deleted + 1))
            else
                archived=$((archived + 1))
            fi
            echo "would: $action $id"
            continue
        fi

        # Hard delete if --hard flag or older than 2x retention
        if $hard || { [ "$updated" -lt "$hard_cutoff_ms" ] 2>/dev/null; }; then
            curl -sf -X DELETE "$base/session/$id?directory=$encoded_dir" >/dev/null 2>&1 || true
            deleted=$((deleted + 1))
        else
            # Soft delete (archive). Directory-scoped to stay consistent
            # with every other opencode call made here (#84).
            curl -sf -X PATCH "$base/session/$id?directory=$encoded_dir" \
                -H 'Content-Type: application/json' \
                -d "{\"time\":{\"archived\":$now_ms}}" >/dev/null 2>&1 || true
            archived=$((archived + 1))
        fi
    done <<< "$session_lines"

    echo "pruned: kept=$kept archived=$archived deleted=$deleted (dir=$(basename "$directory"))"
}

# URL-encode a string. Tries jq (a declared plugin dependency) first,
# then python3 as a fallback. Fails loudly if neither is available so
# directory scoping is never silently bypassed.
_orch_prune_urlencode() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -sRr @uri
        return $?
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
        return $?
    fi
    echo "_orch_prune_urlencode: requires jq or python3 for URL encoding" >&2
    return 1
}

# Prune all sessions for a given worktree directory across all running
# orchestrator ports. Used by `coda feature done` to hard-delete sessions
# tied to a torn-down worktree.
#
# Usage: _orch_prune_sessions_for_dir <worktree_dir>
#
_orch_prune_sessions_for_dir() {
    local worktree_dir="$1"
    local base_dir="${ORCH_BASE_DIR:-${CODA_ORCH_DIR:-$HOME/.config/coda/orchestrators}}"

    if [ -z "$worktree_dir" ]; then
        echo "Usage: _orch_prune_sessions_for_dir <worktree_dir>" >&2
        return 1
    fi

    [ -d "$base_dir" ] || return 0

    local pf port
    for pf in "$base_dir"/*/port; do
        [ -f "$pf" ] || continue
        port=$(cat "$pf")
        [ -z "$port" ] && continue

        # Liveness check: /global/health is tiny and avoids pulling the
        # (potentially huge) shared session list just to confirm a port.
        if ! curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1; then
            continue
        fi

        _orch_prune_dir "$port" "$worktree_dir" --hard --keep 0 --days 0 2>/dev/null || true
    done
}

# Top-level command handler for `coda orch prune [name] [flags]`.
_orch_prune() {
    local name=""
    local flags=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --keep|--days)
                flags+=("$1" "$2")
                shift 2
                ;;
            --hard|--dry-run)
                flags+=("$1")
                shift
                ;;
            --*) echo "Unknown flag: $1" >&2; return 1 ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                fi
                shift
                ;;
        esac
    done

    local base_dir="${ORCH_BASE_DIR:-${CODA_ORCH_DIR:-$HOME/.config/coda/orchestrators}}"

    if [ -n "$name" ]; then
        _orch_prune_one "$name" "${flags[@]+${flags[@]}}"
        return $?
    fi

    # Prune all orchestrators
    local d found=false
    for d in "$base_dir"/*/; do
        [ -d "$d" ] || continue
        found=true
        local n
        n=$(basename "$d")
        _orch_prune_one "$n" "${flags[@]+${flags[@]}}"
    done

    if ! $found; then
        echo "No orchestrators found."
    fi
}

# Prune sessions for a single named orchestrator.
_orch_prune_one() {
    local name="$1"
    shift

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    if [ ! -f "$dir/port" ]; then
        echo "$name: not running (no port file)"
        return 0
    fi

    local port
    port=$(cat "$dir/port")

    case "$port" in
        ''|*[!0-9]*)
            echo "$name: invalid port in $dir/port"
            return 0
            ;;
    esac

    # Health check against /global/health (no directory scope needed
    # for liveness, but the subsequent prune call filters by dir).
    if ! curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1; then
        echo "$name: serve not responding on port $port"
        return 0
    fi

    _orch_prune_dir "$port" "$dir" "$@"
}
