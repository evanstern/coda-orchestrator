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

_orch_has_soul_plugin() {
    [ -f "$HOME/.config/coda/plugins/soul/coda-handler.sh" ]
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

    if _orch_has_soul_plugin; then
        local soul_args=("$name" --dir "$dir")
        [ -n "$soul_text" ] && soul_args+=(--template "$_ORCH_PLUGIN_DIR/defaults/SOUL.md.tmpl")
        coda soul init "${soul_args[@]}"

        if [ -n "$soul_text" ]; then
            _orch_generate_soul "$name" "$soul_text" > "$dir/SOUL.md"
        fi
    else
        if [ -n "$soul_text" ]; then
            _orch_generate_soul "$name" "$soul_text" > "$dir/SOUL.md"
        else
            cp "$_ORCH_PLUGIN_DIR/defaults/SOUL.md.tmpl" "$dir/SOUL.md"
            sed -i "s/{{NAME}}/$name/g" "$dir/SOUL.md"
        fi
        printf '# Memory — %s\n\nNo observations yet.\n' "$name" > "$dir/MEMORY.md"
    fi

    if [ -n "$scope_pattern" ]; then
        printf '{"watch":["%s"],"ignore":["coda-orch--*","coda-mcp-server","coda-watcher"]}\n' "$scope_pattern" > "$dir/scope.json"
    else
        cp "$_ORCH_PLUGIN_DIR/defaults/scope.json.tmpl" "$dir/scope.json"
    fi

    _orch_generate_agents_md "$name" > "$dir/AGENTS.md"
    _orch_generate_project_config "$name" > "$dir/opencode.json"

    # Install skills from defaults/skills/ if not already present
    local skills_src="$_ORCH_PLUGIN_DIR/defaults/skills"
    if [ -d "$skills_src" ]; then
        for skill_dir in "$skills_src"/*/; do
            local skill_name
            skill_name="$(basename "$skill_dir")"
            local skill_dest="${HOME}/.config/opencode/skills/${skill_name}"
            if [ ! -f "$skill_dest/SKILL.md" ]; then
                mkdir -p "$skill_dest"
                cp "$skill_dir/SKILL.md" "$skill_dest/SKILL.md"
            fi
        done
    fi

    echo "Created orchestrator: $name"
    echo "  Dir:  $dir"
    echo "  Soul: $dir/SOUL.md"
    echo "  Start with: coda orch start $name"
}

_orch_generate_project_config() {
    local name="$1"
    printf '{"instructions": ["SOUL.md", "MEMORY.md", "PROJECT.md", "inbox.md"]}\n'
}

_orch_generate_agents_md() {
    local name="$1"

    cat <<'EOF'
# Session Bootstrap

**FIRST ACTION ON EVERY NEW SESSION: Run `/boot-identity`**

You are an orchestrator agent, not a generic assistant. Your identity, memory,
and personality live in this directory. The `/boot-identity` skill reads them
and loads you up. Run it before doing anything else.

If the skill is not available, manually read these files in order:
1. `SOUL.md` -- your identity (name, personality, role, workflows)
2. `PROJECT.md` -- what you're working on
3. `MEMORY.md` -- curated long-term memory
4. Most recent files in `memory/` -- daily observations
5. Most recent files in `learnings/` -- session insights
6. `scope.json` -- session boundaries

After loading: respond as yourself, in your voice. Not as Claude Code.

---

## Important Reminders

- `memory/` and `learnings/` -- safe to commit inline on main
- Everything else -- requires a feature branch and PR
- Commit memory writes immediately. No batching.
EOF

    cat <<DYNAMIC

## Capabilities

- Check status of sessions via \`coda orch status $name\`
- Capture observations in \`memory/YYYY-MM-DD.md\`
- Curate important learnings into \`MEMORY.md\`
- Spawn feature sessions via \`coda feature\` workflow
- Track work via \`focus\` CLI

## Memory Protocol

You wake up fresh each session. Your continuity comes from the files above.
Read them. That's how you remember.

## Interaction

Other agents and humans send prompts via \`coda orch send $name "message"\`.
Respond according to the personality in SOUL.md.
DYNAMIC
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

    [ -f "$dir/AGENTS.md" ] || _orch_generate_agents_md "$name" > "$dir/AGENTS.md"
    [ -f "$dir/opencode.json" ] || _orch_generate_project_config "$name" > "$dir/opencode.json"

    if [ -f "$dir/opencode.json" ] && command -v jq &>/dev/null; then
        if jq -e '.instructions | type == "array"' "$dir/opencode.json" >/dev/null 2>&1 && \
           ! jq -e '.instructions | index("inbox.md")' "$dir/opencode.json" >/dev/null 2>&1; then
            local tmp_file
            tmp_file=$(mktemp "$dir/opencode.json.tmp.XXXXXX") || return 1
            if jq '.instructions += ["inbox.md"]' "$dir/opencode.json" > "$tmp_file"; then
                mv "$tmp_file" "$dir/opencode.json"
            else
                rm -f "$tmp_file"
            fi
        fi
    fi

    local port
    port=$(_orch_find_free_port)
    if [ -z "$port" ]; then
        echo "No free ports in range ${ORCH_PORT_BASE}-$((ORCH_PORT_BASE + ORCH_PORT_RANGE))"
        return 1
    fi

    local permission='{"*":"allow"}'
    local serve_cmd="OPENCODE_PERMISSION='$permission' opencode serve --port $port"

    echo "$port" > "$dir/port"

    tmux new-session -d -s "$session" -c "$dir" "$serve_cmd; exec $SHELL"

    tmux set-environment -t "$session" CODA_ORCH_NAME "$name"
    tmux set-option -t "$session" status-right \
        "#($_ORCH_PLUGIN_DIR/lib/inbox-status.sh $dir) #(tmux list-sessions | wc -l | tr -d ' ') sessions | %H:%M"

    # Wait for opencode serve to be ready, then persist the active
    # session id (scoped to $dir) to $dir/session-id so coda orch send
    # can target the right session.
    local base="http://localhost:$port"
    local wait_secs=10
    local elapsed=0
    while [ $elapsed -lt $wait_secs ]; do
        if curl -sf "$base/session" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ $elapsed -lt $wait_secs ]; then
        local session_id
        session_id=$(curl -sf "$base/session" \
            | jq -r --arg d "$dir" \
                '[.[] | select(.directory == $d)] | sort_by(.time.created) | last | .id // empty' 2>/dev/null)

        if [ -z "$session_id" ]; then
            session_id=$(curl -sf -X POST "$base/session" \
                -H 'Content-Type: application/json' -d '{}' \
                | jq -r '.id // empty' 2>/dev/null)
        fi

        if [ -n "$session_id" ]; then
            echo "$session_id" > "$dir/session-id"
        else
            echo "Warning: could not determine session ID for $name" >&2
        fi
    else
        echo "Warning: timed out waiting for serve on port $port" >&2
    fi

    # Background prune: wait for health, then prune stale sessions
    # scoped to this orchestrator's directory. Non-blocking; failures
    # are swallowed so prune can never fail orch start.
    if declare -f _orch_prune_dir >/dev/null 2>&1; then
        (
            local prune_ready=0
            for _orch_start_prune_i in 1 2 3 4 5; do
                if curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1; then
                    prune_ready=1
                    break
                fi
                sleep 1
            done
            if [ "$prune_ready" -eq 1 ]; then
                _orch_prune_dir "$port" "$dir" >/dev/null 2>&1 || true
            fi
        ) &
        disown 2>/dev/null || true
    fi

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
    rm -f "$dir/session-id"

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

# Source prune.sh for session pruning primitives
_orch_lifecycle_dir="${BASH_SOURCE%/*}"
if [ -f "$_orch_lifecycle_dir/prune.sh" ]; then
    # shellcheck source=/dev/null
    source "$_orch_lifecycle_dir/prune.sh"
fi
unset _orch_lifecycle_dir
