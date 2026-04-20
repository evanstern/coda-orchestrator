#!/usr/bin/env bats
#
# feature-teardown.bats -- tests for pre-feature-teardown delivery.
#
# Covers:
#   - lib/teardown.sh:_orch_write_teardown_report
#   - hooks/pre-feature-teardown/60-feature-teardown-report
#   - spawn-time .orch-meta metadata written by
#     hooks/post-session-create/60-feature-spawn-setup

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    export ORCH_PORT_BASE=4310
    export ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$CODA_ORCH_DIR" "$HOME"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUB_BIN"

    cat > "$STUB_BIN/curl" <<'CURL'
#!/usr/bin/env bash
exit 0
CURL
    chmod +x "$STUB_BIN/curl"

    cat > "$STUB_BIN/opencode" <<'OC'
#!/usr/bin/env bash
exit 0
OC
    chmod +x "$STUB_BIN/opencode"

    cat > "$STUB_BIN/ss" <<'SS'
#!/usr/bin/env bash
exit 0
SS
    chmod +x "$STUB_BIN/ss"

    export PATH="$STUB_BIN:$PATH"

    source "$PLUGIN_DIR/lib/teardown.sh"

    ORCH_NAME="teardownorch"
    BRANCH="87-feature-teardown"
    mkdir -p "$CODA_ORCH_DIR/$ORCH_NAME"
    ORCH_CFG_DIR="$CODA_ORCH_DIR/$ORCH_NAME"
    WORKTREE_DIR="$BATS_TEST_TMPDIR/worktree"
    mkdir -p "$WORKTREE_DIR"
}

teardown() {
    rm -rf "$CODA_ORCH_DIR" "$HOME" "$BATS_TEST_TMPDIR/bin"
}

# --- lib/teardown.sh:_orch_write_teardown_report ---

@test "teardown helper: writes inbox/<branch>.md with required fields" {
    run _orch_write_teardown_report \
        "$ORCH_CFG_DIR" "$BRANCH" "$WORKTREE_DIR" "87" "coda-orchestrator"
    [ "$status" -eq 0 ]

    local out="$ORCH_CFG_DIR/inbox/${BRANCH}.md"
    [ -f "$out" ]

    run cat "$out"
    [[ "$output" == *"# Feature teardown: $BRANCH"* ]]
    [[ "$output" == *"- card: 87"* ]]
    [[ "$output" == *"- branch: $BRANCH"* ]]
    [[ "$output" == *"- project: coda-orchestrator"* ]]
    [[ "$output" == *"- pr: none"* ]]
    [[ "$output" == *"- source: auto"* ]]
    [[ "$output" == *"status: unknown"* ]]
}

@test "teardown helper: uses TEARDOWN.md body when present" {
    cat > "$WORKTREE_DIR/TEARDOWN.md" <<'SELF'
status: completed
pr: none

## What got done
- implemented teardown hook

## What did not get done
- None

## Decisions made
- wrote markdown, not json

## Issues / surprises / workarounds
- None

## Notes for the orchestrator
- please review
SELF

    run _orch_write_teardown_report \
        "$ORCH_CFG_DIR" "$BRANCH" "$WORKTREE_DIR" "87" "coda-orchestrator"
    [ "$status" -eq 0 ]

    run cat "$ORCH_CFG_DIR/inbox/${BRANCH}.md"
    [[ "$output" == *"- source: self-report"* ]]
    [[ "$output" == *"status: completed"* ]]
    [[ "$output" == *"implemented teardown hook"* ]]
    [[ "$output" == *"wrote markdown, not json"* ]]
}

