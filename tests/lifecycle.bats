#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export CODA_ORCH_PORT_BASE=4250
    export CODA_ORCH_PORT_RANGE=10
    export SESSION_PREFIX="coda-test-"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"
    source "$PLUGIN_DIR/coda-handler.sh"
}

teardown() {
    for dir in "$CODA_ORCH_DIR"/*/; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")
        _orch_stop "$name" 2>/dev/null || true
    done
}

# --- new ---

@test "new: creates orchestrator directory" {
    run _orch_new testbot
    [ "$status" -eq 0 ]
    [ -d "$CODA_ORCH_DIR/testbot" ]
}

@test "new: creates SOUL.md" {
    _orch_new testbot
    [ -f "$CODA_ORCH_DIR/testbot/SOUL.md" ]
}

@test "new: creates AGENTS.md" {
    _orch_new testbot
    [ -f "$CODA_ORCH_DIR/testbot/AGENTS.md" ]
}

@test "new: creates opencode.json with instructions" {
    _orch_new testbot
    [ -f "$CODA_ORCH_DIR/testbot/opencode.json" ]
    run jq -r '.instructions[0]' "$CODA_ORCH_DIR/testbot/opencode.json"
    [ "$output" = "SOUL.md" ]
}

@test "new: creates scope.json" {
    _orch_new testbot
    [ -f "$CODA_ORCH_DIR/testbot/scope.json" ]
}

@test "new: creates memory directory" {
    _orch_new testbot
    [ -d "$CODA_ORCH_DIR/testbot/memory" ]
}

@test "new: creates MEMORY.md" {
    _orch_new testbot
    [ -f "$CODA_ORCH_DIR/testbot/MEMORY.md" ]
}

@test "new: initializes git repo" {
    _orch_new testbot
    [ -d "$CODA_ORCH_DIR/testbot/.git" ]
}

@test "new: rejects duplicate name" {
    _orch_new testbot
    run _orch_new testbot
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "new: custom scope is written" {
    _orch_new testbot --scope 'coda-myapp--*'
    run jq -r '.watch[0]' "$CODA_ORCH_DIR/testbot/scope.json"
    [ "$output" = "coda-myapp--*" ]
}

@test "new: default scope uses template" {
    _orch_new testbot
    run jq -r '.watch[0]' "$CODA_ORCH_DIR/testbot/scope.json"
    [ "$output" = "coda-*" ]
}

@test "new: AGENTS.md contains identity override" {
    _orch_new testbot
    grep -q 'IDENTITY OVERRIDE' "$CODA_ORCH_DIR/testbot/AGENTS.md"
}

@test "new: AGENTS.md inlines SOUL.md content" {
    _orch_new testbot
    grep -q 'SOUL.md' "$CODA_ORCH_DIR/testbot/AGENTS.md"
}

# --- start/stop ---

@test "start: creates tmux session" {
    _orch_new testbot
    _orch_start testbot
    tmux has-session -t "${SESSION_PREFIX}orch--testbot" 2>/dev/null
}

@test "start: writes port file" {
    _orch_new testbot
    _orch_start testbot
    [ -f "$CODA_ORCH_DIR/testbot/port" ]
    local port
    port=$(cat "$CODA_ORCH_DIR/testbot/port")
    [ "$port" -ge "$ORCH_PORT_BASE" ]
}

@test "start: idempotent when already running" {
    _orch_new testbot
    _orch_start testbot
    run _orch_start testbot
    [ "$status" -eq 0 ]
    [[ "$output" == *"already running"* ]]
}

@test "start: regenerates AGENTS.md" {
    _orch_new testbot
    echo 'stale' > "$CODA_ORCH_DIR/testbot/AGENTS.md"
    _orch_start testbot
    ! grep -q '^stale$' "$CODA_ORCH_DIR/testbot/AGENTS.md"
}

@test "stop: removes tmux session" {
    _orch_new testbot
    _orch_start testbot
    _orch_stop testbot
    ! tmux has-session -t "${SESSION_PREFIX}orch--testbot" 2>/dev/null
}

@test "stop: removes port file" {
    _orch_new testbot
    _orch_start testbot
    _orch_stop testbot
    [ ! -f "$CODA_ORCH_DIR/testbot/port" ]
}

@test "stop: idempotent when not running" {
    _orch_new testbot
    run _orch_stop testbot
    [ "$status" -eq 0 ]
}

# --- ls ---

@test "ls: lists orchestrators" {
    _orch_new testbot
    run _orch_ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"testbot"* ]]
}

@test "ls: shows running state" {
    _orch_new testbot
    _orch_start testbot
    run _orch_ls
    [[ "$output" == *"running"* ]]
}

@test "ls: shows stopped state" {
    _orch_new testbot
    run _orch_ls
    [[ "$output" == *"stopped"* ]]
}

# --- done ---

@test "done: removes orchestrator directory" {
    _orch_new testbot
    _orch_done testbot
    [ ! -d "$CODA_ORCH_DIR/testbot" ]
}

@test "done: stops running orchestrator first" {
    _orch_new testbot
    _orch_start testbot
    _orch_done testbot
    ! tmux has-session -t "${SESSION_PREFIX}orch--testbot" 2>/dev/null
    [ ! -d "$CODA_ORCH_DIR/testbot" ]
}

@test "done --archive: moves to archive" {
    _orch_new testbot
    _orch_done testbot --archive
    [ ! -d "$CODA_ORCH_DIR/testbot" ]
    local archive_count
    archive_count=$(ls -d "$CODA_ORCH_DIR/.archive/testbot-"* 2>/dev/null | wc -l)
    [ "$archive_count" -eq 1 ]
}

@test "done --archive: archive contains SOUL.md" {
    _orch_new testbot
    _orch_done testbot --archive
    local archive_dir
    archive_dir=$(ls -d "$CODA_ORCH_DIR/.archive/testbot-"* 2>/dev/null | head -1)
    [ -f "$archive_dir/SOUL.md" ]
}

# --- port allocation ---

@test "ports: two orchestrators get different ports" {
    _orch_new bot-a
    _orch_new bot-b
    _orch_start bot-a
    _orch_start bot-b
    local port_a port_b
    port_a=$(cat "$CODA_ORCH_DIR/bot-a/port")
    port_b=$(cat "$CODA_ORCH_DIR/bot-b/port")
    [ "$port_a" != "$port_b" ]
}
