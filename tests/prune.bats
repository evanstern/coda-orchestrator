#!/usr/bin/env bats

setup() {
    export CODA_ORCH_DIR="$BATS_TEST_TMPDIR/orchestrators"
    export HOME="$BATS_TEST_TMPDIR/home"
    export ORCH_BASE_DIR="$CODA_ORCH_DIR"
    mkdir -p "$CODA_ORCH_DIR" "$HOME"

    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export _ORCH_PLUGIN_DIR="$PLUGIN_DIR"

    if [ ! -f "$PLUGIN_DIR/lib/prune.sh" ]; then
        skip "prune.sh not installed in this worktree"
    fi
    source "$PLUGIN_DIR/lib/prune.sh"

    _orch_dir() { echo "$ORCH_BASE_DIR/$1"; }
    export -f _orch_dir
}

teardown() {
    rm -rf "$CODA_ORCH_DIR" "$HOME"
    unset -f curl _orch_dir 2>/dev/null || true
}

_mk_sessions_json() {
    local first=true row id updated parent
    printf '['
    for row in "$@"; do
        IFS=':' read -r id updated parent <<< "$row"
        $first || printf ','
        first=false
        if [ -n "$parent" ]; then
            printf '{"id":"%s","time":{"updated":%s},"parentID":"%s"}' "$id" "$updated" "$parent"
        else
            printf '{"id":"%s","time":{"updated":%s}}' "$id" "$updated"
        fi
    done
    printf ']'
}

# --- validation ---

@test "prune_dir: refuses empty args" {
    run _orch_prune_dir
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "prune_dir: refuses relative directory" {
    run _orch_prune_dir 4200 relative/path
    [ "$status" -eq 1 ]
    [[ "$output" == *"absolute path"* ]]
}

@test "prune_dir: refuses non-numeric port" {
    run _orch_prune_dir notaport /tmp/orch1
    [ "$status" -eq 1 ]
    [[ "$output" == *"port must be numeric"* ]]
}

@test "prune_dir: rejects unknown flags" {
    run _orch_prune_dir 4200 /tmp/orch1 --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flag"* ]]
}

# --- retention logic (stubbed curl) ---

@test "prune_dir: keeps active sessions" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local old_ms=$(( now_ms - 100 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json "ses_active:$old_ms:" "ses_old:$old_ms:")

    curl() {
        case "$*" in
            *"/session/status?directory="*) echo '{"ses_active":{"running":true}}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 0 --days 0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"would: "*"ses_active"* ]]
    [[ "$output" == *"would: "*"ses_old"* ]]
}

@test "prune_dir: keeps child sessions (parentID set)" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local old_ms=$(( now_ms - 100 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json "ses_child:$old_ms:ses_parent" "ses_orphan:$old_ms:")

    curl() {
        case "$*" in
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 0 --days 0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"ses_child"* ]]
    [[ "$output" == *"would: "*"ses_orphan"* ]]
}

@test "prune_dir: keeps KEEP most-recent" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local old_ms=$(( now_ms - 100 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json \
        "ses_1:$((old_ms + 5)):" \
        "ses_2:$((old_ms + 4)):" \
        "ses_3:$((old_ms + 3)):" \
        "ses_4:$((old_ms + 2)):" \
        "ses_5:$((old_ms + 1)):" \
        "ses_6:$old_ms:")

    curl() {
        case "$*" in
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 5 --days 0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"pruned: kept=5"* ]]
    [[ "$output" == *"ses_6"* ]]
    [[ "$output" != *"would: "*"ses_1"* ]]
}

@test "prune_dir: keeps sessions within days window" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local recent_ms=$(( now_ms - 1 * 86400 * 1000 ))
    local old_ms=$(( now_ms - 100 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json \
        "ses_recent:$recent_ms:" \
        "ses_old:$old_ms:")

    curl() {
        case "$*" in
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 0 --days 14 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"would: "*"ses_recent"* ]]
    [[ "$output" == *"would: "*"ses_old"* ]]
}

# --- dry-run / default / hard ---

@test "prune_dir: --dry-run does not mutate" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local old_ms=$(( now_ms - 100 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json "ses_old:$old_ms:")

    local mutate="$BATS_TEST_TMPDIR/mutate"
    : > "$mutate"

    curl() {
        case "$*" in
            *"-X DELETE"*|*"-X PATCH"*) echo "$*" >> "$mutate" ;;
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 0 --days 0 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would: delete ses_old"* ]]
    [ ! -s "$mutate" ]
}

@test "prune_dir: default archives via PATCH when below hard cutoff" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local mid_ms=$(( now_ms - 10 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json "ses_mid:$mid_ms:")

    local delete_log="$BATS_TEST_TMPDIR/delete"
    local patch_log="$BATS_TEST_TMPDIR/patch"
    : > "$delete_log"
    : > "$patch_log"

    curl() {
        case "$*" in
            *"-X DELETE"*) echo "$*" >> "$delete_log" ;;
            *"-X PATCH"*)  echo "$*" >> "$patch_log" ;;
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 0 --days 7
    [ "$status" -eq 0 ]
    [[ "$output" == *"archived=1"* ]]
    [[ "$output" == *"deleted=0"* ]]
    [ ! -s "$delete_log" ]
    [ -s "$patch_log" ]
    grep -q 'archived' "$patch_log"
}

