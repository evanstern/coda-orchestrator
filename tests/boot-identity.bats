#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4280
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"
    export PROJECTS_DIR="$BATS_TEST_TMPDIR/projects"
    export HOME="$BATS_TEST_TMPDIR/home"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"
    source "$PLUGIN_DIR/coda-handler.sh"
}

teardown() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep 'coda-test-' | while read -r s; do
        tmux kill-session -t "$s" 2>/dev/null || true
    done
}

@test "generate_agents_md: output contains /boot-identity" {
    run _orch_generate_agents_md testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"/boot-identity"* ]]
}

@test "generate_agents_md: output does NOT contain IDENTITY OVERRIDE" {
    run _orch_generate_agents_md testbot
    [ "$status" -eq 0 ]
    [[ "$output" != *"# IDENTITY OVERRIDE"* ]]
}

@test "generate_agents_md: output does NOT inline SOUL.md content" {
    _orch_new testbot
    run _orch_generate_agents_md testbot
    [ "$status" -eq 0 ]
    [[ "$output" != *"Core Identity"* ]]
    [[ "$output" != *"Personality"* ]]
}

@test "generate_project_config: output contains PROJECT.md" {
    run _orch_generate_project_config testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROJECT.md"* ]]
}

@test "orch_new: creates boot-identity skill in opencode skills dir" {
    _orch_new testbot
    [ -f "$HOME/.config/opencode/skills/boot-identity/SKILL.md" ]
}

@test "orch_start: preserves existing AGENTS.md" {
    _orch_new testbot
    local dir="$CODA_ORCH_DIR/testbot"
    echo "custom agents content" > "$dir/AGENTS.md"
    _orch_start testbot
    run cat "$dir/AGENTS.md"
    [[ "$output" == "custom agents content" ]]
}

@test "orch_start: preserves existing opencode.json" {
    _orch_new testbot
    local dir="$CODA_ORCH_DIR/testbot"
    echo '{"custom": true}' > "$dir/opencode.json"
    _orch_start testbot
    run cat "$dir/opencode.json"
    [[ "$output" == '{"custom": true}' ]]
}
