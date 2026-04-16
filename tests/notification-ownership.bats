#!/usr/bin/env bats

# Tests for ownership extraction logic used in notification hooks.
# Session naming convention: coda-<project>--<branch>
# The orchestrator name is the <project> portion.
# Note: the actual hook scripts live in ~/.config/coda/orchestrators/ (gitignored).
# These tests verify the extraction logic and hook early-exit behavior.

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

# --- ownership filtering logic ---

@test "ownership: coda-orchestrator session does not match openclaw" {
    SESSION_NAME="coda-coda-orchestrator--test-branch"
    ORCH_NAME=$(extract_orch_name "$SESSION_NAME")
    [ "$ORCH_NAME" = "coda-orchestrator" ]
    [ "$ORCH_NAME" != "openclaw" ]
}

@test "ownership: openclaw session does not match coda-orchestrator" {
    SESSION_NAME="coda-openclaw--new-feature"
    ORCH_NAME=$(extract_orch_name "$SESSION_NAME")
    [ "$ORCH_NAME" = "openclaw" ]
    [ "$ORCH_NAME" != "coda-orchestrator" ]
}

@test "hook: empty session name causes early exit" {
    HOOK="$HOME/.config/coda/orchestrators/coda-orchestrator/hooks/pre-feature-teardown/50-orch-notify"
    if [ -f "$HOOK" ]; then
        run env CODA_SESSION_NAME="" CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators" bash "$HOOK"
        [ "$status" -eq 0 ]
        [ -z "$output" ]
    else
        # Hook not on disk (CI), verify extraction returns empty
        result=$(extract_orch_name "")
        [ -z "$result" ]
    fi
}

@test "extract: session without double-dash extracts full name after prefix" {
    result=$(extract_orch_name "coda-myproject")
    [ "$result" = "myproject" ]
}
