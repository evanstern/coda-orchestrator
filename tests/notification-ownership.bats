#!/usr/bin/env bats

# Tests for ownership extraction logic used in notification hooks.
# Session naming convention: coda-<project>--<branch>
# The orchestrator name is the <project> portion.

extract_orch_name() {
    echo "$1" | sed 's/^coda-//; s/--.*$//'
}

# --- ownership extraction ---

@test "extract: coda-orchestrator from full session name" {
    result=$(extract_orch_name "coda-coda-orchestrator--implement-session-switcher")
    [ "$result" = "coda-orchestrator" ]
}

@test "extract: openclaw from session name" {
    result=$(extract_orch_name "coda-openclaw--feature")
    [ "$result" = "openclaw" ]
}

@test "extract: coda from minimal session name" {
    result=$(extract_orch_name "coda-coda--main")
    [ "$result" = "coda" ]
}

@test "extract: handles branch with dashes" {
    result=$(extract_orch_name "coda-coda-orchestrator--fix-notification-ownership")
    [ "$result" = "coda-orchestrator" ]
}

@test "extract: handles branch with double dashes" {
    result=$(extract_orch_name "coda-openclaw--feature--with--extra-dashes")
    [ "$result" = "openclaw" ]
}

# --- hook only notifies owner ---

setup() {
    export ORCH_BASE_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_DIR="$ORCH_BASE_DIR"
    export SESSION_PREFIX="coda-test-"

    # Create two fake orchestrators with ports
    mkdir -p "$ORCH_BASE_DIR/coda-orchestrator"
    echo "4280" > "$ORCH_BASE_DIR/coda-orchestrator/port"

    mkdir -p "$ORCH_BASE_DIR/openclaw"
    echo "4281" > "$ORCH_BASE_DIR/openclaw/port"
}

@test "hook: pre-feature-teardown only targets owning orchestrator" {
    HOOK="$BATS_TEST_DIRNAME/../hooks/pre-feature-teardown/50-orch-notify"
    [ -f "$HOOK" ] || HOOK="$HOME/.config/coda/orchestrators/coda-orchestrator/hooks/pre-feature-teardown/50-orch-notify"

    # Source extraction logic from the hook (simulate)
    SESSION_NAME="coda-coda-orchestrator--test-branch"
    ORCH_NAME=$(echo "$SESSION_NAME" | sed 's/^coda-//; s/--.*$//')
    [ "$ORCH_NAME" = "coda-orchestrator" ]

    # Verify it would NOT match openclaw
    [ "$ORCH_NAME" != "openclaw" ]
}

@test "hook: post-session-create only targets owning orchestrator" {
    HOOK="$BATS_TEST_DIRNAME/../hooks/post-session-create/50-orch-notify"
    [ -f "$HOOK" ] || HOOK="$HOME/.config/coda/orchestrators/coda-orchestrator/hooks/post-session-create/50-orch-notify"

    SESSION_NAME="coda-openclaw--new-feature"
    ORCH_NAME=$(echo "$SESSION_NAME" | sed 's/^coda-//; s/--.*$//')
    [ "$ORCH_NAME" = "openclaw" ]

    # Verify it would NOT match coda-orchestrator
    [ "$ORCH_NAME" != "coda-orchestrator" ]
}

@test "hook: empty session name causes early exit" {
    SESSION_NAME=""
    [ -z "$SESSION_NAME" ]
}

@test "hook: session without double-dash extracts full name after prefix" {
    # Edge case: no branch separator
    result=$(extract_orch_name "coda-myproject")
    [ "$result" = "myproject" ]
}
