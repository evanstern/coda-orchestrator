#!/usr/bin/env bats
#
# Verifies that _orch_start backgrounds a prune call after the serve
# is healthy, and that prune failures never block orch start.

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    export CODA_ORCH_PORT_BASE=4260
    export CODA_ORCH_PORT_RANGE=10
    export ORCH_PORT_BASE=4260
    export ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$CODA_ORCH_DIR" "$HOME"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    if [ ! -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        skip "lifecycle.sh not installed in this worktree"
    fi
    if [ ! -f "$PLUGIN_DIR/lib/prune.sh" ]; then
        skip "prune.sh not installed in this worktree"
    fi
    source "$PLUGIN_DIR/lib/prune.sh"
    source "$PLUGIN_DIR/lib/lifecycle.sh"
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep '^coda-test-' | while read -r s; do
            tmux kill-session -t "$s" 2>/dev/null || true
        done
    rm -rf "$CODA_ORCH_DIR" "$HOME"
}

@test "start: triggers a background prune after health check" {
    local name="pruneorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    printf '{"instructions":["SOUL.md"]}\n' > "$dir/opencode.json"

    tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            *) command tmux "$@" ;;
        esac
    }
    export -f tmux

    export PRUNE_MARKER="$BATS_TEST_TMPDIR/prune-called"
    _orch_prune_dir() {
        echo "called port=$1 dir=$2" > "$PRUNE_MARKER"
    }
    export -f _orch_prune_dir

    # Stub curl so the serve looks ready immediately and the session
    # list returns one matching session (so _orch_start completes).
    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_boot"}'
            return 0
        fi
        echo "[{\"id\":\"ses_boot\",\"directory\":\"$dir\",\"time\":{\"created\":1}}]"
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]

    # The prune runs asynchronously. Poll generously.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        [ -f "$PRUNE_MARKER" ] && break
        sleep 1
    done

    [ -f "$PRUNE_MARKER" ]
    grep -q "dir=$dir" "$PRUNE_MARKER"

    unset -f tmux curl _orch_prune_dir
}

@test "start: prune failure does not block start" {
    local name="failprune"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    printf '{"instructions":["SOUL.md"]}\n' > "$dir/opencode.json"

    tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            *) command tmux "$@" ;;
        esac
    }
    export -f tmux

    _orch_prune_dir() {
        echo "boom" >&2
        return 99
    }
    export -f _orch_prune_dir

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_boot"}'
            return 0
        fi
        echo "[{\"id\":\"ses_boot\",\"directory\":\"$dir\",\"time\":{\"created\":1}}]"
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Orchestrator started"* ]]

    unset -f tmux curl _orch_prune_dir
}
