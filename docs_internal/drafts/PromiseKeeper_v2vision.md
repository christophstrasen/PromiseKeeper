Document date: 2025-12-27

# Archived: PromiseKeeper v2 vision draft (superseded)

> This document contains design exploration, draft API, and implementation planning.
> The current “clean” docs are:
> - `docs_internal/vision.md`
> - `docs_internal/architecture.md`
> - `docs_internal/api.md`

# PromiseKeeper — v2 Vision (Outline)

This document is an outline for PromiseKeeper v2: a durable, idempotent action scheduler for Project Zomboid mods.
It is intentionally short and decision-oriented. It is not a full spec.

Related:
- v1 intent: `docs_internal/drafts/PromiseKeeper_deferred_spawning_system.md`

---

## 0) North Star

PromiseKeeper helps mod authors express **durable reactions**:

> “When *this* situation arises, run *that* action, at most once (or N times), and remember across reloads.”

PromiseKeeper is **standalone**: it must work without WorldObserver.
WorldObserver integration is optional and should come via adapters.

### Contract (plain words)

You (the modder) provide:
- a stable **promiseId** (a name for this promise, within your namespace),
- an **actionId** + optional `actionArgs` (registered at startup to a function, so PromiseKeeper can resume after reload),
- a **situationKey** + optional `situationArgs` (registered at startup to rebuild the situationStream on demand),
- a **policy** (simple rules like once/N, chance, cooldown, retry delay, expiry),
- an actionable **situation candidate** shape your action can run with: each emitted situation candidate includes a stable **occurranceKey** (so PromiseKeeper can remember it across reloads) and a **subject** that is (or contains) the live, safe-to-mutate thing you want to act on; if your situationStream is not in that shape yet (common with raw events), you reshape it in the situation definition or make it ready in your action.

PromiseKeeper provides:
- It tells you exactly what it found and where, and hands you the live, safe-to-mutate subject.
- It runs your action at the right time, and remembers what it already did across reloads so it won’t repeat unless you allow it.
- It applies your simple policies (run once / N times, retry with delay, optional expiry).
- It makes no promise that every situation candidate emission will be acted upon: readiness + policy can still cause drops/skips.
- It gives you a clear view of what’s pending vs done (and when possible, why).
  - If a promise cannot be resumed (for example because a persisted definition references a missing `situationKey` or `actionId`), it is marked as broken with a clear reason.

---

## 1) Boundary (What PromiseKeeper Is / Isn’t)

### PromiseKeeper IS

- A **persistence-backed action scheduler** with idempotence and retries.
- A **bridge** from situation streams (wired from PZ Events, LuaEvent/Starlit, or optional adapters like WorldObserver) to **durable side effects**.
- A home for simple policies: “run once”, “run max N”, “chance”, “cooldown”, “retry”, “expiry/cleanup”.

### PromiseKeeper IS NOT

- A world observation engine (that is WorldObserver’s domain).
- A full workflow engine (Temporal-style); we keep the model small and practical.
- An active probing/scanning system: PromiseKeeper must not “go looking” for squares/rooms/vehicles on its own. It only consumes situation streams delivered via PZ Events, LuaEvent/Starlit, or optional adapters like WorldObserver.

---

## 2) Core Concepts (Vocabulary)

### Promise

The promise is the contract:

> With `promiseId`, for situation candidates from `situationStream`, run the action identified by `actionId` according to `policy`, and remember progress across reloads.

### Situation Stream

A stream (or event source) produced by a registered situation definition, emitting situation candidates for a single promise.
It should be high-quality and specific (already filtered to “only things that match and may be acted upon”).

Situation streams are not persisted (they are live runtime objects).
Only the *reference* to rebuild them is persisted (`situationKey` + `situationArgs`).

PromiseKeeper should support these situationStream shapes (explicit adapters are preferred):

1) **WorldObserver / Rx-style streams**
   - `situationStream:subscribe(onNext)` returns a subscription with `:unsubscribe()`.
   - Additional args like `onError` / `onCompleted` may exist, but PromiseKeeper only relies on `onNext` + `unsubscribe`.
   - If a source supports both `subscribe` and `Add/Remove`, PromiseKeeper prefers `subscribe`.

