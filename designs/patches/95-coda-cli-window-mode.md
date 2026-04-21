# Card #95 -- coda CLI: window-mode + `--orch` flag

**Status:** Ready for Zach to route into `evanstern/coda`.
**Patch:** `95-coda-cli-window-mode.patch` (sibling file).
**Design ref:** `../features-as-orchestrator-windows.md`.
**Branch (source):** `95-coda-cli-window-mode-and-orch-flag` (local only; not merged).

## What changed

Foundational CLI piece of the features-as-orchestrator-windows roadmap.
Off by default. Byte-identical behavior when both triggers are unset.

### `lib/feature.sh` -- `_coda_feature_start`

- New `--orch <name>` / `--orch=<name>` parser placed before the usage
  check. Keeps positional args `<branch> [base] [project]` intact.
- Resolves `orch_name` -> `orch_target="${SESSION_PREFIX}orch--<sanitized>"`
  (matches the `coda-orch--<name>` convention from the design doc).
- When `--orch` is set, invokes `_coda_attach` with
  `CODA_ORCH_WINDOW_MODE=1 CODA_ORCH_TARGET=<orch-session>` in the env.
- When `CODA_ORCH_WINDOW_MODE=1` is set but no `--orch` resolves, emits a
  warning and falls back to session-mode (project-field-based discovery
  is card #94).

### `lib/core.sh` -- `_coda_attach`

- Window-mode detected when `CODA_ORCH_WINDOW_MODE=1` AND `CODA_ORCH_TARGET`
  resolves to an existing tmux session (`tmux has-session -t`).
- When target is configured but missing, emits the informational
  "Orchestrator session not found / Falling back to standalone session-mode"
  pair and continues to the existing session path. No crash.
- In window-mode:
  - Derives `window_name` by stripping `${SESSION_PREFIX}` and
    `<project>--` from the computed feature session name.
  - Skips `_layout_init` entirely.
  - Calls `_layout_spawn` with `CODA_LAYOUT_TARGET="${orch}:${window}"`
    so layouts can target `session:window` instead of the current
    session.
  - Sets `CODA_DIR` on the orch session environment so downstream
    tooling still sees the feature's working directory.
  - Runs `post-session-create` and `post-session-attach` hooks with
    `CODA_SESSION_NAME="<orch>:<window>"` so hook scripts can tell
    window-mode apart. (Dedicated `post-window-create` is card #99
    and out of scope here.)
  - For attach: uses `tmux switch-client` when already in TMUX, else
    `tmux attach -t <orch-session>`. Never nests clients.
- When `window_mode=false`, the pre-existing code path runs unchanged.

### `layouts/default.sh`, `layouts/classic.sh` -- `_layout_spawn`

- Both now honor `CODA_LAYOUT_TARGET`. If set, split into
  `<session>` and `<window>` and issue `tmux new-window -t <session>
  -n <window> -c <dir> ...`. If unset, old behavior is preserved.
- Other layouts (`wide-twopane`, `three-pane`, `four-pane`) were left
  as-is; per the brief, default + classic are the minimum viable
  window-mode-capable layouts. They remain usable in session-mode.

### Tests

- 9 new bats cases in `test/shell-modules.bats` (prefix
  `card95:`) covering:
  - `--orch riley <branch>` parsing.
  - `--orch=riley <branch>` parsing.
  - No `--orch` does not set `CODA_ORCH_*` env vars.
  - `_coda_attach` window-mode with missing orch session prints the
    fallback warning.
  - `_coda_attach` without window-mode uses the existing session path
    (`_layout_init` invoked, `_layout_spawn` not).
  - `_coda_attach` window-mode spawns into `<orch>:<window>` when the
    orch session exists.
  - `default` + `classic` layouts honor `CODA_LAYOUT_TARGET`.
  - `default` layout falls back to `$session` when target is unset.
- Existing `tests/window-mode.sh` integration harness (fake tmux +
  fake fzf in `tests/bin/`) still PASSES without modification. It
  exercises the fallback path, the orch-window spawn path, the
  no-flag session path, and the "worktree already exists + --orch"
  path end-to-end.

## Contract matrix

| trigger state | orch session exists? | result |
|---|---|---|
| `--orch riley` (or env=1 + target) | yes | window `foo` in `coda-orch--riley` |
| `--orch riley` (or env=1 + target) | no  | warning, standalone session (byte-id with today) |
| no flag, env unset | n/a | standalone session (byte-identical with today) |
| env=1, no target resolvable | n/a | warning in `_coda_feature_start`, standalone session |

## Test output

Full `bats test/shell-modules.bats` on the branch:

```
1..176
... (all pass)
ok 168 card95: _coda_feature_start parses --orch <name> with space
ok 169 card95: _coda_feature_start parses --orch=name form
ok 170 card95: _coda_feature_start without --orch does not set CODA_ORCH_TARGET
ok 171 card95: _coda_attach window-mode requires existing orch session
ok 172 card95: _coda_attach without window-mode takes standard path
ok 173 card95: _coda_attach window-mode spawns window when orch exists
ok 174 card95: default layout _layout_spawn honors CODA_LAYOUT_TARGET
ok 175 card95: default layout _layout_spawn falls back to session when no target
ok 176 card95: classic layout _layout_spawn honors CODA_LAYOUT_TARGET
```

`bash tests/run.sh`:

```
==> core-lifecycle.sh
PASS: core lifecycle tests
==> plugin-dep-detection.sh
PASS: plugin dependency detection tests
==> window-mode.sh
PASS: window-mode tests
```

## Applying this patch

From a clean checkout of `evanstern/coda` on `main`:

```
git checkout -b card-95-window-mode
git am /path/to/95-coda-cli-window-mode.patch
bats test/shell-modules.bats
bash tests/run.sh
```

Then open a PR in the usual way.

## Out of scope (explicit)

- `_coda_feature_done`, `_coda_feature_finish` window-aware teardown -- card #96.
- `_coda_ls`, `_coda_switch` window enumeration -- card #97.
- Hook events `post-window-create` / `pre-window-teardown` -- card #99.
- Project-field-based orch resolution via scope.json -- card #94.
- Flipping the default to window-mode -- wave 4.
- `wide-twopane`, `three-pane`, `four-pane` window-mode support --
  stretch, can ship later without blocking #95.
