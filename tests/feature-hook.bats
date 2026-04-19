#!/usr/bin/env bats
#
# feature-hook.bats -- tests for lib/feature-hook.sh
#
# Covers the dual-path behavior gated on CODA_ORCH_WINDOW_MODE:
#   - Legacy mode (unset): byte-identical to the pre-#91 behavior; creates
#     a top-level tmux session named coda-<project>--<branch>.
#   - Window mode (=1): creates a tmux window inside the orchestrator's
#     session via _layout_spawn; auto-starts the orch session if missing.

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    export CODA_ORCH_PORT_BASE=4300
    export CODA_ORCH_PORT_RANGE=10
    export ORCH_PORT_BASE=4300
    export ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$CODA_ORCH_DIR" "$HOME"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    # Isolate PATH so stubs below take precedence over any real binaries
    # (opencode, curl) that would otherwise be invoked by the hook.
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"

    # curl stub: always reports the serve endpoint is healthy.
    cat > "$STUB_BIN/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL
    chmod +x "$STUB_BIN/curl"

    # opencode stub: swallows all invocations (serve, run --attach).
    cat > "$STUB_BIN/opencode" <<'OC'
#!/usr/bin/env bash
exit 0
OC
    chmod +x "$STUB_BIN/opencode"

    export PATH="$STUB_BIN:$PATH"

    source "$PLUGIN_DIR/lib/feature-hook.sh"

    _orch_find_free_port() {
        echo "$ORCH_PORT_BASE"
    }

    # Orchestrator dir + a dummy worktree.
    ORCH_NAME="testorch"
    BRANCH="42-fix-thing"
    PROJECT_NAME="coda-orchestrator"
    mkdir -p "$CODA_ORCH_DIR/$ORCH_NAME"
    WORKTREE_DIR="$BATS_TEST_TMPDIR/worktree"
    mkdir -p "$WORKTREE_DIR"
    PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$PROJECT_ROOT"
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null \
        | grep '^coda-test-' | while read -r s; do
            tmux kill-session -t "$s" 2>/dev/null || true
        done
    rm -rf "$CODA_ORCH_DIR" "$HOME" "$BATS_TEST_TMPDIR/bin"
}

# --- Legacy mode (CODA_ORCH_WINDOW_MODE unset) ---

@test "legacy mode: creates top-level tmux session named coda-<project>--<branch>" {
    unset CODA_ORCH_WINDOW_MODE

    run _coda_feature_orch_hook "$ORCH_NAME" "$BRANCH" "$PROJECT_NAME" \
        "$WORKTREE_DIR" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]

    local expected_session="${SESSION_PREFIX}${PROJECT_NAME}--${BRANCH}"
    run tmux has-session -t "$expected_session"
    [ "$status" -eq 0 ]

    tmux kill-session -t "$expected_session" 2>/dev/null || true
}

@test "legacy mode: does not create a window inside the orch session" {
    unset CODA_ORCH_WINDOW_MODE

    local orch_session="${SESSION_PREFIX}orch--${ORCH_NAME}"
    tmux new-session -d -s "$orch_session" "sleep 300"

    run _coda_feature_orch_hook "$ORCH_NAME" "$BRANCH" "$PROJECT_NAME" \
        "$WORKTREE_DIR" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]

    run tmux list-windows -t "$orch_session" -F '#{window_name}'
    [ "$status" -eq 0 ]
    [[ "$output" != *"$BRANCH"* ]]

    local feature_session="${SESSION_PREFIX}${PROJECT_NAME}--${BRANCH}"
    run tmux has-session -t "$feature_session"
    [ "$status" -eq 0 ]

    tmux kill-session -t "$orch_session" 2>/dev/null || true
    tmux kill-session -t "$feature_session" 2>/dev/null || true
}

# --- Window mode (CODA_ORCH_WINDOW_MODE=1) ---