2) **PZ Events-style sources**
   - An event-like value with `Add(handler)` and `Remove(handler)`.
   - PromiseKeeper subscribes by calling `Add(handler)` and unsubscribes by calling `Remove(handler)`.
   - Use the explicit adapter `PromiseKeeper/adapters/pz_events` (or `factories.fromPZEvent`) to avoid call-style ambiguity.
3) **LuaEvent (Starlit) sources**
   - An event-like value with `addListener(handler)` and `removeListener(handlerOrToken)`.
   - PromiseKeeper subscribes via `addListener` and unsubscribes via `removeListener`.
   - Use the explicit adapter `PromiseKeeper/adapters/luaevent` (or `factories.fromLuaEvent`) to avoid token/call-style ambiguity.

### Situation Candidate

One item emitted by a situationStream.
It is an actionable “situation instance” that PromiseKeeper may attempt to act on.
It must carry a stable `occurranceKey` (so PromiseKeeper can “check it off”), and the (ideally mutatable) `subject` handed to the action.

### Gate

In v2, PromiseKeeper does not re-check semantic gates on situation candidates.
The situationStream is responsible for only emitting situation candidates that already match the modder’s gate.

PromiseKeeper only performs a minimal readiness check:
- “is the subject available now and safe to mutate?”

In practice, PromiseKeeper only checks that `subject` is present (non-nil); “safe to mutate” is primarily the situationStream’s responsibility, and failures fall under retry policy.

PromiseKeeper should avoid making “game logic” decisions (like distances, complex world queries, or classification logic). Those belong in the upstream situationStream (for example in WorldObserver situations) or to the action itself.

### Policy

PromiseKeeper policies are intentionally simple and non-game-logicy: they should not encode knowledge about Project Zomboid world objects. The simple shapes for this v2 are:
- run count (“only once” / “up to N times”)
- chance (“only sometimes”, deterministically per `occurranceKey`, no re-rolling)
- cooldown (“not too often”, scoped per `promiseId`)
- retry (max retries + delay, driven by an internal pacemaker)
- expiry (optional pruning)

Policy table schema (v2 minimal):

```lua
policy = {
	-- Total number of successful action runs allowed for this promiseId across all occurrences.
	-- Default: 1.
	maxRuns = 1,

	-- Chance threshold in [0, 1]. Deterministic per occurranceKey (no re-rolling).
	-- Default: 1.
	chance = 1,

	-- Minimum cooldown between successful action runs for this promiseId.
	-- Default: 0 (no cooldown).
	cooldownSeconds = 0,

	-- Retry behavior when the action errors.
	retry = {
		maxRetries = 3,
		delaySeconds = 10,
	},

	-- Optional pruning. Note: v2 also has global pruning heuristics; this is a per-promise override knob.
	expiry = {
		enabled = true,
		ttlSeconds = 60 * 60 * 24, -- 1 in-game day by default
	},
}
```

Time base (v2):
- For cooldowns, retry delays, and “next retry due”, PromiseKeeper uses the same game-time millis function shape as WorldObserver (`getGameTime():getTimeCalendar():getTimeInMillis()`), but implemented locally (no WorldObserver dependency).

Chance semantics (v2):
- Chance is evaluated once per `occurranceKey` (no re-rolling on duplicate emissions).
- Preferred: derive a deterministic roll from a stable hash of `namespace + promiseId + occurranceKey` and compare it to the chance threshold.
  - This avoids extra persistence while keeping behavior stable across reloads.
  - If the chance threshold changes later, the roll stays the same; only the threshold changes.
  - Suggested hash for Lua 5.1 / Kahlua: a simple 32-bit rolling hash (e.g. djb2-style) implemented with `string.byte`, `math.fmod`, and a 32-bit modulus, then `roll = hash / 2^32`.

Policy persistence constraint (v2):
- Policies must be represented as plain tables with scalar values (strings/numbers/booleans) and other plain tables.
- No functions and no userdata; if you need complex logic, put it into your action or your situation definition and keep policy as simple parameters.

### Action

A user callback that performs the side effect.
It must be safe under retries and is called in an error envelope.

For resumable promises, actions are looked up by `actionId` in an action registry.
Any `actionArgs` you provided when declaring the promise are persisted and passed to the action (as `args`) on each attempt.

Action call shape (proposed):

> `action(subject, args, promiseCtx)`

### Promise Context

