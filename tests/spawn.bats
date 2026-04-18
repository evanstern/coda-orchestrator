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
    source "$PLUGIN_DIR/coda-handler.sh"
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
