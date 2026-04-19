# Design: Session Pruning for opencode serve Instances

**Card:** #76
**Status:** Draft
**Repos:** coda-orchestrator (pruning primitives), coda (feature done wiring)

## Problem

`coda orch` runs one `opencode serve` per orchestrator on ports 4200-4220.
All instances share a single on-disk session store -- `GET /session` on any
port returns every session regardless of which port you query. Each session
has a `directory` field that scopes it to the orchestrator that created it.

Sessions accumulate without bound. One orchestrator hit 36 sessions from
repeated `orch start`, `orch send`, and `opencode run --attach` calls.
No pruning, no lifecycle management.

The store is shared, so **any pruning must filter by `directory`** or one
orchestrator will delete another's sessions.

## API Findings (opencode v1.3.17)

Verified against a live serve instance:

| Method | Path | Notes |
|--------|------|-------|
| `GET` | `/session?directory=<dir>` | Filter by orchestrator dir. Confirmed: 36 -> 4 after filter. |
| `GET` | `/session/status?directory=<dir>` | Returns in-flight sessions. Empty `{}` when idle. |
| `DELETE` | `/session/{id}?directory=<dir>` | Hard delete. Returns `true`. 404 on unknown. |
| `PATCH` | `/session/{id}` | Archive via `{time:{archived: <ts_ms>}}` (soft delete). |
| `GET` | `/experimental/session?directory=&archived=&cursor=` | Richer query with pagination. |
| `POST` | `/session/{id}/abort` | Cancel in-flight work. |
| `GET` | `/session/{id}/children` | Child/forked sessions. |

No batch-delete endpoint. Archive field is the hook for soft retention.

## Solution

Two layers:

### L1: Pruning primitive (coda-orchestrator)

New file `lib/prune.sh` with one function:

```
_orch_prune_dir <port> <directory> [--hard] [--dry-run] [--keep N] [--days D]
```

Algorithm:
1. `GET /session/status?directory=$dir` -> set ACTIVE_IDS
2. `GET /session?directory=$dir` -> list, sorted by time.updated desc
3. Walk list, classify each session:
   - In ACTIVE_IDS -> keep
   - Has parentID -> keep (child of something)
   - Within top N or newer than D days -> keep
   - Else -> candidate:
     - If `--hard` OR older than 2D days -> `DELETE /session/$id?directory=$dir`
     - Else -> `PATCH /session/$id` with `{time:{archived: <now_ms>}}`
4. Emit summary: `pruned: kept=X archived=Y deleted=Z (dir=<basename>)`

### L2: Policy hooks

**Retention defaults:**
- Keep >= 5 most-recent sessions per directory (env: `CODA_ORCH_KEEP=5`)
- Keep anything updated in last 14 days (env: `CODA_ORCH_KEEP_DAYS=14`)
- Never touch active sessions or child sessions
- Soft delete by default, hard delete for old stuff or torn-down worktrees

**Hook points:**

1. `coda orch start` -- prune on boot (background, non-blocking)
2. `coda feature done` / `feature finish` -- hard-delete sessions for the
   torn-down worktree directory
3. `coda orch prune [name]` -- manual command

## Where the Code Goes

```
coda-orchestrator/main/
  lib/prune.sh              # NEW: _orch_prune_dir
  lib/lifecycle.sh           # EDIT: _orch_start calls prune after port is up
  coda-handler.sh            # EDIT: expose `coda orch prune` command

coda/main/
  lib/feature.sh             # EDIT: _coda_feature_done calls prune for worktree dir
```

### Wiring: lifecycle.sh (_orch_start)

After serve is ready, background the prune:

```bash
(
    for i in 1 2 3 4 5; do
        curl -sf "http://localhost:$port/global/health" >/dev/null 2>&1 && break
        sleep 1
    done
    _orch_prune_dir "$port" "$dir" 2>/dev/null || true
) &
disown
```

Prune failure must never block the start.

### Wiring: feature.sh (_coda_feature_done)

After worktree remove, iterate `$ORCH_BASE_DIR/*/port` and call prune
on each live port with the worktree's directory and `--hard`:

```bash
_coda_prune_sessions_for_dir "$worktree_dir"
```

This lives in a bridge function. Check port health before hitting it.

### New command

```
coda orch prune [name]            # archive per policy (all orchs if no name)
coda orch prune <name> --hard     # delete instead of archive
coda orch prune <name> --dry-run  # list candidates without touching
```

## Directory-scoping Requirement (CRITICAL)

Every HTTP call must include `?directory=<dir>`:
- Listing: `GET /session?directory=$dir`
- Status: `GET /session/status?directory=$dir`
- Delete: `DELETE /session/$id?directory=$dir`

`_orch_prune_dir` must refuse to run if `$directory` is empty or doesn't
start with `/`.

## Edge Cases

- **Active session**: skip via /session/status check
- **Child sessions (parentID set)**: skip conservatively; they age out
  with their parent
- **Shared pool races**: two prunes can race. Idempotent by design --
  DELETE on gone session returns 404, ignored
- **Serve restart mid-prune**: orphaned HTTP call, no corruption.
  Retried on next orch start
- **Worktree dir re-used**: feature done hard-deletes history. New
  branch starts clean. Intended behavior.
- **Stale port file**: check health before hitting port

## Implementation Scope

Single feature session. Order:
1. `lib/prune.sh` + bats tests against a live port
2. Wire `coda orch start`
3. Expose `coda orch prune` command
4. Bridge in `coda/lib/` for `feature done` wiring
5. Manual verify: fresh orch -> 20 sends -> prune --dry-run -> prune -> confirm 5 remain
