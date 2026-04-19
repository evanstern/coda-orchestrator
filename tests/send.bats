#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4270
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    # Load send.sh directly (the unit under test). Also load lifecycle
    # if available, otherwise stub the helpers it provides.
    if [ -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        source "$PLUGIN_DIR/lib/lifecycle.sh"
    fi
    source "$PLUGIN_DIR/lib/send.sh"

    if ! declare -f _orch_dir &>/dev/null; then
        _orch_dir() { echo "$ORCH_BASE_DIR/$1"; }
    fi
    if ! declare -f _orch_session_name &>/dev/null; then
        _orch_session_name() { echo "${SESSION_PREFIX}orch--$1"; }
    fi
    if ! declare -f _orch_is_running &>/dev/null; then
        _orch_is_running() { return 0; }
    fi
    # Force orch-is-running true so send reaches session resolution.
    _orch_is_running() { return 0; }
    export -f _orch_is_running
}

teardown() {
    rm -rf "$CODA_ORCH_DIR" "$HOME"
    tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep '^coda-test-' | while read -r s; do
            tmux kill-session -t "$s" 2>/dev/null || true
        done
}

# --- argument validation ---

@test "send: requires name and message" {
    run _orch_send
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "send: rejects unknown flags" {
    run _orch_send --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flag"* ]]
}

@test "send: accepts --async flag without choking" {
    run _orch_send --async
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# --- session resolution ---

@test "resolve_session: prefers session-id file when present" {
    local dir="$BATS_TEST_TMPDIR/orch1"
    mkdir -p "$dir"
    echo "ses_from_file" > "$dir/session-id"

    # Stub curl to fail so only the file path can succeed.
    curl() { return 7; }
    export -f curl

    run _orch_send_resolve_session "$dir" "http://localhost:1"
    [ "$status" -eq 0 ]
    [ "$output" = "ses_from_file" ]

    unset -f curl
}

@test "resolve_session: trims whitespace from session-id file" {
    local dir="$BATS_TEST_TMPDIR/orch2"
    mkdir -p "$dir"
    printf '  ses_trimmed  \n' > "$dir/session-id"

    curl() { return 7; }
    export -f curl

    run _orch_send_resolve_session "$dir" "http://localhost:1"
    [ "$status" -eq 0 ]
    [ "$output" = "ses_trimmed" ]

    unset -f curl
}

@test "resolve_session: falls back to directory-scoped GET when no file" {
    local dir="$BATS_TEST_TMPDIR/orch3"
    mkdir -p "$dir"

    # Stub curl: GET returns a list with one matching and one ghost session.
    curl() {
        local url="${@: -1}"
        if [[ "$*" == *"-X POST"* ]]; then
            return 7
        fi
        cat <<JSON
[
  {"id":"ses_ghost","directory":"/some/other/dir","time":{"created":9999}},
  {"id":"ses_ours","directory":"$dir","time":{"created":1000}},
  {"id":"ses_ours_newer","directory":"$dir","time":{"created":2000}}
]
JSON
    }
    export -f curl

    run _orch_send_resolve_session "$dir" "http://localhost:1"
    [ "$status" -eq 0 ]
    [ "$output" = "ses_ours_newer" ]

    unset -f curl
}

@test "resolve_session: ignores sessions from other directories" {
    local dir="$BATS_TEST_TMPDIR/orch4"
    mkdir -p "$dir"

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_created"}'
            return 0
        fi
        cat <<JSON
[
  {"id":"ses_ghost1","directory":"/not/us","time":{"created":9999}},
  {"id":"ses_ghost2","directory":"/also/not","time":{"created":8888}}
]
JSON
    }
    export -f curl

    run _orch_send_resolve_session "$dir" "http://localhost:1"
    [ "$status" -eq 0 ]
    [ "$output" = "ses_created" ]

    unset -f curl
}

@test "resolve_session: POSTs a new session as last resort" {
    local dir="$BATS_TEST_TMPDIR/orch5"
    mkdir -p "$dir"

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_new"}'
            return 0
        fi
        echo '[]'
    }
    export -f curl

    run _orch_send_resolve_session "$dir" "http://localhost:1"
    [ "$status" -eq 0 ]
    [ "$output" = "ses_new" ]

    unset -f curl
}

@test "resolve_session: returns error when all paths fail" {
    local dir="$BATS_TEST_TMPDIR/orch6"
    mkdir -p "$dir"

    curl() { return 7; }
    export -f curl

    run _orch_send_resolve_session "$dir" "http://localhost:1"
    [ "$status" -eq 1 ]

    unset -f curl
}

# --- async mode integration ---

@test "send --async: returns immediately and creates log file" {
    local name="asyncorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    echo "4999" > "$dir/port"
    echo "ses_async" > "$dir/session-id"

    # Stub curl so every HTTP call returns something benign.
    curl() {
        if [[ "$*" == *"/message"* && "$*" != *"-X POST"* ]]; then
            echo '[]'
            return 0
        fi
        if [[ "$*" == *"-X POST"* ]]; then
            # Simulate a fast send
            sleep 0
            return 0
        fi
        echo '[]'
    }
    export -f curl

    local start end elapsed
    start=$(date +%s)
    run _orch_send --async "$name" "hello"
    end=$(date +%s)
    elapsed=$((end - start))

    [ "$status" -eq 0 ]
    [[ "$output" == *"Sent async to $name"* ]]
    [[ "$output" == *"Log:"* ]]
    # Must return promptly (well under the 600s poll budget).
    [ "$elapsed" -lt 10 ]
    [ -d "$dir/logs" ]
    ls "$dir/logs"/send-"$name"-*.log >/dev/null 2>&1

    unset -f curl
    # Kill any backgrounded pollers so teardown is clean.
    pkill -f _orch_send_async_poll 2>/dev/null || true
}

@test "send: sync mode unchanged (returns response text)" {
    local name="syncorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    echo "4998" > "$dir/port"
    echo "ses_sync" > "$dir/session-id"

    curl() {
        if [[ "$*" == *"/message"* && "$*" != *"-X POST"* ]]; then
            echo '[]'
            return 0
        fi
        if [[ "$*" == *"-X POST"*"/message"* ]]; then
            echo '{"parts":[{"type":"text","text":"sync-reply"}]}'
            return 0
        fi
        echo '[]'
    }
    export -f curl

    run _orch_send "$name" "ping"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sync-reply"* ]]

    unset -f curl
}

# --- handler dispatch ---

@test "dispatch: send --async is passed through to _orch_send" {
    # coda-handler.sh already delegates via "$@", so calling _coda_orch
    # with --async must reach argument parsing in _orch_send.
    if [ -f "$PLUGIN_DIR/coda-handler.sh" ]; then
        source "$PLUGIN_DIR/coda-handler.sh"
    else
        skip "coda-handler.sh not present"
    fi

    run _coda_orch send --async
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}
