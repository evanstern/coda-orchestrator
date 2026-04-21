# Design: Wiki as first-class memory

**Status:** Partially Implemented (PR #35, cards #104-106)
**Repo:** coda-orchestrator (soul plugin)
**Cards:** TBD (proposed in this doc)

## Problem

Orchestrators have a wiki. It's standardized, Obsidian-formatted,
already bootstrapped by `coda soul init`. Three wikis exist with
real content. But the wiki is under-used at the protocol level:

1. **No active "search the wiki" instruction in the runtime system
   prompt.** `SOUL.md.tmpl` doesn't mention wiki. The agent loads
   SOUL/MEMORY/PROJECT via `opencode.json`, but wiki is not in that
   injection. Agents default to checking `memory/` and `learnings/`,
   not the compiled layer.
2. **`boot-identity` skill does read `wiki/index.md` at step 8**, but
   it's a passive read. No "and prefer this over raw memory when
   answering" instruction.
3. **No first-class search tool.** `rg ~/.config/coda/.../wiki/`
   works, but it requires the agent to already know its CWD and the
   wiki path. It's not a named protocol.
4. **Commit whitelist excludes wiki.** `soul commit` doesn't push
   wiki changes -- they have to be committed via regular git or not
   at all.
5. **`reflect.sh` reads only last 10 pages by name-sort**, not by
   relevance. Fine for small wikis; doesn't scale.
6. **Ingest is ad-hoc.** No "compile this raw memory entry into
   wiki pages" operation. Wikis were hand-written during bootstrap.

## Proposal

Three complementary changes. None of them are big. Together they
make the wiki a protocol-level thing instead of a sometimes-thing.

### 1. Teach the template

Add wiki awareness to `SOUL.md.tmpl` and existing SOUL.md files in
two places:

**`How I Work` section:**
```
- Before answering questions about the project, check `wiki/` first.
  The compiled layer ages better than raw memory. Prefer wiki pages
  over digging through memory/ and learnings/.
```

**`References` section:**
```
- `wiki/` -- compiled project knowledge (entities, patterns, decisions,
  incidents). Start at wiki/index.md. Use `coda soul wiki search <q>`
  to find pages by keyword.
```

This lands via `opencode.json` runtime injection -- most reliable
hook, fires before the agent's first turn.

### 2. Teach the skill

Update `boot-identity/SKILL.md` step 8 from passive ("read
wiki/index.md if it exists") to active:

- Read `wiki/index.md`
- Scan page titles -- note anything relevant to current work
- When a question comes in, grep the wiki first (`coda soul wiki
  search <term>` or `rg` over `wiki/`)
- Cite wiki pages in answers where possible

Add a "Working with the wiki" section to the skill that documents
the ingest → query → lint loop per Karpathy's pattern.

### 3. Build a small search tool

Add `coda soul wiki` subcommand to the soul plugin:

```
coda soul wiki search <query>     # rg over wiki/ pages, return snippets
coda soul wiki read <page>        # cat wiki/<page>.md (tab-complete)
coda soul wiki ls [type]          # list pages, optionally filtered by type
coda soul wiki link <page>        # print the absolute path for linking
```

Implementation: thin wrapper around `rg` and `find`. No indexing,
no embeddings -- at current scale (largest wiki is 10 pages) brute
force is instant. If the wiki grows 100x, revisit.

Optional (stretch, separate card): expose via MCP as
`coda_soul_wiki_search`, `coda_soul_wiki_read` so the tool belt
surfaces them natively.

### 4. Fix the commit whitelist

One-line: add `wiki/` to the whitelist in `plugins/soul/lib/commit.sh`.
`soul commit` then pushes wiki changes.

### 5. Ingest loop (the Karpathy half)

This is the biggest piece. An explicit workflow that reads raw
memory and proposes wiki pages to create/update.

Two implementations possible:

**Option A: Extend existing `/reflect`**
- `reflect.sh` already reads the wiki. Add an explicit "proposed
  wiki updates" section to its output.
- Agent reviews proposals, writes pages, commits.
- Triggered manually by user or agent (`/reflect`).

**Option B: New `/compile-wiki` skill**
- Dedicated command that scans memory/ and learnings/ since the
  last wiki update, synthesizes page updates, writes them.
- More focused than reflect. Can run on a schedule.

Recommend Option A for minimum cost -- reflect already has the
read side. Ingest is a natural output. A new skill can come later
if usage demands it.

## Why this is cheap

- Wiki structure already exists and is consistent
- `boot-identity` already reads the index
- `reflect.sh` already reads the pages
- `rg` is already installed
- Template update is three lines
- Commit whitelist is one line
- `coda soul wiki` is maybe 50 lines of bash

The design is mostly **protocol and naming**, not infrastructure.
The infra is already there.

## Karpathy pattern alignment

Our existing structure maps cleanly to Karpathy's three layers:

| Karpathy | Ours |
|---|---|
| Layer 1: Raw sources (`raw/`) | `memory/`, `learnings/`, `dreams/` |
| Layer 2: Wiki (compiled) | `wiki/` (entities, decisions, patterns, incidents) |
| Layer 3: Schema (workflow) | `SOUL.md`, `boot-identity` skill |

The Karpathy query flow ("read index.md → identify relevant pages
→ synthesize answer with citations") maps to the "search wiki first"
protocol this design proposes.

We diverge from Karpathy's layout on source structure (he uses
`raw/articles/...` for external input; we use `memory/YYYY-MM-DD.md`
for our own observation log). But the compile-and-prefer-compiled
logic is the same.

See `~/.focus/kanban/zach-wiki-compiled-knowledge-layer-over-raw-memory-karpathy-llm-wiki-pattern.md`
(card #86, parked) for Zach's original framing.

Reference implementations for the tooling:
- `lucasastorian/llmwiki` -- web UI + MCP integration
- `Astro-Han/karpathy-llm-wiki` -- Agent Skills format
- `kytmanov/obsidian-llm-wiki-local` -- local-first, Ollama-backed

We don't need to copy any of them. Our scope is smaller --
orchestrator-scoped wikis, not a general PKM system.

## Open questions

- **Cross-wiki search.** Should riley be able to search zach's wiki?
  Sometimes yes (learn from another orch's accumulated knowledge).
  Sometimes no (zach's wiki is his operational notes; privacy isn't
  the concern but noise is).
  - Recommendation: default to own wiki; `--all` flag to search
    across. Low priority.
- **Backlinks / "Referenced by" sections.** Obsidian builds these
  visually but our text access doesn't see them. Worth generating a
  backlink index on `soul commit`?
  - Probably yes but small card of its own.
- **Tag indexes.** All pages have tags in frontmatter; no
  tag-aggregated view exists. Easy to generate.
- **Wiki linting.** Karpathy's pattern includes a "lint" step
  (find contradictions, orphan pages, missing cross-refs). Useful
  but separate concern.
- **Where `coda soul wiki` lives.** Soul plugin owns it. But coda
  CLI completion needs updating -- small cross-repo task or keep
  it plugin-local with `coda orch` style completion.

## Rollout

Ship in two PRs (per Zach review 2026-04-19). Back-compat is
automatic (nothing today depends on the new template lines or the
new wiki subcommand).

**PR1 -- protocol live (pure text/whitelist, ships today):**
- Card 104: SOUL.md template + existing files get wiki section
  (manual edits across 6 personalities, reviewed in-PR)
- Card 105: boot-identity skill gets active wiki-search instruction
- Card 106: commit whitelist includes wiki/

Agents can search via `rg` from day one. Card 104 copy references
path only; updated in PR2 to reference `coda soul wiki search`.

**PR2 -- tooling (new code + tests):**
- Card 107: `coda soul wiki search/read/ls/link` subcommand
- Card 108: reflect.sh emits proposed wiki updates, section first
  in output

**Later (p3, card separately as appetite permits):**
- Card 109: MCP wrapper for wiki search/read
- Card 110: backlink index generation on commit
- Card 111: cross-wiki search (`--all`, with `--all-orchs` and
  `--all-personalities` as open question)
- Card 112: wiki lint skill
- Card 113: tag-aggregated view

## Risks

- **Template drift.** SOUL.md for existing orchestrators won't
  auto-update when the template changes. Card NEW-B addresses this
  by also updating each existing SOUL.md.
- **Search noise.** At current scale (10-page max) no concern. If
  wikis grow, we may want frontmatter-aware search (prefer tag match
  over body match).
- **Protocol vs. reality.** Telling agents "search wiki first" only
  works if wikis have content. Riley's wiki is empty. Need the
  ingest loop (NEW-F) for the protocol to actually pay off for
  orchestrators that haven't bootstrapped manually.

## What success looks like

- Every new orchestrator's SOUL.md mentions wiki and the search
  command from day 1
- `boot-identity` agents scan wiki index, note relevant pages, and
  cite wiki pages in answers
- `coda soul wiki search "session-id"` returns hits across the
  orchestrator's wiki in under 50ms
- `reflect.sh` proposes wiki updates from new memory/learnings,
  the agent approves, `coda soul commit` ships them
- The "I'm digging through memory/YYYY-MM-DD.md again" pattern
  goes away -- compiled knowledge is the path of least resistance
