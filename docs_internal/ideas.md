# PromiseKeeper — Ideas (later / not yet explored)

This file is intentionally speculative. It is not a commitment.

## Ergonomics and recipes
- A “PromiseKeeper in 5 minutes” quickstart page (short mental model + 2 copy/paste recipes).
- A small recipe collection (“once per square”, “once per room”, “chance per occurranceKey”, “cooldown per promiseId”).

## Policy surface
- More explicit policy presets (`once`, `sometimes`, `cooldown`, `retry`) that expand into the current policy table.
- Better visualization of policy decisions in diagnostics (why skipped, why retried, etc).

## Action-driven deferral (powerful but tricky)

Idea: let an `action` “politely decline” to run *right now* and provide a reason, without throwing an error.
This could reduce noisy stack traces for “not ready yet” cases and improve ergonomics for event-driven situations.

Dimensions we discussed:

- **Two different meanings of “try again”**
  - **Wait for another situation emission**: do not schedule anything; rely on the situation stream to emit again.
    - This might be the *same* `occurranceKey` again (common in WO streams), or a *different* `occurranceKey`.
  - **Retry this same occurrence**: schedule another attempt for the same `occurranceKey` using the last stored candidate payload.
    - This is pinned to the same occurrence/payload (may be stale in WO contexts).

- **Events vs WorldObserver behave differently**
  - For **PZ events / LuaEvent**, “wait for next emission” can mean “never” (event may not fire again).
  - For **WorldObserver streams**, emissions typically recur; scheduling retries can create extra work and may retry stale payloads.

- **API shape: return value vs `promiseCtx` helper**
  - **Return value** (explicit contract): e.g. return `{ decision = "retry", whyNot = "...", retryAfterSeconds = 1 }`.
    - Pros: decision is visible at the callsite; fewer hidden side effects.
    - Cons: requires a “special return value” convention.
  - **`promiseCtx` method/helper** (ergonomic intent): e.g. `promiseCtx:retryAfter("not ready", 1)` / `promiseCtx:decline("impossible")`.
    - Pros: reads like intent; no special return value.
    - Cons: hidden control flow; potential for multiple/conflicting calls; `promiseCtx` stops being a plain table.

- **What we should avoid**
  - **Policy mutation from actions** (per `occurranceKey`): hard to reason about, hard to persist safely, surprising after reload.
  - Turning PromiseKeeper into a readiness discovery engine (long-running retries as a primary mechanism).

Potential safe constraints (if we implement):
- At most **one** “decision” per action call (enforced).
- Decisions only apply when the action did not throw (throw still means `action_error` retry path).
- “Retry after …” is **bounded by** `policy.retry` (budget + minimum/maximum delay clamping).
- Provide a “give up” decision only if we introduce a distinct terminal state (beyond `pending`/`done`) that does not count as a successful run.

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
