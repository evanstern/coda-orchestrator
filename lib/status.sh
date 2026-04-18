#!/usr/bin/env bash
#
# status.sh -- tree-view orchestrator status with PR + focus card metadata
#
# Provides `_orch_status [name]`. When name is given, shows one orchestrator
# and its child feature sessions. When omitted, shows every orchestrator in
# $ORCH_BASE_DIR. Output groups feature sessions under their owner orchestrator
# in an ASCII tree, annotating each session with its PR status and listing the
# project's active focus cards on the final branch of each subtree.
#
# Sourced by lib/spawn.sh so this function definition wins over the legacy
# implementation in lib/observe.sh (which is loaded earlier by coda-handler.sh).
#

# --- helpers ------------------------------------------------------------------

# Strip ANSI color codes from stdin.
_orch_status_strip_ansi() {
    sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
}

# Match a session name against newline-separated glob patterns.
# Usage: _orch_status_match <session> <patterns_var_name>
# Returns 0 on match, 1 otherwise.
_orch_status_match_any() {
    local sess="$1"
    local patterns="$2"
    [ -z "$patterns" ] && return 1
    local pattern
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        # shellcheck disable=SC2254
        case "$sess" in $pattern) return 0 ;; esac
    done <<< "$patterns"
    return 1
}

# Decide if a session belongs to an orchestrator's scope.
# Args: <session> <watch_patterns> <ignore_patterns>
_orch_status_session_in_scope() {
    local sess="$1" watch="$2" ignore="$3"
    _orch_status_match_any "$sess" "$watch" || return 1
    if [ -n "$ignore" ] && _orch_status_match_any "$sess" "$ignore"; then
        return 1
    fi
    return 0
}

# Extract project + branch from a feature session name.
# Convention: "${SESSION_PREFIX}<sanitized-project>--<branch>"
# Echos "<project>\t<branch>" or empty string if it does not parse.
_orch_status_parse_session() {
    local sess="$1"
    local prefix="${SESSION_PREFIX:-coda-}"
    local rest="${sess#"$prefix"}"
    [ "$rest" = "$sess" ] && return 0
    case "$rest" in
        *--*) ;;
        *) return 0 ;;
    esac
    local project="${rest%%--*}"
    local branch="${rest#*--}"
    [ -z "$project" ] && return 0
    [ -z "$branch" ] && return 0
    printf '%s\t%s\n' "$project" "$branch"
}

# Resolve the working dir to use when querying gh for a project.
# Tries $PROJECTS_DIR/<project>/main, then $PROJECTS_DIR/<project>.
# Returns 1 if neither exists.
_orch_status_project_dir() {
    local project="$1"
    local base="${PROJECTS_DIR:-$HOME/projects}"
    if [ -n "$project" ] && [ -d "$base/$project/main" ]; then
        echo "$base/$project/main"
        return 0
    fi
    if [ -n "$project" ] && [ -d "$base/$project" ]; then
        echo "$base/$project"
        return 0
    fi
    return 1
}

# Look up PR state for a single (project, branch) pair.
# Echos "#<num> <STATE>" (e.g. "#19 MERGED") or empty when no PR / no gh.
# Cached via the associative array _ORCH_STATUS_PR_CACHE.
declare -gA _ORCH_STATUS_PR_CACHE 2>/dev/null || true

_orch_status_pr_lookup() {
    local project="$1" branch="$2"
    local key="$project::$branch"
    if [ "${_ORCH_STATUS_PR_CACHE[$key]+x}" = "x" ]; then
        printf '%s' "${_ORCH_STATUS_PR_CACHE[$key]}"
        return 0
    fi

    local result=""
    if command -v gh &>/dev/null; then
        local dir
        if dir="$(_orch_status_project_dir "$project")"; then
            local json
            json=$(cd "$dir" 2>/dev/null && \
                gh pr list --head "$branch" --state all \
                    --json number,state --limit 1 2>/dev/null) || json=""
            if [ -n "$json" ] && command -v jq &>/dev/null; then
                local num state
                num=$(printf '%s' "$json" | jq -r '.[0].number // empty' 2>/dev/null)
                state=$(printf '%s' "$json" | jq -r '.[0].state // empty' 2>/dev/null)
                if [ -n "$num" ]; then
                    local state_lc
                    state_lc=$(printf '%s' "$state" | tr '[:upper:]' '[:lower:]')
                    result="#$num, $state_lc"
                fi
            fi
        fi
    fi

    _ORCH_STATUS_PR_CACHE[$key]="$result"
    printf '%s' "$result"
}

