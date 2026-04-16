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

@test "template: contains at least 1 {{PROJECT}} placeholder" {
    count=$(grep -o '{{PROJECT}}' "$TEMPLATE" | wc -l | tr -d ' ')
    [ "$count" -ge 1 ]
}

@test "template: only contains {{NAME}} and {{PROJECT}} as variable content" {
    # Template should not contain hardcoded names -- only placeholders
    run grep -oP '\{\{(?!NAME|PROJECT)[A-Z_]+\}\}' "$TEMPLATE"
    [ "$status" -eq 1 ]
}

@test "template: has Core Identity section" {
    grep -q '## Core Identity' "$TEMPLATE"
}

@test "template: has Personality section" {
    grep -q '## Personality' "$TEMPLATE"
}

@test "template: has Workflows section" {
    grep -q '## Workflows' "$TEMPLATE"
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
