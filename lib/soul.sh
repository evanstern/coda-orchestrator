#!/usr/bin/env bash
#
# soul.sh -- soul generation and editing
#

_orch_generate_soul() {
    local name="$1"
    local speech="$2"

    local result=""

    if command -v opencode &>/dev/null && command -v jq &>/dev/null; then
        local prompt
        prompt=$(cat <<PROMPT
Generate a SOUL.md file for a coda orchestrator named "$name".

The user described the personality as:
"$speech"

Rules:
- Output ONLY the raw markdown. No preamble, no explanation, no code fences.
- The very first line of your output must be: # SOUL.md — $name
- Do NOT start with "Here is" or any other introduction.

Structure:

# SOUL.md — $name

## Identity
Name, what this orchestrator does, its scope.

## Attitude
Tone, communication style, proactivity level derived from the description.

## Boundaries
What it manages, what it doesn't touch, when to act vs observe.

## Decision Defaults
What it does autonomously, what it asks about.

## Memory Policy
What's worth remembering, what to discard.

Be concise. Match the tone the user described. No filler.
PROMPT
        )

        local raw raw_status=0
        raw=$(
            set -o pipefail
            opencode run --pure --format json "$prompt" 2>/dev/null \
                | jq -r 'select(.type == "text") | .part.text // empty' 2>/dev/null
        ) || raw_status=$?
        if [ "$raw_status" -ne 0 ]; then
            echo "Warning: opencode failed to generate SOUL; using template." >&2
        fi
        # Strip any preamble before the heading
        result=$(printf '%s\n' "$raw" | sed -n '/^# SOUL\.md/,$p')
    fi

    if [ -n "$result" ]; then
        printf '%s\n' "$result"
    else
        cat <<EOF
# SOUL.md — $name

## Identity
Name: $name

## Attitude
$speech

## Boundaries
Not yet defined. Edit this file to set scope and limits.

## Decision Defaults
Observe and report. Ask before acting.

## Memory Policy
Remember errors, patterns, and session outcomes. Forget routine state.
EOF
    fi
}

_orch_edit() {
    local name="$1"

    if [ -z "$name" ]; then
        echo "Usage: coda orch edit <name>"
        return 1
    fi

    local dir
    dir="$(_orch_dir "$name")"

    if [ ! -d "$dir" ]; then
        echo "Orchestrator not found: $name"
        return 1
    fi

    local soul_file="$dir/SOUL.md"

    local editor_cmd="${VISUAL:-${EDITOR:-}}"

    if [ -n "$editor_cmd" ]; then
        # Use sh -c so EDITOR values with arguments (e.g. 'code --wait') work.
        sh -c "$editor_cmd \"\$1\"" _ "$soul_file"
    else
        echo "$soul_file"
    fi
}
