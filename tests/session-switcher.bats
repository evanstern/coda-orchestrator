#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4280
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"

    PLUGIN_DIR="${CODA_ORCH_PLUGIN_DIR:-$HOME/.config/coda/orchestrators/coda-orchestrator}"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"
    source "$PLUGIN_DIR/coda-handler.sh"
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep 'coda-test-' | while read -r s; do
        tmux kill-session -t "$s" 2>/dev/null || true
    done
}

# --- sessions ---

@test "sessions: requires orchestrator name" {
    run _orch_sessions
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "sessions: fails for nonexistent orchestrator" {
    run _orch_sessions nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "sessions: shows no sessions when scope is empty" {
    _orch_new testbot --scope 'coda-test-nosuchsession--*'
    run _orch_sessions testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"No sessions found"* ]]
}

@test "sessions: lists scoped sessions" {
    _orch_new testbot --scope 'coda-test-sw--*'
    tmux new-session -d -s "coda-test-sw--main" "sleep 300"

    run _orch_sessions testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"coda-test-sw--main"* ]]
    [[ "$output" == *"Switch:"* ]]

    tmux kill-session -t "coda-test-sw--main" 2>/dev/null || true
}

@test "sessions: does not list out-of-scope sessions" {
    _orch_new testbot --scope 'coda-test-sw--*'
    tmux new-session -d -s "coda-test-other--main" "sleep 300"

    run _orch_sessions testbot
    [ "$status" -eq 0 ]
    [[ "$output" != *"coda-test-other--main"* ]]

    tmux kill-session -t "coda-test-other--main" 2>/dev/null || true
}

# --- switch ---

@test "switch: requires orchestrator name" {
    run _orch_switch
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "switch: fails for nonexistent orchestrator" {
    run _orch_switch nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "switch: fails for no sessions in scope" {
    _orch_new testbot --scope 'coda-test-nosuchsession--*'
    run _orch_switch testbot 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"No sessions found"* ]]
}

@test "switch: fails for invalid number" {
    _orch_new testbot --scope 'coda-test-sw--*'
    tmux new-session -d -s "coda-test-sw--main" "sleep 300"

    run _orch_switch testbot 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid number"* ]]

    tmux kill-session -t "coda-test-sw--main" 2>/dev/null || true
}

@test "switch: fails for unknown session name" {
    _orch_new testbot --scope 'coda-test-sw--*'
    tmux new-session -d -s "coda-test-sw--main" "sleep 300"

    run _orch_switch testbot "nonexistent-session"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Session not found"* ]]

    tmux kill-session -t "coda-test-sw--main" 2>/dev/null || true
}

# --- scoped_sessions helper ---

@test "scoped_sessions: returns pipe-delimited output" {
    _orch_new testbot --scope 'coda-test-sw--*'
    tmux new-session -d -s "coda-test-sw--main" "sleep 300"

    run _orch_scoped_sessions testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"coda-test-sw--main|"* ]]

    tmux kill-session -t "coda-test-sw--main" 2>/dev/null || true
}

@test "scoped_sessions: includes orch session with --include-orch" {
    _orch_new testbot --scope 'coda-test-sw--*'
    local orch_session
    orch_session=$(_orch_session_name testbot)
    tmux new-session -d -s "$orch_session" "sleep 300"

    run _orch_scoped_sessions testbot --include-orch
    [ "$status" -eq 0 ]
    [[ "$output" == *"$orch_session|"* ]]

    tmux kill-session -t "$orch_session" 2>/dev/null || true
}

# --- handler dispatch ---

@test "dispatch: sessions subcommand is wired" {
    run _coda_orch sessions
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatch: switch subcommand is wired" {
    run _coda_orch switch
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dispatch: help includes sessions and switch" {
    run _coda_orch help
    [ "$status" -eq 0 ]
    [[ "$output" == *"sessions"* ]]
    [[ "$output" == *"switch"* ]]
}
