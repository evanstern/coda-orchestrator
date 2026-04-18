#!/usr/bin/env bash
# shell-init.sh -- sourced at shell init via plugin.json "init" field
# Makes _coda_feature_orch_hook available to coda feature start --orch

_ORCH_FEATURE_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_ORCH_FEATURE_HOOK_DIR/feature-hook.sh"
