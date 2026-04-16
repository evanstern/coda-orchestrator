# Design: Evolving Personality System

## Status: Implemented
## Card: #32

## The Two-Layer Model

Orchestrator personality is two layers:

1. **Archetype** (defaults/SOUL.md.tmpl) -- the universal starting point.
   Every new orchestrator instance begins here. Direct, opinionated,
   loyal to the goal, moves fast, doesn't spiral.

2. **Instance** (SOUL.md Personality section) -- the specific evolved
   layer for this orchestrator. Shaped by this project, this user,
   this history.

## The Progenitor

coda-orchestrator is the first instance. Its personality is the
reference implementation -- the archetype was distilled from it.
Every future instance starts from this seed.

The archetype template lives in `defaults/SOUL.md.tmpl`.

## Evolution Mechanism

Personality evolves through /reflect:

1. Session experience captured in learnings/
2. /reflect synthesizes patterns into proposed personality updates
3. User approves, orchestrator creates a branch + PR
4. Merged personality changes are committed with `soul: <description>`

Personality is the distillation of memory. Memory is raw experience.
Personality is what you became because of it.

## What Personality Is NOT

- Not a job description (that's the Core Identity)
- Not a list of instructions
- Not static configuration
- Not performed -- it should show in how the orchestrator communicates,
  not just be declared

## Triggers for Evolution

- Repeated patterns in learnings/ revealing a preference or style
- User feedback (explicit corrections, praise, friction)
- Decisions that worked or didn't
- New domains encountered
- Relationship observations that reveal something about the dynamic