When PromiseKeeper calls an action, it passes `promiseCtx` (the third argument).
It must provide enough context that the action does not need to do much if anything to “sense the world” or warm up objects.

The promise context should answer:

1) **What can I safely mutate right now?** (the live subject, “it’s there”)
2) **Why am I being called?** (what upstream condition made this situation candidate appear, “it’s now”)
3) **What is the stable identity?** (the `promiseId` + `occurranceKey` that make “only once” meaningful across reloads)
4) **What helpful extra context is available?** (optional convenience handles like player/coords, as available)

Promise context fields (v2 minimum):
- `promiseId`
- `occurranceKey`
- `actionId`
- `situationKey`
- `retryCounter`
- `policy` (the full policy table)

---

## 3) Design Goals (v2)

- **Correctness first**
  - Stable idempotence keys
  - Explicit retry + failure recording behavior
- **Standalone usability**
- Works with only PZ Events / LuaEvent sources + optional adapters (e.g. WorldObserver)
  - Good debugging surface (“why didn’t it fire?”)
- **Low coupling**
  - No dependency on WorldObserver; integration via adapter modules only
  - Situation streams are pluggable
- **Performance by default**
  - Fast by default: it never scans.
  - Lean and simple; it relies on upstream systems to keep situation streams cost-bounded
- **Completeness later**
  - Clarify the ingress contract and adapter patterns as we learn from real use-cases

Non-goals (v2):
- Cross-mod distributed consensus, networking, or server/client replication semantics.

---

## 4) Architecture Sketch

Split PromiseKeeper into “core” and “ingress/adapters”.

**Core (standalone, no external dependencies):**
- `requests_store.lua` (ModData schema + idempotence)
- `router.lua` (evaluation engine)
- `policies/*.lua` (policies: run once/N, chance, cooldown, retry, expiry)
- `actions_registry.lua` (actionId → actionFn)
- `situations_registry.lua` (situationKey → buildSituationStreamFn)
- `time.lua` (game-time millis helper; same shape as WorldObserver but implemented locally)
- `debug/*.lua` (introspection / dumps / reasons)

**Ingress/adapters:**
- PromiseKeeper consumes situation streams wired via **PZ Events** or **LuaEvent/Starlit** sources.
- WorldObserver integration uses the search bridge (`pk.situations.searchIn(WorldObserver)`), which wraps WO situation streams into candidates based on `WoMeta.occurranceKey`.
  - Why this is good: adapters can offer subscribe/unsubscribe, so PromiseKeeper can stop fulfilling when a promise is complete, expires, or is manually stopped.
  - For event sources, adapters provide the place to reshape emissions into `{ occurranceKey, subject }`.

Desired dependency direction:
`ingress/adapters` → `router` → `store`

---

## 5) The Key v2 Decisions (Checklist)

These should be answered early and documented as choices.
Current status: decisions are mostly settled.

- [x] **Catch-up semantics:** promises are future-based; PromiseKeeper does not scan and does not run actions at registration time.
  - Commentary: if catch-up/backfill is desired, the situationStream provider must replay or re-emit situation candidates.
	- [x] **Ingress contract:** minimum situationStream requirements are strict and simple.
	  - Commentary: each situation candidate must include `occurranceKey` and a non-nil `subject`; otherwise PromiseKeeper warns and drops it.
	  - Commentary: duplicates are expected; idempotence handles them (default is “only once per occurranceKey”).
  - Commentary: situationStream must support unsubscribe; for `Add/Remove` sources, PromiseKeeper removes its handler to unsubscribe; LuaEvent uses `addListener/removeListener`.
	  - Commentary: PromiseKeeper keeps logging/diagnostics minimal; producers don’t need to attach extra debugging fields.
	  - Commentary: if hydration is needed, do it upstream in the situationStream (for example via `:map(...)`); PromiseKeeper itself does not “sense the world”.
	  - [ ] @TODO: Re-check the ingress contract after the first implementation spike (especially unsubscribe and hydration patterns).
- [x] **Occurrence identity:** use stable ids produced by the situationStream (for example WorldObserver keys), avoid a second PromiseKeeper-specific key taxonomy.
  - Commentary: if a situation candidate has no `occurranceKey`, PromiseKeeper warns and drops it.