@test "teardown helper: preserves previous report with .prev suffix" {
    _orch_write_teardown_report \
        "$ORCH_CFG_DIR" "$BRANCH" "$WORKTREE_DIR" "87" "coda-orchestrator" \
        >/dev/null

    echo "marker-first" > "$ORCH_CFG_DIR/inbox/${BRANCH}.md"

    _orch_write_teardown_report \
        "$ORCH_CFG_DIR" "$BRANCH" "$WORKTREE_DIR" "87" "coda-orchestrator" \
        >/dev/null

    [ -f "$ORCH_CFG_DIR/inbox/${BRANCH}.md.prev" ]
    run cat "$ORCH_CFG_DIR/inbox/${BRANCH}.md.prev"
    [ "$output" = "marker-first" ]
}

@test "teardown helper: sanitizes slashes in branch name for file path" {
    local b="spawn/42-thing"
    run _orch_write_teardown_report \
        "$ORCH_CFG_DIR" "$b" "$WORKTREE_DIR" "" ""
    [ "$status" -eq 0 ]

    [ -f "$ORCH_CFG_DIR/inbox/spawn-42-thing.md" ]
    [ ! -d "$ORCH_CFG_DIR/inbox/spawn" ]
}

@test "teardown helper: fails when orch_dir missing" {
    run _orch_write_teardown_report "" "$BRANCH" "$WORKTREE_DIR" "" ""
    [ "$status" -ne 0 ]

    run _orch_write_teardown_report "/nonexistent/xyz" "$BRANCH" "$WORKTREE_DIR" "" ""
    [ "$status" -ne 0 ]
}

@test "teardown helper: does not append to inbox.md" {
    : > "$ORCH_CFG_DIR/inbox.md"
    local before
    before=$(wc -c < "$ORCH_CFG_DIR/inbox.md")

    _orch_write_teardown_report \
        "$ORCH_CFG_DIR" "$BRANCH" "$WORKTREE_DIR" "" "" >/dev/null

    local after
    after=$(wc -c < "$ORCH_CFG_DIR/inbox.md")
    [ "$before" = "$after" ]
}

# --- spawn hook writes .orch-meta ---

SPAWN_HOOK="$BATS_TEST_DIRNAME/../hooks/post-session-create/60-feature-spawn-setup"

@test "spawn hook: writes .orch-meta with orchestrator context" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_PROJECT_NAME="coda-orchestrator"

    run bash "$SPAWN_HOOK"
    [ "$status" -eq 0 ]

    [ -f "$WORKTREE_DIR/.orch-meta" ]

    (
        set +u
        source "$WORKTREE_DIR/.orch-meta"
        [ "$CODA_ORCH_NAME" = "$ORCH_NAME" ]
        [ "$CODA_ORCH_DIR" = "$ORCH_CFG_DIR" ]
        [ "$CODA_FEATURE_BRANCH" = "$BRANCH" ]
        [ "$CODA_FEATURE_CARD" = "87" ]
        [ "$CODA_WORKTREE_DIR" = "$WORKTREE_DIR" ]
    )
}

@test "spawn hook: AGENTS.md header documents TEARDOWN.md contract" {
    export CODA_FEATURE_BRANCH="$BRANCH"
    export CODA_ORCH_NAME="$ORCH_NAME"
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_PROJECT_NAME="coda-orchestrator"

    run bash "$SPAWN_HOOK"
    [ "$status" -eq 0 ]

    run cat "$WORKTREE_DIR/AGENTS.md"
    [[ "$output" == *"TEARDOWN.md"* ]]
    [[ "$output" == *"Teardown report (required)"* ]]
}

# --- pre-feature-teardown hook ---

TEARDOWN_HOOK="$BATS_TEST_DIRNAME/../hooks/pre-feature-teardown/60-feature-teardown-report"

@test "teardown hook: exits 0 silently when CODA_WORKTREE_DIR unset" {
    unset CODA_WORKTREE_DIR CODA_FEATURE_BRANCH CODA_ORCH_NAME

    run bash "$TEARDOWN_HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "teardown hook: exits 0 silently when worktree has no .orch-meta" {
    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_FEATURE_BRANCH="$BRANCH"
    unset CODA_ORCH_NAME

    run bash "$TEARDOWN_HOOK"
    [ "$status" -eq 0 ]

    [ ! -d "$ORCH_CFG_DIR/inbox" ]
}

