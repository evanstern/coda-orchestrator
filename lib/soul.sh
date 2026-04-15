#!/usr/bin/env bash
#
# soul.sh u2014 soul generation and editing
#

_orch_generate_soul() {
    local name="$1"
    local speech="$2"

    if command -v opencode &>/dev/null; then
        local prompt
        prompt=$(cat <<PROMPT
Generate a SOUL.md file for a coda orchestrator named "$name".

The user described the personality as:
"$speech"

Output ONLY the markdown content (no code fences). Use this structure:

# SOUL.md u2014 $name

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
        opencode run --format json "$prompt" 2>/dev/null \
            | jq -r '.[-1].content // empty' 2>/dev/null
    fi

    # Fallback if opencode or jq failed: write the raw speech as a basic soul
    if [ ${PIPESTATUS[0]:-1} -ne 0 ] || [ -z "$(cat)" ] 2>/dev/null; then
        cat <<EOF
# SOUL.md u2014 $name

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

    if [ -n "${EDITOR:-}" ]; then
        "$EDITOR" "$soul_file"
    else
        echo "$soul_file"
    fi
}