- [x] **Retry policy:** max retry count + delay between retries.
- [x] **Retry scheduling:** retries are driven by a small internal pacemaker (e.g. `Events.OnTick`), gated by “next retry due”.
  - Commentary: v2 targets `Events.OnTick` as the pacemaker.
- [x] **Chance semantics:** deterministic per `occurranceKey` (no re-rolling); derive a stable roll from `namespace + promiseId + occurranceKey` (no extra persistence required).
- [x] **Policy skip:** when policy prevents acting (cooldown/chance), PromiseKeeper logs at info level and otherwise does nothing (it waits for the next situation candidate emission).
- [x] **Cooldown scope:** cooldown is per `promiseId` (not per `subject` / per `occurranceKey`).
- [x] **Cleanup/expiry:** only expire when:
  - there are more than 1000 unfulfilled items, and
  - the item is older than 1 in-game day by default.
  - Modders can turn expiry off per promise, or change TTL.
- [x] **Budgets:** decision (for now): no. PromiseKeeper stays simple and relies on upstream systems to keep situation streams cost-bounded.
- [x] **Reset/forget:** resetting progress is explicit via `forget(promiseId)` on the namespace handle; it never happens implicitly in `promise(...)`.
- [x] **Resumable-only promises (v2):** PromiseKeeper persists *promise definitions* and resumes them after reload.
  - Commentary: this means `situationStream` and `action` must be rebuildable by id (via `situationKey` + `situationArgs` and `actionId` + `actionArgs`).
  - Commentary: an `ephemeral` mode (inline streams/actions that don’t auto-resume) may be added later, but is intentionally not part of v2.

---

## 6) Public API (Proposed)

PromiseKeeper is shared infrastructure: multiple mods may use it at the same time.
To avoid cross-mod collisions in stored state, PromiseKeeper uses a namespaced API handle (no global “current namespace”).

- `PromiseKeeper.namespace(namespace)`
  - Returns a namespaced PromiseKeeper handle. All calls on that handle store state under that namespace.
  - In the API bullets below, we call that handle `pk`.
  - Naming guidance: prefer a fully-qualified namespace (usually your mod id). In the DREAM ecosystem (see glossary), a shared `DREAM.namespaces` helper can standardize namespace allocation across modules.

- `pk.factories` / `pk.adapters`
  - Convenience references to `PromiseKeeper.factories` and `PromiseKeeper.adapters` (so smokes and mod init code stay concise).

- `pk.actions.define(actionId, actionFn)`
  - Register an action function under a stable id (required for resumable promises).
  - Note: the action function itself is not persisted; mods must register actions at startup so persisted promises can resume.
  - Note: `actionArgs` are stored per promise definition (in `pk.promise(spec)`), not in the registry.
  - Overwrite semantics: redefining the same `actionId` is allowed and logs at info level.
- `pk.actions.has(actionId)`
  - Return true/false depending on whether `actionId` is currently registered in this namespace.
  - Intention: allow mods (and PromiseKeeper diagnostics) to quickly detect missing registrations during boot and before declaring promises.
- `pk.actions.list()`
  - List known actionIds registered in this namespace.
  - Intention: support debugging and “why is this promise broken?” tooling without requiring the modder to add extra plumbing.
- `pk.situations.define(situationKey, buildSituationStreamFn)`
  - Register a situation definition (factory) under a stable id (required for resumable promises).
  - The factory returns a live situationStream that PromiseKeeper can subscribe/unsubscribe to.
  - Overwrite semantics: redefining the same `situationKey` is allowed and logs at info level.
- `pk.situations.defineFromPZEvent(situationKey, eventSource, mapEventToCandidate)`
  - Convenience helper for PZ `Events.*` sources. Produces a situationStream that emits `{ occurranceKey, subject }`.
  - `mapEventToCandidate(args, ...)` receives the promise's `situationArgs` as the first parameter.
- `pk.situations.defineFromLuaEvent(situationKey, eventSource, mapEventToCandidate)`
  - Convenience helper for Starlit LuaEvent sources. Produces a situationStream that emits `{ occurranceKey, subject }`.
  - `mapEventToCandidate(args, ...)` receives the promise's `situationArgs` as the first parameter.
- `pk.situations.searchIn(WorldObserver)`
  - One-time bridge for WorldObserver situations. PromiseKeeper can resolve `situationKey` directly from WO.
  - Resolution rule: if `situationKey` exists in `pk.situations`, it wins; otherwise fall back to WorldObserver.
  - Hard error if namespace is missing.