@test "prune_dir: --hard deletes instead of archiving" {
    local now_ms=$(( $(date +%s) * 1000 ))
    local mid_ms=$(( now_ms - 10 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json "ses_mid:$mid_ms:")

    local delete_log="$BATS_TEST_TMPDIR/delete"
    local patch_log="$BATS_TEST_TMPDIR/patch"
    : > "$delete_log"
    : > "$patch_log"

    curl() {
        case "$*" in
            *"-X DELETE"*) echo "$*" >> "$delete_log" ;;
            *"-X PATCH"*)  echo "$*" >> "$patch_log" ;;
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/orch1 --keep 0 --days 7 --hard
    [ "$status" -eq 0 ]
    [[ "$output" == *"deleted=1"* ]]
    [[ "$output" == *"archived=0"* ]]
    [ -s "$delete_log" ]
    [ ! -s "$patch_log" ]
}

@test "prune_dir: summary line shape (empty list)" {
    curl() {
        case "$*" in
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo '[]' ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    run _orch_prune_dir 4200 /tmp/myorch
    [ "$status" -eq 0 ]
    [[ "$output" == "pruned: kept=0 archived=0 deleted=0 (dir=myorch)" ]]
}

@test "prune_dir: every HTTP call carries ?directory=" {
    local calls="$BATS_TEST_TMPDIR/calls"
    : > "$calls"

    local now_ms=$(( $(date +%s) * 1000 ))
    local old_ms=$(( now_ms - 100 * 86400 * 1000 ))
    local sessions
    sessions=$(_mk_sessions_json "ses_a:$old_ms:")

    curl() {
        echo "$*" >> "$calls"
        case "$*" in
            *"/session/status?directory="*) echo '{}' ;;
            *"/session?directory="*)        echo "$sessions" ;;
            *"-X DELETE"*|*"-X PATCH"*)     return 0 ;;
            *)                              return 1 ;;
        esac
    }
    export -f curl

    _orch_prune_dir 4200 /tmp/orchA --keep 0 --days 0

    [ -s "$calls" ]
    while IFS= read -r line; do
        [[ "$line" == *"directory="* ]] || {
            printf 'unscoped call: %s\n' "$line" >&2
            return 1
        }
        [[ "$line" != *"orchB"* ]] || {
            printf 'leaked into orchB: %s\n' "$line" >&2
            return 1
        }
    done < "$calls"
}

# --- dispatcher (_orch_prune_one) ---

@test "prune_one: 'not running' when port file missing" {
    mkdir -p "$ORCH_BASE_DIR/ghost"
    run _orch_prune_one ghost
    [ "$status" -eq 0 ]
    [[ "$output" == *"not running"* ]]
}

@test "prune_one: 'not responding' when serve is dead" {
    mkdir -p "$ORCH_BASE_DIR/dead"
    echo "59999" > "$ORCH_BASE_DIR/dead/port"

    curl() { return 7; }
    export -f curl

    run _orch_prune_one dead
    [ "$status" -eq 0 ]
    [[ "$output" == *"not responding"* ]]
}

@test "prune_one: rejects invalid port in port file" {
    mkdir -p "$ORCH_BASE_DIR/bogus"
    echo "notaport" > "$ORCH_BASE_DIR/bogus/port"

    run _orch_prune_one bogus
    [ "$status" -eq 0 ]
    [[ "$output" == *"invalid port"* ]]
}

@test "prune_one: not found for unknown orchestrator" {
    run _orch_prune_one ghost_never_created
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# --- live opencode serve: two-directory scoping ---

_prune_test_pick_port() {
    local p=4290
    while ss -tln 2>/dev/null | grep -q ":$p "; do
        p=$((p + 1))
        [ "$p" -gt 4330 ] && return 1
    done
    echo "$p"
}

_prune_test_wait_ready() {
    local port="$1" i
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

@test "live: pruning dir A leaves dir B untouched" {
    if ! command -v opencode >/dev/null 2>&1; then
        skip "opencode not installed"
    fi

    local port
    port=$(_prune_test_pick_port) || skip "no free port in 4290-4330"

    local dir_a="$BATS_TEST_TMPDIR/orchA"
    local dir_b="$BATS_TEST_TMPDIR/orchB"
    mkdir -p "$dir_a" "$dir_b"
    printf '{}\n' > "$dir_a/opencode.json"
    printf '{}\n' > "$dir_b/opencode.json"

    local log="$BATS_TEST_TMPDIR/serve.log"
    OPENCODE_PERMISSION='{"*":"allow"}' opencode serve --port "$port" \
        > "$log" 2>&1 &
    local serve_pid=$!

    if ! _prune_test_wait_ready "$port"; then
        kill "$serve_pid" 2>/dev/null
        skip "opencode serve did not come up"
    fi

    local encA encB
    encA=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$dir_a")
    encB=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$dir_b")

    local base="http://localhost:$port" i
    for i in 1 2 3; do
        curl -sf -X POST "$base/session?directory=$encA" \
            -H 'Content-Type: application/json' -d '{}' >/dev/null
        curl -sf -X POST "$base/session?directory=$encB" \
            -H 'Content-Type: application/json' -d '{}' >/dev/null
    done

    local count_b_before
    count_b_before=$(curl -sf "$base/session?directory=$encB" | jq 'length')

    run _orch_prune_dir "$port" "$dir_a" --hard --keep 0 --days 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"pruned:"* ]]

    local count_b_after
    count_b_after=$(curl -sf "$base/session?directory=$encB" | jq 'length')

    kill "$serve_pid" 2>/dev/null || true
    wait "$serve_pid" 2>/dev/null || true

    [ "$count_b_before" = "$count_b_after" ]
}
