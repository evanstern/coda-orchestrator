#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4290
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export PROJECTS_DIR="$BATS_TEST_TMPDIR/projects"
    export HOME="$BATS_TEST_TMPDIR/home"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    if [ -f "$PLUGIN_DIR/coda-handler.sh" ]; then
        source "$PLUGIN_DIR/coda-handler.sh"
    else
        # Minimal stand-in when plugin handler isn't installed (e.g. CI).
        for mod in lifecycle observe spawn; do
            [ -f "$PLUGIN_DIR/lib/${mod}.sh" ] && source "$PLUGIN_DIR/lib/${mod}.sh"
        done
        # status.sh is the unit under test; load it directly.
        source "$PLUGIN_DIR/lib/status.sh"
    fi

    # Stub _orch_dir / _orch_session_name / _orch_is_running if missing
    # so the unit tests don't depend on the gitignored lifecycle.sh.
    if ! declare -f _orch_dir &>/dev/null; then
        _orch_dir() { echo "$ORCH_BASE_DIR/$1"; }
    fi
    if ! declare -f _orch_session_name &>/dev/null; then
        _orch_session_name() { echo "${SESSION_PREFIX}orch--$1"; }
    fi
    if ! declare -f _orch_is_running &>/dev/null; then
        _orch_is_running() { return 1; }
    fi

    # Force-ensure the tree-view _orch_status is loaded last, overriding any
    # legacy version pulled in by the handler.
    source "$PLUGIN_DIR/lib/status.sh"
}

teardown() {
    rm -rf "$CODA_ORCH_DIR" "$PROJECTS_DIR" "$HOME"
}

# --- session parsing ---

@test "parse_session: extracts project and branch" {
    run _orch_status_parse_session "coda-test-myproj--feature-x"
    [ "$status" -eq 0 ]
    [ "$output" = $'myproj\tfeature-x'  ]
}

@test "parse_session: handles project names containing hyphens" {
    run _orch_status_parse_session "coda-test-coda-orchestrator--51-orch-status-tree-view"
    [ "$status" -eq 0 ]
    [ "$output" = $'coda-orchestrator\t51-orch-status-tree-view' ]
}

@test "parse_session: returns empty for malformed names" {
    run _orch_status_parse_session "not-a-coda-session"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parse_session: returns empty when separator missing" {
    run _orch_status_parse_session "coda-test-justaproject"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- scope matching ---

@test "session_in_scope: matches watch glob" {
    run _orch_status_session_in_scope "coda-test-foo--bar" "coda-test-*" ""
    [ "$status" -eq 0 ]
}

@test "session_in_scope: respects ignore patterns" {
    run _orch_status_session_in_scope \
        "coda-test-orch--coda-orchestrator" \
        "coda-test-*" \
        $'coda-test-orch--*\ncoda-test-watcher'
    [ "$status" -eq 1 ]
}

@test "session_in_scope: rejects sessions outside watch" {
    run _orch_status_session_in_scope "other-thing" "coda-test-*" ""
    [ "$status" -eq 1 ]
}

# --- focus card listing graceful degradation ---

@test "focus_cards: returns empty when focus binary unavailable" {
    PATH="/usr/bin:/bin" run _orch_status_focus_cards "anything"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "focus_cards: returns empty for blank project" {
    run _orch_status_focus_cards ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- pr lookup graceful degradation ---

@test "pr_lookup: empty when no project dir resolvable" {
    PATH="/usr/bin:/bin" run _orch_status_pr_lookup "no-such-project" "no-branch"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- main rendering ---

@test "status: reports missing orchestrator base dir" {
    rm -rf "$ORCH_BASE_DIR"
    run _orch_status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No orchestrators found"* ]]
}

@test "status: errors on unknown orchestrator name" {
    mkdir -p "$ORCH_BASE_DIR"
    run _orch_status nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "status: renders header and 'no scope defined' for orch with no scope" {
    mkdir -p "$ORCH_BASE_DIR/empty"
    run _orch_status empty
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty (stopped)"* ]]
    [[ "$output" == *"(no scope defined)"* ]]
}

@test "status: shows tree with child sessions matching scope" {
    mkdir -p "$ORCH_BASE_DIR/myorch"
    cat > "$ORCH_BASE_DIR/myorch/scope.json" <<'EOF'
{
  "watch": ["coda-test-*"],
  "ignore": ["coda-test-orch--*"]
}
EOF
    # Override tmux + helpers by using a stub sessions list.
    _orch_status_render_one() {
        local name="$1" sessions="$2"
        printf '%s (stopped)\n' "$name"
        local sess project_branch
        local children=()
        while IFS= read -r sess; do
            [ -z "$sess" ] && continue
            children+=("$sess")
        done <<< "$sessions"
        printf '  |- %s\n' "${children[@]}"
    }
    run _orch_status_render_one myorch $'coda-test-foo--branch1\ncoda-test-foo--branch2'
    [ "$status" -eq 0 ]
    [[ "$output" == *"myorch (stopped)"* ]]
    [[ "$output" == *"branch1"* ]]
    [[ "$output" == *"branch2"* ]]
}

@test "status: end-to-end with one orch and one matching session, no gh/focus" {
    mkdir -p "$ORCH_BASE_DIR/solo"
    cat > "$ORCH_BASE_DIR/solo/scope.json" <<'EOF'
{
  "watch": ["coda-test-fakeproj--*"],
  "ignore": []
}
EOF
    # Stub tmux: pretend one matching session exists.
    tmux() {
        if [ "$1" = "list-sessions" ]; then
            echo "coda-test-fakeproj--my-feature"
            return 0
        fi
        command tmux "$@"
    }
    export -f tmux

    PATH="/usr/bin:/bin" run _orch_status solo
    unset -f tmux
    [ "$status" -eq 0 ]
    [[ "$output" == *"solo (stopped)"* ]]
    [[ "$output" == *"my-feature"* ]]
    [[ "$output" == *"+- fakeproj/my-feature"* || "$output" == *"|- fakeproj/my-feature"* ]]
}

@test "status: omits project prefix when session project matches orch primary project" {
    mkdir -p "$ORCH_BASE_DIR/matched"
    cat > "$ORCH_BASE_DIR/matched/scope.json" <<'EOF'
{
  "watch": ["coda-test-myproj--*"],
  "ignore": [],
  "project": "myproj"
}
EOF
    tmux() {
        if [ "$1" = "list-sessions" ]; then
            echo "coda-test-myproj--my-feature"
            return 0
        fi
        command tmux "$@"
    }
    export -f tmux

    PATH="/usr/bin:/bin" run _orch_status matched
    unset -f tmux
    [ "$status" -eq 0 ]
    [[ "$output" == *"+- my-feature"* || "$output" == *"|- my-feature"* ]]
    [[ "$output" != *"myproj/my-feature"* ]]
}