# List active focus card IDs (and a couple of backlog hints) for a project.
# Echos a single line like "#51 (active), #45 (active), #62 (backlog)" or empty.
_orch_status_focus_cards() {
    local project="$1"
    [ -z "$project" ] && return 0
    command -v focus &>/dev/null || return 0

    local active_raw backlog_raw
    active_raw=$(focus list active --project "$project" --no-color 2>/dev/null \
        | _orch_status_strip_ansi)
    backlog_raw=$(focus list backlog --project "$project" --no-color 2>/dev/null \
        | _orch_status_strip_ansi)

    # Collect IDs (numeric tokens at the start of each card row).
    local out="" id
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        [ -n "$out" ] && out+=", "
        out+="#${id} (active)"
    done < <(printf '%s\n' "$active_raw" \
        | awk '/^[0-9]+[[:space:]]/ { print $1 }')

    local backlog_ids=()
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        backlog_ids+=("$id")
    done < <(printf '%s\n' "$backlog_raw" \
        | awk '/^[0-9]+[[:space:]]/ { print $1 }' | head -3)

    local b
    for b in "${backlog_ids[@]}"; do
        [ -n "$out" ] && out+=", "
        out+="#${b}"
    done

    printf '%s' "$out"
}

# --- main entry points --------------------------------------------------------

_orch_status() {
    local name="${1:-}"

    if [ ! -d "$ORCH_BASE_DIR" ]; then
        echo "No orchestrators found."
        echo "  Create one: coda orch new <name>"
        return 0
    fi

    # Reset PR cache on each top-level invocation so output is fresh.
    _ORCH_STATUS_PR_CACHE=()

    # Snapshot tmux sessions once.
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

    if [ -n "$name" ]; then
        local dir
        dir="$(_orch_dir "$name")"
        if [ ! -d "$dir" ]; then
            echo "Orchestrator not found: $name"
            return 1
        fi
        _orch_status_render_one "$name" "$sessions"
        return 0
    fi

    local d found=false
    for d in "$ORCH_BASE_DIR"/*/; do
        [ -d "$d" ] || continue
        found=true
        local n
        n=$(basename "$d")
        _orch_status_render_one "$n" "$sessions"
        echo ""
    done

    if ! $found; then
        echo "No orchestrators found."
        echo "  Create one: coda orch new <name>"
    fi
}

# Render one orchestrator block. Args: <name> <sessions-snapshot>
_orch_status_render_one() {
    local name="$1"
    local sessions="$2"
    local dir
    dir="$(_orch_dir "$name")"

    local state="stopped"
    if _orch_is_running "$name" 2>/dev/null; then
        state="active"
    fi

    printf '%s (%s)\n' "$name" "$state"

    local scope_file="$dir/scope.json"
    local watch="" ignore="" project=""
    if [ -f "$scope_file" ] && command -v jq &>/dev/null; then
        watch=$(jq -r '.watch[]? // empty' "$scope_file" 2>/dev/null)
        ignore=$(jq -r '.ignore[]? // empty' "$scope_file" 2>/dev/null)
        project=$(jq -r '.project // empty' "$scope_file" 2>/dev/null)
    fi

    if [ -z "$watch" ]; then
        printf '  (no scope defined)\n'
        return 0
    fi

    # Collect matching child sessions (skip the orchestrator's own session).
    local own_session
    own_session="$(_orch_session_name "$name")"

    local children=()
    local sess
    while IFS= read -r sess; do
        [ -z "$sess" ] && continue
        [ "$sess" = "$own_session" ] && continue
        if _orch_status_session_in_scope "$sess" "$watch" "$ignore"; then
            children+=("$sess")
        fi
    done <<< "$sessions"

    local focus_line=""
    focus_line="$(_orch_status_focus_cards "$project")"

    if [ ${#children[@]} -eq 0 ] && [ -z "$focus_line" ]; then
        printf '  (no child sessions, no focus cards)\n'
        return 0
    fi

    # Print children. Last item uses '+-', others use '|-'. If a focus line
    # is present, it becomes the last branch instead.
    local total=${#children[@]}
    local has_focus=0
    [ -n "$focus_line" ] && has_focus=1

    local i=0
    local sess_i project_i branch_i parsed pr connector
    for sess_i in "${children[@]}"; do
        i=$((i + 1))
        local is_last=0
        if [ $i -eq $total ] && [ $has_focus -eq 0 ]; then
            is_last=1
        fi
        if [ $is_last -eq 1 ]; then
            connector="+-"
        else
            connector="|-"
        fi

        parsed="$(_orch_status_parse_session "$sess_i")"
        if [ -n "$parsed" ]; then
            project_i="${parsed%%$'\t'*}"
            branch_i="${parsed#*$'\t'}"
        else
            project_i=""
            branch_i="$sess_i"
        fi

        local lookup_project="${project_i:-$project}"
        pr="$(_orch_status_pr_lookup "$lookup_project" "$branch_i")"

        # Show "<project>/<branch>" when project differs from orch's
        # primary project (or when orch has no primary project set), so
        # duplicate branch names across projects are distinguishable.
        local label="$branch_i"
        if [ -n "$project_i" ] && [ "$project_i" != "$project" ]; then
            label="$project_i/$branch_i"
        fi

        if [ -n "$pr" ]; then
            printf '  %s %s [PR %s]\n' "$connector" "$label" "$pr"
        else
            printf '  %s %s\n' "$connector" "$label"
        fi
    done

    if [ $has_focus -eq 1 ]; then
        printf '  +- focus: %s\n' "$focus_line"
    fi
}