- `pk.situations.has(situationKey)` / `pk.situations.list()`
  - Introspection for debugging and diagnostics.
- `pk.promise(spec)` (preferred) / `pk.promise(promiseId, situationKey, situationArgs, actionId, actionArgs, policy)` (legacy positional)
  - This is the promise: “with this id, for situation candidates from this factory, I will run this action, following this policy”.
  - `spec` includes: `promiseId`, `situationKey`, `situationArgs?`, `actionId`, `actionArgs?`, `policy?`.
  - `situationArgs` and `actionArgs` may be nil (treated as `{}`).
  - The situationStream produced by the factory must be high-quality and specific: it only emits situation candidates that are already acceptable for this promise.
  - Re-register semantics: calling `promise(...)` again with the same `promiseId` updates the stored definition (factory/args/action/policy) without resetting progress; it logs at info level.
  - Returns a `promise` handle with `started`, `stop()`, `forget()`, `status()`, and `whyNot(occurranceKey)`.
- `pk.remember()`
  - (Re)start all persisted promises in this namespace by wiring their `situationKey` + `situationArgs` and `actionId` + `actionArgs`.
  - Intention: called at game startup to restore PromiseKeeper’s “keeper” behavior after reload.
  - Failure behavior: if a promise cannot be resumed (missing `actionId` / `situationKey`), mark it as broken and log; if `getDebug()` is true, also throw an error so modders see it immediately.
- `pk.rememberAll()`
  - (Re)start all persisted promises across all namespaces.
  - Intention: an opt-in “help out” tool for advanced modders (or admin mods) that want to restore other mods’ promises.
- `pk.forget(promiseId)`
  - Explicitly forget progress for this promise id (opt-in reset). This is never implicit in `promise(...)`.
- `pk.forgetAll()`
  - Forget stored progress for all promises in this namespace.
- `pk.listPromises()`
  - List all persisted promise definitions and progress in this namespace.
- `pk.getStatus(promiseId)` / `pk.debugDump()` / `pk.whyNot(promiseId, occurranceKey)` (diagnostics)
  - Diagnostics should surface stable “reason codes” (kept as a small list) so adapters can mark promises as broken in a consistent way.

Notes:
- v1 API names (`registerFulfiller`, `ensureAt`, `ensureMatchingForSquare`) are considered legacy and will be removed in v2 without compatibility or shims.

### Reason codes (v2 minimal)

`broken` (promise-level, persistent until fixed):
- `missing_action_id`
- `missing_situation_key`
- `invalid_situation_stream`
- `subscribe_failed`
- `invalid_policy`
- `moddata_corrupt`
- `interest_failed`
- `remember_failed`

`whyNot` (per occurrence or transient):
- `missing_occurrance_key`
- `missing_subject`
- `already_fulfilled`
- `max_runs_reached`
- `policy_skip_chance`
- `policy_skip_cooldown`
- `retry_waiting`
- `retries_exhausted`
- `action_error`

### Situation candidate shape (conceptual)

Each emitted situation candidate should include:
- `occurranceKey` (stable identity across reloads)
- `subject` (the mutatable thing handed to `action`)
- any additional fields are optional and may be passed through as promise context

If `occurranceKey` or `subject` is missing or nil, PromiseKeeper warns and drops the situation candidate.

---

## 7) Context (v1 vs v2)

In v1, PromiseKeeper used a `SquareCtx`-style context object as the primary input.

In v2, we want a more flexible system:
- Situation candidates may carry different payload shapes depending on the upstream source.
- PromiseKeeper must still be reliable for the action: when it runs your action, it must hand you the mutatable subject and enough “what/where/why” context to act without sensing.

Avoid: pushing a growing taxonomy of “ctx types” into mod-facing code.

---

## 8) WorldObserver Integration (Optional Adapter)

WorldObserver situations are treated as **already actionable**. PromiseKeeper consumes them directly without per-situation mapping.

Adapter responsibilities:
- Resolve a WorldObserver situation stream by `situationKey`.
- Treat each emission as the `subject` (the full observation, including multi-family).
- Use `observation.WoMeta.occurranceKey` (or `WoMeta.key`) as the `occurranceKey`.