@test "teardown hook: reads .orch-meta and writes inbox/<branch>.md" {
    cat > "$WORKTREE_DIR/.orch-meta" <<META
CODA_ORCH_NAME=$ORCH_NAME
CODA_ORCH_DIR=$ORCH_CFG_DIR
CODA_FEATURE_BRANCH=$BRANCH
CODA_FEATURE_CARD=87
CODA_PROJECT_NAME=coda-orchestrator
CODA_WORKTREE_DIR=$WORKTREE_DIR
META

    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_FEATURE_BRANCH="$BRANCH"

    run bash "$TEARDOWN_HOOK"
    [ "$status" -eq 0 ]

    [ -f "$ORCH_CFG_DIR/inbox/${BRANCH}.md" ]
    run cat "$ORCH_CFG_DIR/inbox/${BRANCH}.md"
    [[ "$output" == *"- card: 87"* ]]
    [[ "$output" == *"- project: coda-orchestrator"* ]]
}

@test "teardown hook: delivers self-report when TEARDOWN.md present" {
    cat > "$WORKTREE_DIR/.orch-meta" <<META
CODA_ORCH_NAME=$ORCH_NAME
CODA_ORCH_DIR=$ORCH_CFG_DIR
CODA_FEATURE_BRANCH=$BRANCH
CODA_FEATURE_CARD=87
CODA_PROJECT_NAME=coda-orchestrator
CODA_WORKTREE_DIR=$WORKTREE_DIR
META

    cat > "$WORKTREE_DIR/TEARDOWN.md" <<'SELF'
status: partial
pr: none

## What got done
- unique-token-selfreport

## What did not get done
- nothing

## Decisions made
- None

## Issues / surprises / workarounds
- None

## Notes for the orchestrator
- None
SELF

    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_FEATURE_BRANCH="$BRANCH"

    run bash "$TEARDOWN_HOOK"
    [ "$status" -eq 0 ]

    run cat "$ORCH_CFG_DIR/inbox/${BRANCH}.md"
    [[ "$output" == *"- source: self-report"* ]]
    [[ "$output" == *"status: partial"* ]]
    [[ "$output" == *"unique-token-selfreport"* ]]
}

@test "teardown hook: does not touch inbox.md" {
    cat > "$WORKTREE_DIR/.orch-meta" <<META
CODA_ORCH_NAME=$ORCH_NAME
CODA_ORCH_DIR=$ORCH_CFG_DIR
CODA_FEATURE_BRANCH=$BRANCH
CODA_FEATURE_CARD=
CODA_PROJECT_NAME=
CODA_WORKTREE_DIR=$WORKTREE_DIR
META

    echo "preexisting inbox content" > "$ORCH_CFG_DIR/inbox.md"
    local sha_before
    sha_before=$(sha1sum < "$ORCH_CFG_DIR/inbox.md")

    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_FEATURE_BRANCH="$BRANCH"

    run bash "$TEARDOWN_HOOK"
    [ "$status" -eq 0 ]

    local sha_after
    sha_after=$(sha1sum < "$ORCH_CFG_DIR/inbox.md")
    [ "$sha_before" = "$sha_after" ]
}

@test "teardown hook: exits 0 when orchestrator dir no longer exists" {
    cat > "$WORKTREE_DIR/.orch-meta" <<META
CODA_ORCH_NAME=gone
CODA_ORCH_DIR=$CODA_ORCH_DIR/gone
CODA_FEATURE_BRANCH=$BRANCH
CODA_FEATURE_CARD=
CODA_PROJECT_NAME=
CODA_WORKTREE_DIR=$WORKTREE_DIR
META

    export CODA_WORKTREE_DIR="$WORKTREE_DIR"
    export CODA_FEATURE_BRANCH="$BRANCH"

    run bash "$TEARDOWN_HOOK"
    [ "$status" -eq 0 ]
}
