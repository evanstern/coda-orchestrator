#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4280
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export PROJECTS_DIR="$BATS_TEST_TMPDIR/projects"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"
    source "$PLUGIN_DIR/coda-handler.sh"

    # Create a fake project with a bare-like git repo
    mkdir -p "$PROJECTS_DIR/testproject"
    git -C "$PROJECTS_DIR/testproject" init -q --bare
    # Create an initial commit so branches work
    local tmp_clone="$BATS_TEST_TMPDIR/tmp-clone"
    git clone -q "$PROJECTS_DIR/testproject" "$tmp_clone"
    git -C "$tmp_clone" -c user.name='test' -c user.email='test@test' commit -q --allow-empty -m 'init'
    git -C "$tmp_clone" push -q origin main 2>/dev/null || \
        git -C "$tmp_clone" push -q origin master 2>/dev/null
    rm -rf "$tmp_clone"
}

teardown() {
    # Kill any spawned tmux sessions
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep 'coda-test-' | while read -r s; do
        tmux kill-session -t "$s" 2>/dev/null || true
    done
    # Clean up worktrees
    if [ -d "$PROJECTS_DIR/testproject" ]; then
        git -C "$PROJECTS_DIR/testproject" worktree prune 2>/dev/null || true
    fi
}

# --- spawn argument validation ---

@test "spawn: requires all three arguments" {
    run _orch_spawn
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "spawn: requires slug" {
    run _orch_spawn myorch
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "spawn: requires brief" {
    run _orch_spawn myorch myslug
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "spawn: fails for nonexistent orchestrator" {
    run _orch_spawn nonexistent myslug "do the thing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# --- concurrency limit ---

@test "spawn: enforces concurrency limit" {
    _orch_new testbot --scope 'coda-testproject--*'

    # Create fake spawn sessions to hit the limit
    for i in $(seq 1 5); do
        tmux new-session -d -s "coda-fake--spawn-task${i}" "sleep 300"
    done

    run _orch_spawn testbot myslug "do the thing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Concurrency limit"* ]]

    # Cleanup fake sessions
    for i in $(seq 1 5); do
        tmux kill-session -t "coda-fake--spawn-task${i}" 2>/dev/null || true
    done
}

# --- project resolution ---

@test "spawn: resolves project from scope watch pattern" {
    _orch_new testbot --scope 'coda-testproject--*'

    # This will fail at the opencode serve step (no opencode in test),
    # but we can verify it got past project resolution
    run _orch_spawn testbot myslug "do the thing"
    # Should not fail with "Cannot determine project"
    [[ "$output" != *"Cannot determine project"* ]]
}

@test "spawn: fails for missing project directory" {
    _orch_new testbot --scope 'coda-nonexistent--*'
    run _orch_spawn testbot myslug "do the thing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Project directory not found"* ]]
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

# --- auto-trigger ---

@test "spawn: trigger message sends read @IMPLEMENT.md and execute" {
    grep -q 'read @IMPLEMENT.md and execute' "$PLUGIN_DIR/lib/spawn.sh"
}

@test "spawn: trigger uses opencode run --attach with --format json" {
    grep -q 'opencode run --attach.*--format json.*read @IMPLEMENT.md' "$PLUGIN_DIR/lib/spawn.sh"
}

# --- handler dispatch ---

@test "dispatch: spawn subcommand is wired" {
    run _coda_orch spawn
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatch: spawns subcommand is wired" {
    run _coda_orch spawns
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatch: help includes spawn" {
    run _coda_orch help
    [[ "$output" == *"spawn"* ]]
}