PromiseKeeper core should not import WO modules.

Convention:
- Bridge once per namespace:
  - `pk.situations.searchIn(WorldObserver)`
- Then reference WO situations directly in promises:
  - `pk.promise({ situationKey = "corpseSquares", ... })`

---

## 9) Testing Strategy (v2)

- Unit-test store invariants (idempotence, merge rules, serialization safety).
- Unit-test router with synthetic situation candidates (no engine required).
- Provide one “PZ smoke” script that simulates minimal engine globals and validates requires + basic execution envelopes.

---

## 10) Milestones (Suggested)

1) **Router split**: replace `square_events.lua` with `router.lua` + event-driven ingress
2) **Catch-up/backfill**: clarify “no sweeps” and “no immediate action at registration time”, and document adapter-driven backfill/replay
3) **Cleanup/expiry**: implement pruning + TTL
4) **Policies**: run once/N, chance, cooldown, retry delay
5) **Adapters**: WorldObserver adapter + PZ Events / LuaEvent adapters

---

## 11) Glossary

- `namespace`: A mod-chosen name that isolates PromiseKeeper state so multiple mods can use it without collisions. Prefer a fully-qualified name (usually your mod id).
- `DREAM`: “Deterministic and REactive Authoring Modules” — a proposed loose collection of compatible modules (e.g. WorldObserver + PromiseKeeper) that can share conventions and tooling without hard dependencies.
- `DREAM.namespaces`: A proposed shared namespace registry/helper so mods can allocate namespaces consistently across modules and reduce accidental collisions.
- `PromiseKeeper.namespace(namespace)`: Return a namespaced PromiseKeeper handle (no global state).
- `pk`: A namespaced PromiseKeeper handle returned by `PromiseKeeper.namespace(namespace)`.
- `promiseId`: Stable name for a promise (“the rule”), chosen by the modder within a namespace.
- Promise: The contract “for situation candidates from a `situationStream`, run an `action` according to `policy`, and remember across reloads”.
- `actionId`: Stable name for an action function, registered at startup so PromiseKeeper can resume after reload.
- `actionArgs`: Optional action parameters persisted as part of a promise definition and passed to the action function on each attempt.
- `situationKey`: Stable name for a situation definition (stream builder), registered at startup so PromiseKeeper can resume after reload.
- `situationStream`: A live stream/event source (built by a factory) that emits situation candidates for a single promise. It should be high-quality and already filtered to match the gate.
- Situation candidate: One emitted situation instance that PromiseKeeper may attempt to act on.
- `occurranceKey`: Stable identity for a situation candidate/subject within a promise, used so PromiseKeeper can “check it off” and not redo it after reload.
- `subject`: The live, safe-to-mutate thing handed to the action.
- `action`: The modder’s function that performs the side effect (looked up by `actionId`).
- `policy`: Simple rules about “how” to run: once/N, chance, cooldown, retry delay, expiry.
- `pk.promise(spec)`: Register (or re-register) a promise in the namespace of `pk` (and return a promise handle).
- `pk.forget(promiseId)`: Explicitly forget stored progress for a promise id in the namespace of `pk`.
- Adapter: A bridge that turns external sources into PromiseKeeper situationStreams (PZ Events / LuaEvent). WorldObserver uses a search bridge (`pk.situations.searchIn`) and emits actionable observations directly.

---

## 12) Factory Helpers (Proposed, Minimal)

These are small helper builders intended to reduce boilerplate inside situation factories.
They are deliberately minimal sketches (no defensive checking).

### A) From a PZ event source (`Add`/`Remove`) to a situationStream

```lua
-- PromiseKeeper/factories.lua (sketch)
local Factories = {}

function Factories.fromPZEvent(eventSource, mapEventToCandidate)
	return {
		subscribe = function(_, onNext)
			local handler = function(...)
				onNext(mapEventToCandidate(...))
			end
			eventSource.Add(handler)
			return {
				unsubscribe = function()
					eventSource.Remove(handler)
				end,
			}
		end,
	}
end

return Factories
```

Example usage (a mod registering a situationKey):

