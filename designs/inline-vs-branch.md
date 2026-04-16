# Inline vs. Branch Decision Framework

Before making any change, check this table. **When unsure, branch.**

## Decision Table

| Change Type | Inline OK? | Examples |
|---|---|---|
| Daily memory files | Yes | `memory/YYYY-MM-DD.md` |
| Learnings files | Yes | `learnings/YYYY-MM-DD.md` |
| MEMORY.md updates | Yes | Curating patterns from daily files |
| `/reflect` proposals | Yes | Proposing (not applying) evolved identity changes |
| Status responses | Yes | `/status`, `/memory`, `/soul`, `/scope` |
| SOUL.md (any section) | **No — branch** | Even Evolved Identity after approval |
| AGENTS.md | **No — branch** | Agent behavior, protocols, capabilities |
| PROJECT.md | **No — branch** | Project definition, goals |
| scope.json | **No — branch** | Watch/ignore patterns |
| designs/ | **No — branch** | Design docs, decision frameworks |
| Config / structural files | **No — branch** | `plugin.json`, `opencode.json`, hooks, lib |

## Quick Rule

```
Is it observational or ephemeral?  →  Inline
Does it change how the system works? →  Branch
Not sure?                            →  Branch
```

## Why

Inline changes bypass PR review. Structural changes — even small ones — can drift the system without anyone noticing. Branching ensures a second pair of eyes via `coda feature` and PR review.
