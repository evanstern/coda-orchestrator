#!/usr/bin/env bash
# shell-init.sh -- sourced at shell init via plugin.json "init" field
# Makes _coda_feature_orch_hook and _orch_prune_dir available outside
# the coda subshell (e.g. interactive shell, cross-repo bridges).

_ORCH_SHELL_INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_ORCH_SHELL_INIT_DIR/feature-hook.sh"
# shellcheck source=/dev/null
[ -f "$_ORCH_SHELL_INIT_DIR/prune.sh" ] && source "$_ORCH_SHELL_INIT_DIR/prune.sh"
unset _ORCH_SHELL_INIT_DIR
