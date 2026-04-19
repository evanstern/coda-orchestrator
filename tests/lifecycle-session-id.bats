#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4260
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    # lifecycle.sh reads these unprefixed names (set by coda-handler.sh
    # normally). When loading lifecycle.sh directly in tests, set them.
    export ORCH_PORT_BASE=4260
    export ORCH_PORT_RANGE=10
    export ORCH_PORT_BASE=4260
    export ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    if [ ! -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        skip "lifecycle.sh not installed in this worktree"
    fi
    source "$PLUGIN_DIR/lib/lifecycle.sh"
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep '^coda-test-' | while read -r s; do
            tmux kill-session -t "$s" 2>/dev/null || true
        done
    rm -rf "$CODA_ORCH_DIR" "$HOME"
}

# --- session-id write on boot ---

@test "start: writes session-id file after serve comes up" {
    local name="bootorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    printf '{"instructions":["SOUL.md"]}\n' > "$dir/opencode.json"

    # Stub tmux so we don't actually spawn opencode serve.
    tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            *) command tmux "$@" ;;
        esac
    }
    export -f tmux

    # Stub curl so the readiness probe succeeds and the session lookup
    # returns one session scoped to $dir.
    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_created"}'
            return 0
        fi
        cat <<JSON
[
  {"id":"ses_ghost","directory":"/other/orch","time":{"created":9999}},
  {"id":"ses_ours","directory":"$dir","time":{"created":1000}}
]
JSON
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]
    [ -f "$dir/session-id" ]
    [ "$(cat "$dir/session-id")" = "ses_ours" ]

    unset -f tmux curl
}

@test "start: creates a new session when none match directory" {
    local name="emptyorch"
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

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_fresh"}'
            return 0
        fi
        # GET /session returns only ghost sessions.
        echo '[{"id":"ses_ghost","directory":"/other","time":{"created":9999}}]'
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]
    [ -f "$dir/session-id" ]
    [ "$(cat "$dir/session-id")" = "ses_fresh" ]

    unset -f tmux curl
}

@test "stop: removes session-id file" {
    local name="stoporch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    echo "ses_stale" > "$dir/session-id"
    echo "4261" > "$dir/port"

    tmux() {
        case "$1" in
            has-session) return 0 ;;
            kill-session) return 0 ;;
            *) command tmux "$@" ;;
        esac
    }
    export -f tmux

    run _orch_stop "$name"
    [ "$status" -eq 0 ]
    [ ! -f "$dir/session-id" ]

    unset -f tmux
}
