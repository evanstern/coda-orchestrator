#!/usr/bin/env bash
#
# lifecycle.sh -- orchestrator create, start, stop, list, teardown
#

_orch_session_name() {
    echo "${SESSION_PREFIX}orch--${1}"
}

_orch_dir() {
    echo "${ORCH_BASE_DIR}/${1}"
}

_orch_find_free_port() {
    local port=$ORCH_PORT_BASE
    local max=$((ORCH_PORT_BASE + ORCH_PORT_RANGE))

    local claimed_ports=""
    if [ -d "$ORCH_BASE_DIR" ]; then
        for pf in "$ORCH_BASE_DIR"/*/port; do
            [ -f "$pf" ] && claimed_ports="$claimed_ports $(cat "$pf")"
        done
    fi

    while [ "$port" -le "$max" ]; do
        if ! ss -tlnp 2>/dev/null | grep -q ":${port} " && \
           ! echo "$claimed_ports" | grep -qw "$port"; then
            echo "$port"
            return
        fi
        port=$((port + 1))
    done
}

_orch_is_running() {
    local name="$1"
    if tmux has-session -t "$(_orch_session_name "$name")" 2>/dev/null; then
        return 0
    fi
    # Clean stale port file if session is dead
    rm -f "$(_orch_dir "$name")/port"
    return 1
}

_orch_new() {
    local name=""
    local soul_text=""
    local scope_pattern=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --soul)   soul_text="$2"; shift 2 ;;
            --scope)  scope_pattern="$2"; shift 2 ;;
            --*)      echo "Unknown flag: $1"; return 1 ;;
            *)        name="$1"; shift ;;
        esac
    done

    if [ -z "$name" ]; then
        echo "Usage: coda orch new <name> [--soul \"...\"] [--scope \"pattern\"]"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ -d "$dir" ]; then
        echo "Orchestrator already exists: $name"
        echo "  Dir: $dir"
        return 1
    fi

    mkdir -p "$dir/memory"

    git init -q "$dir"
    git -C "$dir" add -A && \
        git -C "$dir" -c user.name='coda orch' -c user.email='coda-orch@local' \
            commit -q -m 'init orchestrator' --allow-empty

    # Generate or copy SOUL.md
    if [ -n "$soul_text" ]; then
        _orch_generate_soul "$name" "$soul_text" > "$dir/SOUL.md"
    else
        cp "$_ORCH_PLUGIN_DIR/defaults/SOUL.md.tmpl" "$dir/SOUL.md"
        sed -i "s/{{NAME}}/$name/g" "$dir/SOUL.md"
    fi

    if [ -n "$scope_pattern" ]; then
        printf '{"watch":["%s"],"ignore":["coda-orch--*","coda-mcp-server","coda-watcher"]}\n' "$scope_pattern" > "$dir/scope.json"
    else
        cp "$_ORCH_PLUGIN_DIR/defaults/scope.json.tmpl" "$dir/scope.json"
    fi

    # MEMORY.md
    printf '# Memory -- %s\n\nNo observations yet.\n' "$name" > "$dir/MEMORY.md"

    _orch_generate_agents_md "$name" > "$dir/AGENTS.md"
    _orch_generate_project_config "$name" > "$dir/opencode.json"

    echo "Created orchestrator: $name"
    echo "  Dir:  $dir"
    echo "  Soul: $dir/SOUL.md"
    echo "  Start with: coda orch start $name"
}

_orch_generate_project_config() {
    local name="$1"
    printf '{"instructions": ["SOUL.md", "MEMORY.md"]}\n'
}

_orch_generate_agents_md() {
    local name="$1"
    local dir
    dir="$(_orch_dir "$name")"

    # Header
    cat <<'HEADER'
# IDENTITY OVERRIDE

**You are NOT Claude Code. You are NOT a generic assistant.**

You are a specialized orchestrator agent. Your name, personality, role, and
boundaries are defined below. When asked who you are, respond with your
orchestrator identity -- never as "Claude Code" or "Anthropic's CLI agent".

Follow the personality defined below precisely.
HEADER

    # Inline SOUL.md -- this IS the personality
    if [ -f "$dir/SOUL.md" ]; then
        printf '\n---\n\n'
        cat "$dir/SOUL.md"
        printf '\n\n---\n\n'
    fi

    # Inline MEMORY.md -- continuity across sessions
    if [ -f "$dir/MEMORY.md" ]; then
        printf '## Long-term Memory\n\n'
        cat "$dir/MEMORY.md"
        printf '\n\n'
    fi

    # Operational instructions
    cat <<EOF
## Your Scope

You observe and manage coda sessions that match the patterns in scope.json.
Do NOT act on sessions outside your scope.

## Capabilities

- Check status of sessions in your scope via \`coda orch status $name\`
- Capture observations in memory/ daily files (memory/YYYY-MM-DD.md)
- Curate important learnings into MEMORY.md
- Read SOUL.md and MEMORY.md for your current personality and context

## Memory Protocol

You wake up fresh each session. Your continuity comes from:
- **memory/YYYY-MM-DD.md** -- daily raw observations. Create if missing.
- **MEMORY.md** -- curated learnings. Update when you notice patterns worth keeping.

## Interaction

Other agents and humans send you prompts via \`coda orch send $name "message"\`.
Respond according to the personality defined above.

## Important

- Stay in character. Your SOUL.md defines who you are.
- Stay within your scope. Don't act on sessions outside your watch patterns.
- When uncertain, observe and record rather than act.
EOF
}

_orch_start() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch start <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        echo "  Create with: coda orch new $name"
        return 1
    fi

    local session
    session="$(_orch_session_name "$name")"

    if tmux has-session -t "$session" 2>/dev/null; then
        echo "Orchestrator already running: $name"
        echo "  Attach: tmux attach -t $session"
        return 0
    fi

    _orch_generate_agents_md "$name" > "$dir/AGENTS.md"
    _orch_generate_project_config "$name" > "$dir/opencode.json"

    local port
    port=$(_orch_find_free_port)
    if [ -z "$port" ]; then
        echo "No free ports in range ${ORCH_PORT_BASE}-$((ORCH_PORT_BASE + ORCH_PORT_RANGE))"
        return 1
    fi

    local permission='{"*":"allow"}'
    local serve_cmd="OPENCODE_PERMISSION='$permission' opencode serve --pure --port $port"

    echo "$port" > "$dir/port"

    tmux new-session -d -s "$session" -c "$dir" "$serve_cmd; exec $SHELL"

    echo "Orchestrator started: $name"
    echo "  Session: $session"
    echo "  Port:    $port"
    echo "  Dir:     $dir"
    echo "  Attach:  opencode attach http://localhost:$port"
    echo "  Send:    coda orch send $name \"message\""
}

_orch_stop() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch stop <name>"
        return 1
    fi

    local session
    session="$(_orch_session_name "$name")"

    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "Orchestrator is not running: $name"
        return 0
    fi

    tmux kill-session -t "$session"

    local dir
    dir="$(_orch_dir "$name")"
    rm -f "$dir/port"

    echo "Orchestrator stopped: $name"
}

_orch_ls() {
    local no_color=false
    [ "${1:-}" = "--no-color" ] && no_color=true

    if [ ! -d "$ORCH_BASE_DIR" ]; then
        echo "No orchestrators found."
        echo "  Create one: coda orch new <name>"
        return 0
    fi

    local found=false
    for dir in "$ORCH_BASE_DIR"/*/; do
        [ -d "$dir" ] || continue
        found=true

        local name
        name=$(basename "$dir")
        local state="stopped"
        local port_info=""
        local scope_info=""

        if _orch_is_running "$name"; then
            state="running"
            if [ -f "$dir/port" ]; then
                port_info=" (port $(cat "$dir/port"))"
            fi
        fi

        if [ -f "$dir/scope.json" ] && command -v jq &>/dev/null; then
            scope_info=" scope: $(jq -r '.watch | join(", ")' "$dir/scope.json" 2>/dev/null)"
        fi

        printf "  %-20s  %-8s%s%s\n" "$name" "$state" "$port_info" "$scope_info"
    done

    if ! $found; then
        echo "No orchestrators found."
        echo "  Create one: coda orch new <name>"
    fi
}

_orch_done() {
    local name=""
    local archive=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --archive) archive=true; shift ;;
            --*)       echo "Unknown flag: $1"; return 1 ;;
            *)         name="$1"; shift ;;
        esac
    done

    if [ -z "$name" ]; then
        echo "Usage: coda orch done <name> [--archive]"
        return 1
    fi

    _orch_stop "$name" 2>/dev/null

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    if $archive; then
        local archive_dir="${ORCH_BASE_DIR}/.archive/${name}-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$(dirname "$archive_dir")"
        mv "$dir" "$archive_dir"
        echo "Orchestrator archived: $name"
        echo "  Archive: $archive_dir"
    else
        rm -rf "$dir"
        echo "Orchestrator removed: $name"
    fi
}
