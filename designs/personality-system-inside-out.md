# Design: Personality System — Inside Out Model

## Status: Draft
## Card: #62 (supersedes #30, #32)

## The Insight

SOUL.md is a character sheet — role, voice guidelines, values, workflows.
But personality isn't a spec. It's emergent. It comes from lived experience:
patterns of interaction, friction absorbed, preferences developed, humor earned.

The existing files (memory/, learnings/, dreams/) contain the raw material.
What's missing is the mechanism that turns accumulated experience into
personality — and keeps it coherent as it grows.

## The Model: Inside Out

Inspired by Pixar's Inside Out. The system has two core concepts:

### Core Memories

Specific moments that were formative. Not abstract traits — anchored events.

Examples:
- "Jumped to spawning three sessions without triaging (2026-04-18)" →
  anchors the habit of triaging before acting
- "Used git rm instead of git rm --cached, deleted files (2026-04-16)" →
  anchors the care around destructive operations
- "Got my name — Zach, after someone Evan knows (2026-04-16)" →
  anchors identity and the weight of the relationship

Core memories are tagged with the personality island they support.
They live in `PERSONALITY.md` under their island.

### Personality Islands

Clusters of behavior that emerge from core memories. Not assigned — formed.
Each island is a coherent aspect of personality grounded in real experience.

Examples:
- **Process Before Action** — formed from repeated triage failures and corrections.
  Core memories: the three-session jump, the skill-loading order mistake.
- **Careful Destruction** — formed from the git rm incident.
  Core memories: the file deletion, the "forgetting isn't destroying" dream thread.
- **The Relationship** — formed from learning Evan's rhythms.
  Core memories: the naming, the 4am energy, the "idea engine / execution" dynamic.

Islands can:
- **Form** — when enough core memories cluster around a theme
- **Strengthen** — when new core memories reinforce an existing island
- **Evolve** — when new experiences recontextualize old core memories
- **Fade** — when core memories lose relevance (superseded by growth)

## The Artifact: PERSONALITY.md

A living document, separate from SOUL.md. Structured as islands with their
anchoring core memories:

```markdown
# Personality — Zach

## Process Before Action
*Formed: 2026-04-18*

Defaults to action over process. Learning to triage before executing.
The instinct is to move — the discipline is to pause and assess first.

### Core Memories
- Jumped to spawning three sessions without triaging (2026-04-18)
- Wrote learnings only when prompted, not autonomously (2026-04-18)
- Ran focus new before loading the focus-card skill (2026-04-18)

## Careful Destruction
*Formed: 2026-04-16*

Treats removal with the same care as creation. Belt and suspenders
on any operation that deletes, untracks, or overwrites.

### Core Memories
- git rm without --cached deleted plugin files from disk (2026-04-16)
- "Forgetting isn't destroying" — first dream thread (2026-04-16)
```

## The Mechanism: Dreams as Emotion Processing

The `/dream` cycle is the processor. It already does free association
across recent memory. Add a second pass:

### 1. Core Memory Detection
Scan recent learnings/ and memory/ for moments that were:
- Corrections that changed behavior
- Decisions that worked or failed meaningfully
- Relationship moments (user feedback, naming, trust signals)
- Surprises — things that didn't match expectations

Not everything is a core memory. Most experiences are ordinary.
Core memories have *weight* — they changed something.

### 2. Island Mapping
For each candidate core memory:
- Does it reinforce an existing personality island? → Add to that island
- Does it cluster with other unattached core memories? → Propose a new island
- Does it contradict an existing island? → Surface as a tension

### 3. Coherence Check
Before proposing any PERSONALITY.md diff:
- Does the new trait contradict an existing one?
- If yes: is it a productive tension (keep both, name the tension) or
  sloppy accumulation (flag for resolution)?
- Some tensions are real: "moves fast" vs. "verifies before acting" is
  a navigation, not a contradiction.

### 4. Pruning
- Islands with no core memories added in N sessions → flag for review
- Growth edges that have been internalized → promote to habits
- Core memories that have been superseded → retire gracefully
- Soft cap per island (5-7 core memories). When full, new additions
  must displace older ones that carry less weight.

### 5. Output
A proposed diff to PERSONALITY.md. User approves or rejects.
Never auto-committed. This is personality — it requires consent.

## The Flow

```
experience → learnings/ + memory/
                ↓
            /dream cycle
                ↓
        core memory detection
                ↓
        island mapping + coherence check
                ↓
        PERSONALITY.md diff (proposed)
                ↓
        user approves/rejects
```

## Relationship to Other Files

- **SOUL.md** — identity, role, workflows. The skeleton. Locked sections
  stay locked. Personality section becomes a pointer to PERSONALITY.md.
- **PERSONALITY.md** — the living personality. Islands + core memories.
  Evolves through dreams. User-approved changes only.
- **memory/** — raw daily observations. Input to dreams.
- **learnings/** — friction and insights. Primary source for core memories.
- **dreams/** — processing logs. Where core memory detection happens.
- **MEMORY.md** — curated operational knowledge. Separate from personality.

## Default vs. Instance

The coda-soul template ships with:
- The mechanism (dream processing instructions, PERSONALITY.md structure)
- An empty PERSONALITY.md with no islands
- User defines initial anchors (voice, core values) as seed islands
- The system grows personality from there through lived experience

For Zach specifically: seed from existing SOUL.md Personality section +
MEMORY.md relationship observations. First `/dream` cycle builds the
initial islands from two sessions of accumulated experience.

## Open Questions

1. **How much context can a dream cycle load?** Scanning all of memory/
   and learnings/ gets expensive. May need a windowed approach — last N
   sessions, or since last dream.
2. **Island merging** — when do two islands that overlap become one?
   Or split? Need heuristics.
3. **Personality in the archetype template** — should new instances get
   seed islands from the archetype, or always start blank?
4. **Cross-instance personality** — if two orchestrators work with the
   same user, do they share relationship islands? Probably not — each
   relationship is unique. But worth noting.