```lua
local PromiseKeeper = require("PromiseKeeper")

local MOD_ID = "MyMod"
local pk = PromiseKeeper.namespace(MOD_ID)

pk.actions.define("logSquareLoaded", function(subject, args, promiseCtx)
	local x = subject:getX()
	local y = subject:getY()
	local z = subject:getZ()
	print(("[PK] %s square loaded at x=%d y=%d z=%d note=%s"):format(
		tostring(promiseCtx.occurranceKey),
		x,
		y,
		z,
		tostring(args.note)
	))
end)

pk.situations.defineFromPZEvent("onSquareLoaded", Events.LoadGridsquare, function(args, square)
	local x = square:getX()
	local y = square:getY()
	local z = square:getZ()
	local prefix = tostring(args.keyPrefix or "")
	return {
		occurranceKey = prefix .. ("x%dy%dz%d"):format(x, y, z),
		subject = square,
	}
end)

local promise = pk.promise({
	promiseId = "logSquaresOnce",
	situationKey = "onSquareLoaded",
	situationArgs = { keyPrefix = "sq:" },
	actionId = "logSquareLoaded",
	actionArgs = { note = "hello" },
	policy = { maxRuns = 1, chance = 0.25 },
})

pk.remember()
```

### B) From a LuaEvent source (`addListener`/`removeListener`) to a situationStream

```lua
-- PromiseKeeper/factories.lua (sketch)
function Factories.fromLuaEvent(eventSource, mapEventToCandidate)
	return {
		subscribe = function(_, onNext)
			local handler = function(...)
				onNext(mapEventToCandidate(...))
			end
			eventSource:addListener(handler)
			return {
				unsubscribe = function()
					eventSource:removeListener(handler)
				end,
			}
		end,
	}
end
```

### C) WorldObserver situations (no per-situation mapping)

PromiseKeeper treats WorldObserver situation streams as already actionable and reads `WoMeta.occurranceKey` directly.

Example usage (a mod registering a situationKey in WorldObserver):

```lua
local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")

local MOD_ID = "MyMod"
local pk = PromiseKeeper.namespace(MOD_ID)
pk.situations.searchIn(WorldObserver)
local situations = WorldObserver.situations.namespace(MOD_ID)

-- Define the WorldObserver situation once (typically at load time).
-- PromiseKeeper does not hide this step: WO remains the source of truth for situation definitions.
situations.define("nearSquares", function()
	return WorldObserver.observations:squares()
end)

pk.actions.define("markSquare", function(subject, args, promiseCtx)
	print(("[PK] %s mark square tag=%s"):format(tostring(promiseCtx.occurranceKey), tostring(args.tag)))
end)

pk.promise({
	promiseId = "markNearSquares",
	situationKey = "nearSquares",
	situationArgs = nil,
	actionId = "markSquare",
	actionArgs = { tag = "seen" },
	policy = { maxRuns = 1, chance = 1 },
})

pk.remember()
```

---

## 13) Persistence Layout (Suggested)

PromiseKeeper v2 persists promise definitions and progress in world `ModData` (serializable tables only).

Suggested top-level shape:

```lua
ModData.PromiseKeeperV2 = {
	version = 2,
	namespaces = {
		[namespace] = {
			promises = {
				[promiseId] = {
					definition = {
						situationKey = "...",
						situationArgs = { ... },
						actionId = "...",
						actionArgs = { ... },
						policy = { ... },
					},
					progress = {
						status = "active" | "broken" | "stopped",
						brokenReason = { code = "...", message = "..." } | nil,
						cooldownUntilMs = 0, -- per promiseId
						occurrences = {
							[tostring(occurranceKey)] = {
								state = "pending" | "done",
								retryCounter = 0,
								nextRetryAtMs = 0,
								lastError = nil,
							},
						},
					},
				},
			},
		},
	},
}
```

---

## 14) Implementation Plan (Draft)

This plan assumes a clean v2 implementation with minimal reuse of v1 code.
If in doubt, remove more and start fresh.

### A) Keep vs remove (v1 codebase)

Keep (with light refactor as needed):
- `PromiseKeeper/util.lua` (hash32, logging helpers, small table utils) as the base utility module.

Remove or retire as legacy (v1-specific, square-first):
- `PromiseKeeper.lua` (v1 public API: `registerFulfiller`, `ensureAt`, `ensureMatchingForSquare`)
- `square_events.lua` (v1 square-first router)
- `requests_store.lua` (v1 ModData schema)
- `registry.lua` (v1 fulfiller registry)
- `types.lua` (v1 SquareCtx types)
- `config.lua` (v1 settings tied to ensureAt)
- `test.lua` (v1 demo script)

