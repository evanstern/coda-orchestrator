#!/usr/bin/env bash
#
# coda-handler.sh -- coda orchestrator plugin command dispatcher
#
# Sourced by coda's plugin system. Provides `coda orch <subcommand>`.
#

_ORCH_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_BASE_DIR="${CODA_ORCH_DIR:-$HOME/.config/coda/orchestrators}"
ORCH_PORT_BASE="${CODA_ORCH_PORT_BASE:-4200}"
ORCH_PORT_RANGE="${CODA_ORCH_PORT_RANGE:-20}"

# Source library modules. prune is sourced before lifecycle so
# _orch_start can reference _orch_prune_dir.
for _orch_mod in prune lifecycle soul observe send spawn; do
    if [ -f "$_ORCH_PLUGIN_DIR/lib/${_orch_mod}.sh" ]; then
        # shellcheck source=/dev/null
        source "$_ORCH_PLUGIN_DIR/lib/${_orch_mod}.sh"
    fi
done
unset _orch_mod

_coda_orch() {
    local subcmd="${1:-help}"
    shift 2>/dev/null || true

    case "$subcmd" in
        new)     _orch_new "$@" ;;
        ls)      _orch_ls "$@" ;;
        start)   _orch_start "$@" ;;
        stop)    _orch_stop "$@" ;;
        status)  _orch_status "$@" ;;
        send)    _orch_send "$@" ;;
        edit)    _orch_edit "$@" ;;
        done)    _orch_done "$@" ;;
        spawns)  _orch_spawn_status "$@" ;;
        prune)   _orch_prune "$@" ;;
        help|"")
            cat <<'EOF'
coda orch -- orchestrator management

USAGE
  coda orch new <name> [--soul "..."] [--scope "pattern"]   Create orchestrator
  coda orch ls                                              List orchestrators
  coda orch start <name>                                    Start orchestrator
  coda orch stop <name>                                     Stop orchestrator
  coda orch status <name>                                   Session status in scope
  coda orch send <name> <message> [--async]                 Send prompt
  coda orch edit <name>                                     Edit SOUL.md
  coda orch done <name> [--archive]                         Tear down orchestrator
  coda orch spawns <name>                                   List spawned sessions
  coda orch prune [name] [--hard] [--dry-run]               Prune stale sessions
EOF
            ;;
        *)
            echo "Unknown orch subcommand: $subcmd"
            echo "Run 'coda orch help' for usage."
            return 1
            ;;
    esac
}