@test "window mode: creates window in orch session, not a new top-level session" {
    export CODA_ORCH_WINDOW_MODE=1

    local orch_session="${SESSION_PREFIX}orch--${ORCH_NAME}"
    tmux new-session -d -s "$orch_session" "sleep 300"

    _layout_spawn() {
        local session="$1" dir="$2"
        local target="${CODA_LAYOUT_TARGET:-$session}"
        local window_flag=()
        case "$target" in
            *:*) window_flag=(-n "${target##*:}") ;;
        esac
        tmux new-window -d -t "${target%%:*}" "${window_flag[@]}" -c "$dir" "sleep 300"
    }

    run _coda_feature_orch_hook "$ORCH_NAME" "$BRANCH" "$PROJECT_NAME" \
        "$WORKTREE_DIR" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]

    # Window named after the branch exists in the orch session.
    run tmux list-windows -t "$orch_session" -F '#{window_name}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"$BRANCH"* ]]

    # No top-level feature session was created.
    local feature_session="${SESSION_PREFIX}${PROJECT_NAME}--${BRANCH}"
    run tmux has-session -t "$feature_session"
    [ "$status" -ne 0 ]

    tmux kill-session -t "$orch_session" 2>/dev/null || true
}

@test "window mode: auto-starts orch session when not running" {
    export CODA_ORCH_WINDOW_MODE=1

    local orch_session="${SESSION_PREFIX}orch--${ORCH_NAME}"
    run tmux has-session -t "$orch_session"
    [ "$status" -ne 0 ]

    _orch_start() {
        local name="$1"
        tmux new-session -d -s "${SESSION_PREFIX}orch--${name}" "sleep 300"
    }

    _layout_spawn() {
        local session="$1" dir="$2"
        local target="${CODA_LAYOUT_TARGET:-$session}"
        local window_flag=()
        case "$target" in
            *:*) window_flag=(-n "${target##*:}") ;;
        esac
        tmux new-window -d -t "${target%%:*}" "${window_flag[@]}" -c "$dir" "sleep 300"
    }

    run _coda_feature_orch_hook "$ORCH_NAME" "$BRANCH" "$PROJECT_NAME" \
        "$WORKTREE_DIR" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]

    run tmux has-session -t "$orch_session"
    [ "$status" -eq 0 ]

    run tmux list-windows -t "$orch_session" -F '#{window_name}'
    [[ "$output" == *"$BRANCH"* ]]

    tmux kill-session -t "$orch_session" 2>/dev/null || true
}

@test "window mode: sets CODA_LAYOUT_TARGET to <orch-session>:<branch>" {
    export CODA_ORCH_WINDOW_MODE=1

    local orch_session="${SESSION_PREFIX}orch--${ORCH_NAME}"
    tmux new-session -d -s "$orch_session" "sleep 300"

    local target_capture="$BATS_TEST_TMPDIR/layout-target"
    _layout_spawn() {
        echo "$CODA_LAYOUT_TARGET" > "$target_capture"
        local target="${CODA_LAYOUT_TARGET:-$1}"
        local window_flag=()
        case "$target" in
            *:*) window_flag=(-n "${target##*:}") ;;
        esac
        tmux new-window -d -t "${target%%:*}" "${window_flag[@]}" -c "$2" "sleep 300"
    }

    run _coda_feature_orch_hook "$ORCH_NAME" "$BRANCH" "$PROJECT_NAME" \
        "$WORKTREE_DIR" "$PROJECT_ROOT"
    [ "$status" -eq 0 ]

    [ -f "$target_capture" ]
    run cat "$target_capture"
    [ "$output" = "${orch_session}:${BRANCH}" ]

    tmux kill-session -t "$orch_session" 2>/dev/null || true
}

@test "window mode: fails cleanly when orch session cannot be started" {
    export CODA_ORCH_WINDOW_MODE=1

    _orch_start() { return 1; }

    run _coda_feature_orch_hook "$ORCH_NAME" "$BRANCH" "$PROJECT_NAME" \
        "$WORKTREE_DIR" "$PROJECT_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Orchestrator session not running"* ]]

    [ ! -f "$WORKTREE_DIR/port" ]
}
