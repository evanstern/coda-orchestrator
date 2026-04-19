# Design: Features as Orchestrator Windows

**Cards:** TBD (this doc proposes the card set)
**Status:** Draft for review
**Repos:** coda (CLI, primary), coda-orchestrator (hook, scope handling)

## Problem

Today, feature sessions spawned by orchestrators are top-level tmux
sessions. An orchestrator like `coda-orch--riley` runs in its own
session; each feature it spawns becomes a sibling like
`coda-coda-orchestrator--81-fix-send`. The relationship between
orchestrator and its features is implicit -- encoded in session-name
prefixes and resolved by scope.json glob matching.

Concrete consequences:

1. `tmux ls` and `ctrl+b s` produce a flat list. Orchestrators and
   features intermingle. There is no visual grouping.
2. Discoverability requires memorizing the naming convention
   (`coda-<project>--<branch>`) or scanning `coda orch status`.
3. `coda orch switch` and `coda orch sessions` rely on glob-filtering
   `tmux list-sessions` -- not on a real parent/child relationship.
4. Feature sessions are otherwise invisible UI: they host one
   `opencode serve` pane, no workspace. Attaching to a feature means
   running `opencode attach http://localhost:<port>` from somewhere
   else.
5. Two code paths do the same thing (`coda feature start` standalone
   vs `coda feature start` via orchestrator hook), each reimplementing
   session lifecycle.
6. Scope.json watch/ignore globs exist solely to reconstruct the
   hierarchy tmux doesn't natively express.

## Proposal

Features spawned by an orchestrator become **windows inside the
orchestrator's tmux session**, not separate top-level sessions.

```
Before:                          After:
coda-orch--riley                 riley (or: coda-orch--riley)
  Win 1: serve                     Win 1: serve
  Win 2: scratch                   Win 2: scratch
  Win 3: workspace                 Win 3: workspace
                                   Win 4: 81-fix-send      <-- new
coda-coda-orch--81-fix-send        Win 5: 76-session-prune <-- new
coda-coda-orch--76-session-prune
```

Each feature window:
- Is named `<id>-<slug>` (e.g. `81-fix-send`) -- sortable, greppable
- Hosts the feature's `opencode serve` in pane 0
- Applies the configured layout (single or multi-pane) to that window
- Auto-triggers the feature agent via `opencode run --attach` the
  same way the current hook does
- Lives and dies with `coda feature done`/`finish`, which now
  `kill-window` instead of `kill-session`

## Why this works cleanly

The big reveal from the code survey: **every existing layout already
has a `_layout_spawn` function** that uses `tmux new-window`.
`_layout_spawn` was built for `coda layout apply` (add a new window to
the current session). The same function is the right hook for
spawning a feature window inside an orchestrator session. No new
primitive. Just a new call site.

The redesign becomes:
1. At session creation time (no orch mode): call `_layout_init` (today)
2. At window-in-orch creation time: call `_layout_spawn` targeting
   the orchestrator's session

Every layout -- `classic`, `default`, `three-pane`, `wide-twopane`,
`four-pane` -- already works as a window layout because that was the
original use case of `_layout_spawn`.

## User experience

### Attach to an orchestrator
```
tmux attach -t riley    # or coda riley
```
Lands on whatever window was last active. `ctrl+b w` shows every
window including the feature windows.

### Start a feature
```
coda feature start 92-new-thing      # inside project root owned by orch
```
1. Worktree created (unchanged)
2. Orchestrator auto-started if not running (new)
3. `tmux new-window -t riley: -n 92-new-thing` (replacing new-session)
4. Layout applied via `_layout_spawn` (same code as today, different
   call site)
5. `opencode serve` comes up in pane 0
6. `opencode run --attach` auto-triggers the agent (unchanged)

User attaches to `riley`, ctrl+b w, picks the feature window.

### Spawning without being attached
Works exactly like today. `tmux new-window -d -t riley:` creates the
window detached; the user or agent attaches later.

### Finish a feature
```
coda feature done 92-new-thing
```
1. Find window by name in orchestrator session
2. `tmux kill-window -t riley:92-new-thing`
3. Remove worktree, delete branch (unchanged)

