#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    export CODA_ORCH_PORT_BASE=4290
    export CODA_ORCH_PORT_RANGE=10
    export ORCH_PORT_BASE=4290
    export ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$CODA_ORCH_DIR" "$HOME"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    if [ -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        source "$PLUGIN_DIR/lib/lifecycle.sh"
    fi
    source "$PLUGIN_DIR/lib/send.sh"
    if [ -f "$PLUGIN_DIR/lib/inbox.sh" ]; then
        source "$PLUGIN_DIR/lib/inbox.sh"
    fi

    if ! declare -f _orch_dir &>/dev/null; then
        _orch_dir() { echo "$ORCH_BASE_DIR/$1"; }
    fi
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep '^coda-test-' | while read -r s; do
            tmux kill-session -t "$s" 2>/dev/null || true
        done
    rm -rf "$CODA_ORCH_DIR" "$HOME"
}

# --- _orch_inbox_append ---

@test "inbox_append: writes entry bracketed by --- markers" {
    local dir="$BATS_TEST_TMPDIR/inbox1"
    mkdir -p "$dir"

    _orch_inbox_append "$dir" "alice" "hello there"

    [ -f "$dir/inbox.md" ]
    run grep -c '^---$' "$dir/inbox.md"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]

    run grep -F "from: alice" "$dir/inbox.md"
    [ "$status" -eq 0 ]
    run grep -F "hello there" "$dir/inbox.md"
    [ "$status" -eq 0 ]
}

@test "inbox_append: appends multiple entries" {
    local dir="$BATS_TEST_TMPDIR/inbox2"
    mkdir -p "$dir"

    _orch_inbox_append "$dir" "alice" "first"
    _orch_inbox_append "$dir" "bob" "second"

    run grep -c '^---$' "$dir/inbox.md"
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "inbox_append: no-op when dir missing" {
    run _orch_inbox_append "" "alice" "hello"
    [ "$status" -eq 0 ]

    run _orch_inbox_append "/nonexistent/path/xyz" "alice" "hello"
    [ "$status" -eq 0 ]
    [ ! -f "/nonexistent/path/xyz/inbox.md" ]
}

# --- inbox-status.sh ---

@test "inbox-status: emits badge for entries" {
    local dir="$BATS_TEST_TMPDIR/inbox3"
    mkdir -p "$dir"
    _orch_inbox_append "$dir" "alice" "one"
    _orch_inbox_append "$dir" "bob" "two"

    run "$PLUGIN_DIR/lib/inbox-status.sh" "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[2 msg(s)]"* ]]
}

@test "inbox-status: emits nothing for empty file" {
    local dir="$BATS_TEST_TMPDIR/inbox4"
    mkdir -p "$dir"
    : > "$dir/inbox.md"

    run "$PLUGIN_DIR/lib/inbox-status.sh" "$dir"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "inbox-status: emits nothing when file has content but no --- markers" {
    local dir="$BATS_TEST_TMPDIR/inbox4b"
    mkdir -p "$dir"
    printf 'some prose with no markers\n' > "$dir/inbox.md"

    run "$PLUGIN_DIR/lib/inbox-status.sh" "$dir"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "inbox-status: emits nothing for missing file" {
    local dir="$BATS_TEST_TMPDIR/inbox5"
    mkdir -p "$dir"

    run "$PLUGIN_DIR/lib/inbox-status.sh" "$dir"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "inbox-status: script is executable" {
    [ -x "$PLUGIN_DIR/lib/inbox-status.sh" ]
}

# --- _orch_start patches opencode.json ---

@test "start: adds inbox.md to existing opencode.json instructions" {
    if [ ! -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        skip "lifecycle.sh not installed"
    fi

    local name="patchorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    printf '{"instructions":["SOUL.md","MEMORY.md","PROJECT.md"]}\n' > "$dir/opencode.json"

    tmux() {
        case "$1" in
            has-session)     return 1 ;;
            new-session)     return 0 ;;
            set-environment) return 0 ;;
            set-option)      return 0 ;;
            *)               command tmux "$@" ;;
        esac
    }
    export -f tmux

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_patch"}'
            return 0
        fi
        echo '[]'
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]

    run jq -e '.instructions | index("inbox.md")' "$dir/opencode.json"
    [ "$status" -eq 0 ]

    unset -f tmux curl
}

@test "start: does not duplicate inbox.md if already present" {
    if [ ! -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        skip "lifecycle.sh not installed"
    fi

    local name="dedupeorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    printf '{"instructions":["SOUL.md","inbox.md"]}\n' > "$dir/opencode.json"

    tmux() {
        case "$1" in
            has-session)     return 1 ;;
            new-session)     return 0 ;;
            set-environment) return 0 ;;
            set-option)      return 0 ;;
            *)               command tmux "$@" ;;
        esac
    }
    export -f tmux

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_dedup"}'
            return 0
        fi
        echo '[]'
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]

    run jq '[.instructions[] | select(. == "inbox.md")] | length' "$dir/opencode.json"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    unset -f tmux curl
}

@test "start: leaves opencode.json intact when instructions is not an array" {
    if [ ! -f "$PLUGIN_DIR/lib/lifecycle.sh" ]; then
        skip "lifecycle.sh not installed"
    fi

    local name="nonarrayorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    local original='{"instructions":"SOUL.md","other":42}'
    printf '%s\n' "$original" > "$dir/opencode.json"

    tmux() {
        case "$1" in
            has-session)     return 1 ;;
            new-session)     return 0 ;;
            set-environment) return 0 ;;
            set-option)      return 0 ;;
            *)               command tmux "$@" ;;
        esac
    }
    export -f tmux

    curl() {
        if [[ "$*" == *"-X POST"* ]]; then
            echo '{"id":"ses_noarr"}'
            return 0
        fi
        echo '[]'
    }
    export -f curl

    run _orch_start "$name"
    [ "$status" -eq 0 ]

    [ -s "$dir/opencode.json" ]
    run jq -r '.other' "$dir/opencode.json"
    [ "$output" = "42" ]
    run jq -r '.instructions' "$dir/opencode.json"
    [ "$output" = "SOUL.md" ]

    unset -f tmux curl
}

# --- _orch_inbox subcommand ---

@test "inbox cmd: prints 'inbox is empty' for empty file" {
    if ! declare -f _orch_inbox &>/dev/null; then
        skip "inbox.sh not loaded"
    fi

    local name="emptyinboxorch"
    mkdir -p "$ORCH_BASE_DIR/$name"

    run _orch_inbox "$name"
    [ "$status" -eq 0 ]
    [[ "$output" == *"inbox is empty"* ]]
}

@test "inbox cmd: cats inbox contents when present" {
    if ! declare -f _orch_inbox &>/dev/null; then
        skip "inbox.sh not loaded"
    fi

    local name="filledinboxorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    _orch_inbox_append "$dir" "alice" "unique-token-xyz"

    run _orch_inbox "$name"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unique-token-xyz"* ]]
}

@test "inbox cmd: clear truncates file" {
    if ! declare -f _orch_inbox &>/dev/null; then
        skip "inbox.sh not loaded"
    fi

    local name="clearorch"
    local dir="$ORCH_BASE_DIR/$name"
    mkdir -p "$dir"
    _orch_inbox_append "$dir" "alice" "will be wiped"

    run _orch_inbox "$name" clear
    [ "$status" -eq 0 ]
    [ ! -s "$dir/inbox.md" ]
}

@test "inbox cmd: errors when orchestrator not found" {
    if ! declare -f _orch_inbox &>/dev/null; then
        skip "inbox.sh not loaded"
    fi

    run _orch_inbox "nonexistent-orch"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}
