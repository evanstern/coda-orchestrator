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

    # ss stub: reports no listeners so the hook's inline port-scan always
    # picks the first candidate port. Keeps tests deterministic regardless
    # of what's actually listening on the host.
    cat > "$STUB_BIN/ss" <<'SS'
#!/usr/bin/env bash
exit 0
SS
    chmod +x "$STUB_BIN/ss"

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

# --- New-style hook: hooks/post-session-create/60-feature-spawn-setup ---
#
# These tests exercise the standalone hook script that receives feature
# context via CODA_* env vars (from coda CLI PR #44). The hook does NOT
# create the tmux window -- that's already done by _coda_attach when
# CODA_ORCH_WINDOW_MODE=1 (coda CLI PR #40). The hook only wires up the
# opencode serve + brief + auto-trigger.

HOOK_SCRIPT="$BATS_TEST_DIRNAME/../hooks/post-session-create/60-feature-spawn-setup"

@test "hook: exits 0 silently when CODA_FEATURE_BRANCH is unset" {
    unset CODA_FEATURE_BRANCH
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"

    run bash "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$WORKTREE_DIR/port" ]
}

@test "hook: exits 0 silently when CODA_ORCH_NAME is unset" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    unset CODA_ORCH_NAME
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"

    run bash "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$WORKTREE_DIR/port" ]
}

@test "hook: moves staged-brief.md to IMPLEMENT.md when present" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_PROJECT_NAME="$PROJECT_NAME"

    echo "BRIEF CONTENT" > "$CODA_ORCH_DIR/$ORCH_NAME/staged-brief.md"

    run bash "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]

    [ ! -f "$CODA_ORCH_DIR/$ORCH_NAME/staged-brief.md" ]
    [ -f "$WORKTREE_DIR/IMPLEMENT.md" ]
    run cat "$WORKTREE_DIR/IMPLEMENT.md"
    [ "$output" = "BRIEF CONTENT" ]
}

@test "hook: prepends AGENTS.md with feature-session header" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_PROJECT_NAME="$PROJECT_NAME"

    printf 'ORIGINAL AGENTS CONTENT\n' > "$WORKTREE_DIR/AGENTS.md"

    run bash "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]

    [ -f "$WORKTREE_DIR/AGENTS.md" ]
    run cat "$WORKTREE_DIR/AGENTS.md"
    [[ "$output" == *"# FEATURE SESSION"* ]]
    [[ "$output" == *"You are a feature implementation agent"* ]]
    [[ "$output" == *"ORIGINAL AGENTS CONTENT"* ]]
}

@test "hook: skips brief injection when staged-brief.md does not exist" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_PROJECT_NAME="$PROJECT_NAME"

    [ ! -f "$CODA_ORCH_DIR/$ORCH_NAME/staged-brief.md" ]

    run bash "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]

    [ ! -f "$WORKTREE_DIR/IMPLEMENT.md" ]
}

@test "hook: writes port file in worktree dir" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_PROJECT_NAME="$PROJECT_NAME"

    run bash "$HOOK_SCRIPT"
    [ "$status" -eq 0 ]

    [ -f "$WORKTREE_DIR/port" ]
    run cat "$WORKTREE_DIR/port"
    # Port should be a number in the configured range.
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -ge "$ORCH_PORT_BASE" ]
    [ "$output" -le "$((ORCH_PORT_BASE + ORCH_PORT_RANGE))" ]
}
