#!/usr/bin/env bats
#
# tests/safe-commit.bats -- whitelist behavior for bin/safe-commit.sh
#
# We can't actually run `git commit && git push` in tests, so we stub git
# to capture invocations and exercise the whitelist gate only.

setup() {
    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$PLUGIN_DIR/bin/safe-commit.sh"

    export REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/bin-stub"
    cd "$REPO"

    # Stub git: fake diff/commit/push responses. $REPO is exported so the
    # stub can find a writable log path regardless of the script's cwd.
    cat > "$REPO/bin-stub/git" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "diff --cached")
        # Staged files are driven by env var STAGED_FILES (newline separated)
        printf '%s\n' "${STAGED_FILES:-}"
        ;;
    "commit "*|"commit")
        echo "commit $*" >> "${REPO:-/tmp}/git.log"
        ;;
    "push "*)
        echo "push $*" >> "${REPO:-/tmp}/git.log"
        ;;
    *)
        echo "unexpected git: $*" >&2
        exit 99
        ;;
esac
EOF
    chmod +x "$REPO/bin-stub/git"
    export PATH="$REPO/bin-stub:$PATH"
}

@test "safe-commit: rejects when nothing is staged" {
    STAGED_FILES="" run bash "$SCRIPT" -m "msg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Nothing staged"* ]]
}

@test "safe-commit: allows files under memory/" {
    STAGED_FILES="memory/2026-01-01.md" run bash "$SCRIPT" -m "m"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Committing"* ]]
}

@test "safe-commit: allows files under learnings/" {
    STAGED_FILES="learnings/foo.md" run bash "$SCRIPT" -m "m"
    [ "$status" -eq 0 ]
}

@test "safe-commit: allows files under wiki/" {
    STAGED_FILES="wiki/index.md" run bash "$SCRIPT" -m "m"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Committing"* ]]
}

@test "safe-commit: allows nested wiki/ paths" {
    STAGED_FILES=$'wiki/patterns/ingest.md\nwiki/index.md' \
        run bash "$SCRIPT" -m "m"
    [ "$status" -eq 0 ]
}

@test "safe-commit: allows SOUL.md, PROJECT.md, MEMORY.md" {
    STAGED_FILES=$'SOUL.md\nPROJECT.md\nMEMORY.md' \
        run bash "$SCRIPT" -m "m"
    [ "$status" -eq 0 ]
}

@test "safe-commit: rejects non-whitelisted files" {
    STAGED_FILES="lib/lifecycle.sh" run bash "$SCRIPT" -m "m"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not in the safe-commit whitelist"* ]]
}

@test "safe-commit: rejects mixed staged files when one is not whitelisted" {
    STAGED_FILES=$'wiki/index.md\nbin/safe-commit.sh' \
        run bash "$SCRIPT" -m "m"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bin/safe-commit.sh"* ]]
}
