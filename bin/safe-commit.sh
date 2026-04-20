#!/usr/bin/env bash
# bin/safe-commit.sh -- commit only whitelisted files
# Usage: bin/safe-commit.sh -m "commit message"

set -e

WHITELIST=("memory/" "learnings/" "wiki/" "SOUL.md" "PROJECT.md" "MEMORY.md")

# Get staged files
STAGED=$(git diff --cached --name-only)

if [ -z "$STAGED" ]; then
    echo "Nothing staged to commit."
    exit 1
fi

# Check each staged file against whitelist
for file in $STAGED; do
    allowed=false
    for pattern in "${WHITELIST[@]}"; do
        if [[ "$file" == $pattern* ]]; then
            allowed=true
            break
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
