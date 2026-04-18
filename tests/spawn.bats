#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4280
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export PROJECTS_DIR="$BATS_TEST_TMPDIR/projects"
    export HOME="$BATS_TEST_TMPDIR/home"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    export ORCH_PORT_BASE="$CODA_ORCH_PORT_BASE"
    export ORCH_PORT_RANGE="$CODA_ORCH_PORT_RANGE"

    if [ -f "$PLUGIN_DIR/coda-handler.sh" ]; then
        source "$PLUGIN_DIR/coda-handler.sh"
    else
        # Fallback for clean checkouts without the installed plugin handler:
        # source tracked modules directly and define a minimal dispatcher.
        for mod in lifecycle observe spawn; do
            [ -f "$PLUGIN_DIR/lib/${mod}.sh" ] && source "$PLUGIN_DIR/lib/${mod}.sh"
        done
        _coda_orch() {
            local subcmd="${1:-help}"
            shift 2>/dev/null || true
            case "$subcmd" in
                spawns)  _orch_spawn_status "$@" ;;
                help|"") echo "coda orch -- help (stub)" ;;
                *) echo "Unknown orch subcommand: $subcmd"; return 1 ;;
            esac
        }
    fi

    # Stub helpers so tests don't depend on the gitignored lifecycle.sh.
    if ! declare -f _orch_dir &>/dev/null; then
        _orch_dir() { echo "$ORCH_BASE_DIR/$1"; }
    fi
    if ! declare -f _orch_new &>/dev/null; then
        _orch_new() {
            local name="$1"
            mkdir -p "$ORCH_BASE_DIR/$name"
            printf '{"watch":[],"ignore":[]}\n' > "$ORCH_BASE_DIR/$name/scope.json"
        }
    fi
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep 'coda-test-' | while read -r s; do
        tmux kill-session -t "$s" 2>/dev/null || true
    done
}

# --- spawns (status) ---

@test "spawns: requires orchestrator name" {
    run _orch_spawn_status
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "spawns: fails for nonexistent orchestrator" {
    run _orch_spawn_status nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "spawns: shows empty when no spawns" {
    _orch_new testbot
    run _orch_spawn_status testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"no active spawned sessions"* ]]
}

@test "spawns: lists active spawn sessions" {
    _orch_new testbot
    mkdir -p "$CODA_ORCH_DIR/testbot/logs"
    echo '{"type":"text","part":{"text":"working..."}}' > "$CODA_ORCH_DIR/testbot/logs/spawn-task1.log"
    tmux new-session -d -s "coda-test--spawn-task1" "sleep 300"

    run _orch_spawn_status testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"spawn-task1"* ]]

    tmux kill-session -t "coda-test--spawn-task1" 2>/dev/null || true
}

# --- feature-hook presence (replaces former _orch_spawn) ---

@test "feature-hook: _coda_feature_orch_hook is defined" {
    source "$PLUGIN_DIR/lib/feature-hook.sh"
    run type -t _coda_feature_orch_hook
    [ "$status" -eq 0 ]
    [ "$output" = "function" ]
}

@test "feature-hook: trigger message sends read @IMPLEMENT.md and execute" {
    grep -q 'read @IMPLEMENT.md and execute' "$PLUGIN_DIR/lib/feature-hook.sh"
}

@test "feature-hook: trigger uses opencode run --attach with --format json" {
    grep -qE 'opencode run --attach.*--format json' "$PLUGIN_DIR/lib/feature-hook.sh"
}

@test "shell-init: sources feature-hook.sh" {
    grep -q 'feature-hook.sh' "$PLUGIN_DIR/lib/shell-init.sh"
}

# --- handler dispatch ---

@test "dispatch: spawn subcommand is removed" {
    run _coda_orch spawn
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown orch subcommand"* ]]
}

@test "dispatch: spawns subcommand is wired" {
    run _coda_orch spawns
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatch: help does not advertise spawn" {
    run _coda_orch help
    [[ "$output" != *"coda orch spawn "* ]]
}
