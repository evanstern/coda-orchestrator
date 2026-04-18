#!/usr/bin/env bats

setup() {
    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEMPLATE="$PLUGIN_DIR/defaults/SOUL.md.tmpl"
}

@test "template: SOUL.md.tmpl exists in defaults/" {
    [ -f "$TEMPLATE" ]
}

@test "template: contains at least 2 {{NAME}} placeholders" {
    count=$(grep -o '{{NAME}}' "$TEMPLATE" | wc -l | tr -d ' ')
    [ "$count" -ge 2 ]
}

@test "template: only contains {{NAME}} as variable content" {
    # Template should not contain hardcoded names -- only placeholders
    run grep -oP '\{\{(?!NAME)[A-Z_]+\}\}' "$TEMPLATE"
    [ "$status" -eq 1 ]
}

@test "template: has Core Identity section" {
    grep -q '## Core Identity' "$TEMPLATE"
}

@test "template: has Personality section" {
    grep -q '## Personality' "$TEMPLATE"
}

@test "template: has How I Work section" {
    grep -q '## How I Work' "$TEMPLATE"
}

@test "template: has Memory Policy section" {
    grep -q '## Memory Policy' "$TEMPLATE"
}

@test "template: has Decision Framework section" {
    grep -q '## Decision Framework' "$TEMPLATE"
}

@test "template: has References section" {
    grep -q '## References' "$TEMPLATE"
}

@test "template: has Repositories block with placeholders" {
    grep -q '\*\*Repositories:\*\*' "$TEMPLATE"
    grep -qF '[config-dir]' "$TEMPLATE"
    grep -qF '[config-remote]' "$TEMPLATE"
    grep -qF '[project-dir]' "$TEMPLATE"
    grep -qF '[project-remote]' "$TEMPLATE"
}

@test "template: Repositories block sits between Boundaries and Personality" {
    boundaries_line=$(grep -n '\*\*Boundaries:\*\*' "$TEMPLATE" | head -1 | cut -d: -f1)
    repos_line=$(grep -n '\*\*Repositories:\*\*' "$TEMPLATE" | head -1 | cut -d: -f1)
    personality_line=$(grep -n '## Personality' "$TEMPLATE" | head -1 | cut -d: -f1)
    [ "$boundaries_line" -lt "$repos_line" ]
    [ "$repos_line" -lt "$personality_line" ]
}