### B) New module layout (v2)

Public API:
- `external/PromiseKeeper/Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper.lua`
  - Implements `PromiseKeeper.namespace`, `pk.promise`, `pk.remember`, `pk.forget`, etc.

Core:
- `PromiseKeeper/core/store.lua` (ModData persistence: definitions + progress, broken reasons)
- `PromiseKeeper/core/router.lua` (ingest, idempotence, policy application, action call envelope)
- `PromiseKeeper/core/pacemaker.lua` (retry scheduling, `Events.OnTick` hook, "nextRetryDue" gating)
- `PromiseKeeper/time.lua` (game millis helper; same shape as WorldObserver but implemented locally)

Registries:
- `PromiseKeeper/registries/actions.lua` (actionId -> actionFn)
- `PromiseKeeper/registries/situations.lua` (situationKey -> buildSituationStreamFn)

Policies:
- `PromiseKeeper/policies/run_count.lua`
- `PromiseKeeper/policies/chance.lua`
- `PromiseKeeper/policies/cooldown.lua`
- `PromiseKeeper/policies/retry.lua`
- `PromiseKeeper/policies/expiry.lua`

Adapters / factories:
- `PromiseKeeper/factories.lua` (fromPZEvent, fromLuaEvent)
- `PromiseKeeper/adapters/pz_events.lua` (PZ `Events.*` streams)
- `PromiseKeeper/adapters/luaevent.lua` (Starlit `LuaEvent` streams)
- `PromiseKeeper/adapters/worldobserver.lua` (wraps WO situation streams into candidates)

Debug:
- `PromiseKeeper/debug/status.lua` (reason codes, `getStatus`, `debugDump`, `whyNot`)

### C) What to implement first (order)

1) `store.lua` + schema for definitions/progress + listPromises
2) `registries/*` + `PromiseKeeper.namespace` facade
3) `router.lua` (ingest + idempotence + action call shape)
4) `policies/*` (run_count, chance, cooldown, retry, expiry)
5) `pacemaker.lua` + `Events.OnTick` hook
6) `factories.lua` + `adapters/*`
7) `debug/status.lua` + reason codes
8) Wiring + one end-to-end smoke script

### D) Busted tests (PromiseKeeper-only)

Add a dedicated test folder:
- `external/PromiseKeeper/tests/unit/`
  - Run with `busted tests` from `external/PromiseKeeper`

Suggested unit coverage:
- **store.lua**: round-trip persist shape, `listPromises`, broken reason recording, per-promise cooldown fields
- **registries/actions.lua**: overwrite logging, `hasAction`, `listActions`
- **registries/situations.lua**: overwrite logging, get/define behavior, args normalization
- **policies/chance.lua**: deterministic roll per `namespace+promiseId+occurranceKey`
- **policies/cooldown.lua**: per-promise cooldown keying
- **router.lua**: idempotence (only once per `occurranceKey`), policy skip logging, action call signature
- **pacemaker.lua**: retry scheduling with stubbed time (nextRetryDue gating)

### E) Smoke tests (runtime)

Three smoke scripts under:
- `external/PromiseKeeper/Contents/mods/PromiseKeeper/42/media/lua/shared/examples/`

1) **PZ Events smoke** (`smoke_pk_pz_events.lua`)
   - Use `Events.OnTick` or `Events.LoadGridsquare` with `pk.situations.defineFromPZEvent`
   - Register a promise + action, log once, stop.

2) **Starlit LuaEvent smoke** (`smoke_pk_luaevent.lua`)
   - Create a Starlit `LuaEvent`, trigger a few emissions
   - Ensure PromiseKeeper receives and logs them.

3) **WorldObserver smoke** (`smoke_pk_worldobserver.lua`)
   - Define a simple WO situation (e.g. `nearSquares`)
   - Call `pk.situations.searchIn(WorldObserver)` once, then promise directly by `situationKey`
   - Confirm a promise fires and logs.

### F) Open questions to resolve during planning

- None. Recent answers locked in:
  - Policy field names confirmed (`maxRuns`, `chance`, `cooldownSeconds`, `retry`, `expiry`).
  - ModData migrations: no migration, hard clear (no save-game compatibility).