### Without an orchestrator
`coda feature start` standalone (not under an orchestrator-managed
project) keeps the current session-per-feature flow. No change for
non-orchestrator users.

## How orchestrator association is resolved

Currently: scope.json `watch` globs match session names.

Proposal:
- **Primary:** project repo configuration. An orchestrator's
  `scope.json` (or a new `orchestrator` key in the project's `.coda.env`)
  maps a project directory to an orchestrator name. When
  `_coda_feature_start` runs inside that project, it looks up the
  orchestrator and targets its session.
- **Fallback:** existing scope.json watch pattern matching. Preserves
  backwards compatibility for orchestrators that watch multiple projects.
- **Auto-start:** if the resolved orchestrator is not running, start
  it first (background), then create the feature window.

## Architecture changes

### coda repo (primary)

**`lib/core.sh` (`_coda_attach`):**
- Detect orchestrator mode (new): either the project has an owning
  orchestrator (per the resolution above) OR the current shell is
  inside an orchestrator's tmux session (`$TMUX` matches).
- Branch:
  - Standalone: call `_layout_init` (today's path, unchanged)
  - Orch-mode: call `_layout_spawn` targeting the orchestrator session

**`lib/feature.sh`:**
- `_coda_feature_start`: resolves whether this is an orch-managed
  project. Auto-starts orch if needed. Creates window (orch-mode) or
  session (standalone).
- `_coda_feature_done` and `_coda_feature_finish`: branch on whether
  the target is a session or a window. `tmux has-window -t orch:name`
  is the probe; `tmux kill-window -t orch:name` is the action.
- Target resolution: given `<branch>`, find the window in the owning
  orchestrator's session.

**`lib/core.sh` (`_coda_ls`, `_coda_switch`):**
- Currently: `tmux list-sessions | grep ^coda-`.
- New: also list windows in every running orchestrator session.
  Format: `orch:window-name` for features, bare session name for
  standalones.
- `_coda_switch` with fzf: preview uses `tmux capture-pane -t <target>`
  which already accepts `session:window` targets -- no change there.

**`lib/project.sh` (`_coda_project_close`):**
- Needs to kill orchestrator windows belonging to the project, not
  just sessions. Inventory: list windows across all running
  orchestrator sessions, filter by whose worktree roots match this
  project root.

**`completions/coda.bash` and `completions/coda.zsh`:**
- `_coda_sessions` completion adds the orch-window targets in
  `orch:window` form (or just the window name, since that's what
  users type with `coda <name>` short-form).

### coda-orchestrator repo

**`lib/feature-hook.sh` (`_coda_feature_orch_hook`):**
- Today: creates new tmux session + starts opencode serve in a pane.
- New: creates a new window in the orchestrator session via
  `_layout_spawn`. The hook becomes much thinner -- most of the
  tmux ceremony moves into the layout.
- The agent auto-trigger (`opencode run --attach` in background)
  stays identical; only the tmux target changes.

**`lib/status.sh` (`_orch_status`):**
- Primary source becomes `tmux list-windows -t <orch-session>`
  instead of `tmux list-sessions | glob-filter`.
- Tree view: orchestrator is the root, each window is a child row.
- Legacy path retained during migration: also include top-level
  feature sessions matching old globs.

**`lib/ui.sh` (`_orch_switch`, `_orch_sessions`):**
- Enumerate windows in the orchestrator's session.
- `switch-client -t orch-session:window-name` is the attach target.
- Keyboard UX: `coda orch switch riley 92` jumps directly to window
  named `92-*`.

**`lib/send.sh`:**
- Unchanged: targets opencode servers by port, not tmux.

**`hooks/post-session-create/50-orch-notify` and
`hooks/pre-feature-teardown/50-orch-notify`:**
- These fire on session events. They need to fire on
  post-window-create / pre-window-teardown too.
- **Decision (Zach review 2026-04-19): Option A (proper hook
  events).** The hook infrastructure is already built:
  `_coda_run_hooks` supports three-tier execution (user, builtin,
  plugin), 10 hook events are registered with a mechanical pattern
  for adding new ones, and plugin hook registration via
  `plugin.json` is automatic. Only real work is the trigger call
  site: fire `post-window-create` once after `_layout_spawn` in
  `feature-hook.sh`, fire `pre-window-teardown` from
  `_coda_feature_done` before `kill-window`. Clean, minimal,
  proper.

**`scope.json`:**
- Glob-matching stays as the fallback resolution path.
- New first-class field: `scope.project` maps to a project dir; when
  `coda feature start` runs in that dir, it targets this orchestrator.
- Validation: one project should have one owning orchestrator
  (warn on conflicts).

### Session naming

Current orchestrator session: `coda-orch--<name>` (e.g. `coda-orch--riley`).

Two options for the redesign:

**A. Keep prefix:** `coda-orch--riley`. Features become windows named
`<id>-<slug>`. Users still need to know the prefix to find their orch.

**B. Shorten:** `riley` (drop `coda-orch--` prefix). Orchestrators are
now first-class names. `tmux attach -t riley` instead of
`tmux attach -t coda-orch--riley`. Much nicer at the keyboard.

**Decision (Zach review 2026-04-19): A for this redesign, B as
follow-up.** Short names are the right destination but are major
surgery -- SESSION_PREFIX is wired into completions, `_coda_ls`,
`_coda_switch`, every hook glob, and scope.json patterns. First
pass keeps the `coda-orch--` prefix. Card NEW-L stays on the
roadmap but carries a note listing every SESSION_PREFIX callsite
so the scope is concrete when we get there.

## Cross-repo coordination

Most of the work is in `evanstern/coda` (coda CLI):
- `lib/core.sh`, `lib/feature.sh`, `lib/project.sh`, completions
- The `--orch` flag that's still missing (from #26 in our repo)

The orchestrator repo changes are narrower:
- `lib/feature-hook.sh` -- thinner, invokes `_layout_spawn`
- `lib/status.sh`, `lib/ui.sh` -- window-first discovery
- Hooks for window events

This calls for escalation to Zach. Neither I nor coda-core should
land half of this unilaterally. The design doc + card set goes to
Zach first; he routes the coda CLI pieces.

## Migration strategy

Incremental, opt-in initially:

1. **Phase 1 (coda CLI):** implement window-mode in `_coda_attach` and
   `_coda_feature_start`, gated behind an opt-in flag `--orch-window`
   or env `CODA_ORCH_WINDOW_MODE=1`. Existing behavior unchanged when
   off.
2. **Phase 2 (coda-orchestrator):** update `feature-hook.sh` to use
   the new window-mode path when `CODA_ORCH_WINDOW_MODE=1`. Discovery
   and teardown paths already read both old and new targets.
3. **Phase 3:** flip the default. Window mode is now the default;
   legacy session mode is the opt-out (`--orch-session` or
   `CODA_ORCH_WINDOW_MODE=0`).
4. **Phase 4:** remove the session-per-feature code path once no
   orchestrators rely on it. Drop the opt-out.

Old top-level feature sessions continue to be recognized and torn down
throughout phases 1-3. Nothing breaks.

## Open questions

- **Layout defaults per feature window.** Today every feature session
  gets the same minimal `opencode serve` setup. If the feature window
  can use any configured layout (`four-pane`, etc), should feature
  windows default to a specific "feature layout" or follow the
  orchestrator's `.coda.env` setting?
- **remain-on-exit for completed features.** When the opencode serve
  in a feature window exits (e.g. user stops it), should the window
  auto-close, or should it persist with "Process exited" visible? The
  tmux `remain-on-exit` option supports this. Recommendation:
  auto-close by default; users can run `coda feature done` to tear
  down, or just `ctrl+d` in the window.
- **Multi-user attach.** tmux allows two clients on the same session
  viewing different windows independently -- great for pair work.
  Does anything coda-specific need adjusting for this? Probably not;
  it's mostly UX documentation.
- **Zombie serves.** The snapshot found a detached opencode serve
  from a deleted worktree. Not specific to this design, but the
  window-model makes orphans easier to clean (killed with the
  window).

## Card set (post Zach review)

Consolidated from 13 cards to 10. Rationale per card below.

**Umbrella**
- **#90** -- Design: features as orchestrator windows (this doc).
  Becomes a pinned reference; doesn't ship code.

**coda-orchestrator (my repo)**
- **#91** -- Feature-hook uses `_layout_spawn` inside orchestrator
  session. Gate behind `CODA_ORCH_WINDOW_MODE`. Back-compat
  fallback preserved.
- **#92** -- Status and switch read windows-in-session. Update
  `status.sh`, `ui.sh`. **Note:** `_orch_scoped_sessions` and
  `_orch_all_coda_sessions` are called in `ui.sh` today but
  undefined -- this card is implement-from-scratch, not an update.
- **#93** -- Window-event hooks (orchestrator side): register
  `post-window-create` and `pre-window-teardown` plugin hooks in
  `plugin.json`, wire notify scripts. Depends on #99 (coda CLI
  side) for events to fire.
- **#94** -- scope.json `project` field for orchestrator ownership
  resolution.
- **#101** -- Short session names for orchestrators. Follow-up,
  after window-mode is stable. Card carries a SESSION_PREFIX
  callsite inventory for scoping.
- **#102** -- Migration guide + test plan.

**coda CLI (coda-core's repo)**
- **#95** -- *Consolidated* `_coda_attach` + `_coda_feature_start`
  window-mode support + `--orch` flag parser (formerly #95 + #100).
  These are one PR against `feature.sh` + `core.sh`. `--orch` is
  the mechanism by which `_coda_feature_start` knows to target an
  orchestrator -- foundational, not polish. Zach review 2026-04-19.
- **#96** -- `_coda_feature_done` + `_coda_feature_finish`
  window-aware teardown.
- **#97** -- `_coda_ls`, `_coda_switch`, completions enumerate
  orchestrator windows.
- **#98** -- `_coda_project_close` cleans windows across all
  orchestrators.
- **#99** -- *Consolidated* hook events both sides: `_coda_run_hooks`
  dispatches `post-window-create` + `pre-window-teardown` from the
  feature-hook and teardown paths; pairs with orchestrator-side
  #93 which registers the plugin hooks. These land together.

**NEW (from review)**
- **#115** -- `.coda.env` supports `CODA_FEATURE_LAYOUT` override.
  Today `.coda.env` has `CODA_LAYOUT` (whole-session). Per-project
  feature layout needs a new key. Separate card, not waved --
  ships whenever it's useful.

## Sequencing (updated)

**Wave 1 (foundation, parallel-safe):**
- #90 (this doc, just land it)
- #94 (scope.json project field)
- #95 (coda CLI window-mode + --orch flag) -- escalate

**Wave 2 (depends on wave 1):**
- #91 (feature-hook uses new path)
- #96 (coda CLI teardown)
- #97 (coda CLI discovery)
- #92 (orch status + switch, with implement-from-scratch for
  undefined helpers)

**Wave 3:**
- #93 + #99 (hook events, land together)
- #98 (project close)

**Wave 4:**
- Flip default to window-mode
- #102 (migration guide)
- Eventually: drop session-per-feature path

**Unwaved / as appetite permits:**
- #101 (short session names)
- #115 (CODA_FEATURE_LAYOUT)

## Risks

- **Dual-path complexity during migration.** Code that reads both
  old and new targets is bug-prone. Aggressive test coverage needed.
- **Cross-repo ordering.** Most work is coda-side; orchestrator
  changes reference functions that must ship first in coda. Keep the
  opt-in flag until both halves are green.
- **Hook event additions.** Adding new hook events to coda CLI is
  smaller than it first looked (Zach review 2026-04-19): the
  dispatcher and 10 existing events prove the pattern. Only new
  work is the trigger call site.
- **User muscle memory.** Anyone who types
  `coda-coda-orchestrator--81-fix-send` by hand will have to relearn.
  Short names help.

## Appendix: Why this matters

The flat session list is a conceptual mismatch. The user's mental
model is hierarchical -- "riley is working on #81" -- and the tool
represents it as two sibling processes with a name convention. Every
filter, status command, scope.json glob, and parse-session-name
function exists to paper over the gap. Moving features inside the
orchestrator session makes the representation match the model.

The migration is sizeable (~30 callsites across two repos) but each
callsite is a local change, not a structural one. The layout system
already supports the window case. The opencode HTTP API doesn't care
what tmux does. The orchestrator's scope-matching becomes redundant
for feature tracking (still useful for cross-orch awareness).

This is the kind of cleanup that eliminates a whole category of
friction.
