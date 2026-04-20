#!/usr/bin/env bash
# bin/safe-commit.sh -- commit only whitelisted files
# Usage: bin/safe-commit.sh -m "commit message"

set -e

# Whitelist entries ending in "/" are directory prefixes (any path under
# them is allowed). All other entries are matched as exact paths -- so
# "SOUL.md" matches only "SOUL.md" and NOT "SOUL.md.bak", "SOUL.md~", etc.
WHITELIST=("memory/" "learnings/" "wiki/" "SOUL.md" "PROJECT.md" "MEMORY.md")

# Get staged files, NUL-delimited so paths with spaces/newlines are safe.
mapfile -d '' -t STAGED < <(git diff --cached --name-only -z)

if [ "${#STAGED[@]}" -eq 0 ]; then
    echo "Nothing staged to commit."
    exit 1
fi

for file in "${STAGED[@]}"; do
    allowed=false
    for pattern in "${WHITELIST[@]}"; do
        if [[ "$pattern" == */ ]]; then
            if [[ "$file" == "$pattern"* ]]; then
                allowed=true
                break
            fi
        else
            if [[ "$file" == "$pattern" ]]; then
                allowed=true
                break
            fi
        fi
    done
    if [ "$allowed" = false ]; then
        echo "ERROR: '$file' is not in the safe-commit whitelist."
        echo "Whitelisted paths: ${WHITELIST[*]}"
        echo "Use a feature branch for this change."
        exit 1
    fi
done

echo "All staged files are whitelisted. Committing..."
git commit "$@" && git push origin main
