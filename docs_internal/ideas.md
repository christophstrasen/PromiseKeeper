# PromiseKeeper — Ideas (later / not yet explored)

This file is intentionally speculative. It is not a commitment.

## Ergonomics and recipes
- A “PromiseKeeper in 5 minutes” quickstart page (short mental model + 2 copy/paste recipes).
- A small recipe collection (“once per square”, “once per room”, “chance per occurranceKey”, “cooldown per promiseId”).

## Policy surface
- More explicit policy presets (`once`, `sometimes`, `cooldown`, `retry`) that expand into the current policy table.
- Better visualization of policy decisions in diagnostics (why skipped, why retried, etc).

## Multiplayer semantics
- Clear initial stance (server-only actions? shared ModData?).
- A verified guide for MP/client/server responsibilities.

## Durability / migration
- Optional schema versioning for persisted entries (still a hard cut by default).
- Export/import tools for debugging or admin mods.

## Alternate situation sources
- A generic “adapter registry” so `pk.situations.searchIn(...)` can support other registries beyond WorldObserver (while keeping auto-detection).

## Optional ephemeral promises
- A mode where the mod passes inline functions/streams without registering ids.
- Not resumable after reload unless the mod re-creates the promise.
