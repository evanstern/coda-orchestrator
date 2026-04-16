#!/usr/bin/env bats

setup() {
    PLUGIN_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEMPLATE="$PLUGIN_DIR/defaults/SOUL.md.tmpl"
}

@test "template: SOUL.md.tmpl exists in defaults/" {
    [ -f "$TEMPLATE" ]
}

@test "template: contains at least 2 {{NAME}} placeholders" {
    count=$(grep -c '{{NAME}}' "$TEMPLATE")
    [ "$count" -ge 2 ]
}

@test "template: no instance-specific content (progenitor)" {
    run grep -i 'progenitor' "$TEMPLATE"
    [ "$status" -eq 1 ]
}

@test "template: no instance-specific content (Zach)" {
    run grep -i 'zach' "$TEMPLATE"
    [ "$status" -eq 1 ]
}

@test "template: no instance-specific content (coda-orchestrator)" {
    run grep 'coda-orchestrator' "$TEMPLATE"
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
