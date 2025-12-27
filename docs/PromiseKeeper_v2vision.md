Document date: 2025-12-27

# PromiseKeeper — v2 Vision (Outline)

This document is an outline for PromiseKeeper v2: a durable, idempotent action scheduler for Project Zomboid mods.

It is intentionally short and decision-oriented. It is not a full spec.

Related:
- v1 intent: `external/PromiseKeeper/docs/PromiseKeeper_deferred_spawning_system.md`

---

## 0) North Star

PromiseKeeper helps mod authors express **durable reactions**:

> “When *this* becomes true / available, run *that* action, at most once (or N times), and remember across reloads.”

PromiseKeeper is **standalone**: it must work without WorldObserver.
WorldObserver integration is optional and should come via adapters.

### Contract (plain words)

You (the modder) provide:
- a stable **promiseId** (a name for this promise),
- the **action** (a function),
- a **candidateStream** (high-quality and specific: it only emits candidates that already satisfy your gate; wired from LuaEvents/Starlit or from a WorldObserver adapter),
- a **policy** (simple rules like once/N, chance, cooldown, retry delay, expiry),
- a candidate shape your action can run with: each candidate includes a stable **fulfillmentId** (so PromiseKeeper can remember it across reloads) and a **target** that is (or contains) the live, safe-to-mutate world object; if your source is not in that shape yet, you reshape it before wiring it in (for example with `map`).

PromiseKeeper provides:
- It tells you exactly what it found and where, and hands you the live, safe-to-mutate world object.
- It runs your action at the right time, and remembers what it already did across reloads so it won’t repeat unless you allow it.
- It applies your simple policies (run once / N times, retry with delay, optional expiry).
- It gives you a clear view of what’s pending vs done (and when possible, why).

---

## 1) Boundary (What PromiseKeeper Is / Isn’t)

### PromiseKeeper IS

- A **persistence-backed action scheduler** with idempotence and retries.
- A **bridge** from candidate streams (wired from LuaEvents/Starlit or WorldObserver situations) to **durable side effects**.
- A home for simple policies: “run once”, “run max N”, “chance”, “cooldown”, “retry”, “expiry/cleanup”.

### PromiseKeeper IS NOT

- A world observation engine (that is WorldObserver’s domain).
- A full workflow engine (Temporal-style); we keep the model small and practical.
- An active probing/scanning system: PromiseKeeper must not “go looking” for squares/rooms/vehicles on its own. It only consumes candidate streams delivered via LuaEvents (typically Starlit) or by optional adapters.

---

## 2) Core Concepts (Vocabulary)

### Promise

The promise is the contract:

> With `promiseId`, for candidates from `candidateStream`, run `action` according to `policy`, and remember progress across reloads.

### Candidate Stream

A stream (or event source) that emits candidates for a single promise.
It should be high quality and specific (already filtered to “only things that match the gate”).

Candidate streams are not persisted.

### Candidate

One item emitted by a candidateStream.
It must carry a stable `fulfillmentId` (so PromiseKeeper can “check it off”), and the mutatable `target` handed to the action.

### Gate

In v2, PromiseKeeper does not re-check semantic gates on candidates.
The candidateStream is responsible for only emitting candidates that already match the modder’s gate.

PromiseKeeper only performs a minimal readiness check:
- “is the target available now and safe to mutate?”

PromiseKeeper should avoid making “game logic” decisions (like distances, complex world queries, or classification logic). Those belong in the upstream candidateStream (for example in WorldObserver Situations) or to the action itself.

### Policy

PromiseKeeper policies are intentionally simple and non-game-logicy:
- run count (“only once” / “up to N times”)
- chance (“only sometimes”)
- cooldown (“not too often”)
- retry (max retries + delay)
- expiry (optional pruning)

### Action

A user callback that performs the side effect.
It must be safe under retries and is called in an error envelope.

### Action Context

When PromiseKeeper calls an action, it must provide enough context that the action does not need to do much if anything to “sense the world” or warm up objects.

The action context should answer:

1) **What can I safely mutate right now?** (the live world object/ref, “it’s there”)
2) **Why am I being called?** (what upstream condition made this candidate appear, “it’s now”)
3) **What is the stable identity?** (the `promiseId` + `fulfillmentId` that make “only once” meaningful across reloads)
4) **What helpful extra context is available?** (optional convenience handles like player/coords, as available)

---

## 3) Design Goals (v2)

- **Correctness first**
  - Stable idempotence keys
  - Explicit retry + failure recording behavior
- **Standalone usability**
  - Works with only LuaEvents + optional adapters (e.g. WorldObserver)
  - Good debugging surface (“why didn’t it fire?”)
- **Low coupling**
  - No dependency on WorldObserver; integration via adapter modules only
  - Candidate streams are pluggable
- **Performance by default**
  - Fast by default: it never scans.
  - Lean and simple; it relies on upstream systems to keep candidate streams cost-bounded
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
- `debug/*.lua` (introspection / dumps / reasons)

**Ingress/adapters:**
- PromiseKeeper consumes candidate streams wired via **LuaEvents** (typically Starlit).
- `adapters/worldobserver.lua` (first-class optional ingest): WorldObserver can publish into LuaEvents as a shared interface, or call PromiseKeeper directly.
  - Why this is good: adapters can offer subscribe/unsubscribe, so PromiseKeeper can stop fulfilling when a promise is complete, expires, or is manually stopped.
  - Adapters also provide a natural place to reshape situation emissions into PromiseKeeper candidates (for example with `:map(...)`).

Desired dependency direction:
`ingress/adapters` → `router` → `store`

---

## 5) The Key v2 Decisions (Checklist)

These should be answered early and documented as choices.
Current status: decisions are mostly settled.

- [x] **Catch-up semantics:** promises are future-based; PromiseKeeper does not scan and does not fulfill at registration time.
  - Commentary: if catch-up/backfill is desired, the candidateStream provider must replay or re-emit candidates.
- [x] **Ingress contract:** minimum candidateStream requirements are strict and simple.
  - Commentary: each candidate must include `fulfillmentId` and a non-nil `target`; otherwise PromiseKeeper warns and drops it.
  - Commentary: duplicates are expected; idempotence handles them (default is “only once per fulfillmentId”).
  - Commentary: candidateStream must support unsubscribe; if the source is a LuaEvent, PromiseKeeper can remove its handler.
  - Commentary: PromiseKeeper keeps logging/diagnostics minimal; producers don’t need to attach extra debugging fields.
  - Commentary: if hydration is needed, do it upstream in the candidateStream (for example via `:map(...)`); PromiseKeeper itself does not “sense the world”.
  - [ ] @TODO: Re-check the ingress contract after the first implementation spike (especially unsubscribe and hydration patterns).
- [x] **Fulfillment identity:** use stable ids produced by the candidateStream (for example WorldObserver keys), avoid a second PromiseKeeper-specific key taxonomy.
  - Commentary: if a candidate has no `fulfillmentId`, PromiseKeeper warns and drops it.
- [x] **Retry policy:** max retry count + delay between retries.
- [x] **Cleanup/expiry:** only expire when:
  - there are more than 1000 unfulfilled items, and
  - the item is older than 1 in-game day by default.
  - Modders can turn expiry off per promise, or change TTL.
- [x] **Budgets:** decision (for now): no. PromiseKeeper stays simple and relies on upstream systems to keep candidate streams cost-bounded.
- [x] **Reset/forget:** resetting progress is explicit via `PromiseKeeper.forget(promiseId)`; it never happens implicitly in `fulfill(...)`.

---

## 6) Public API (Proposed)

New target API: a single universal primitive that consumes a candidate stream.

- `PromiseKeeper.fulfill(promiseId, candidateStream, action, policy)`
  - This is the promise: “with this id, for these candidates, I will run this action, following this policy”.
  - `candidateStream` is high-quality and specific: it only emits candidates that are already acceptable for this promise.
- `PromiseKeeper.forget(promiseId)`
  - Explicitly forget progress for this promise id (opt-in reset). This is never implicit in `fulfill(...)`.
- `getStatus(promiseId)` / `debugDump()` / `whyNot(promiseId, fulfillmentId)` (diagnostics)

Notes:
- v1 API names (`registerFulfiller`, `ensureAt`, `ensureMatchingForSquare`) are considered legacy and will be removed in v2 without compatibility or shims.

### Candidate shape (conceptual)

Each emitted candidate should include:
- `fulfillmentId` (stable identity across reloads)
- `target` (the mutatable world object handed to `action`)
- any additional fields are optional and may be passed through as action context

If `fulfillmentId` or `target` is missing or nil, PromiseKeeper warns and drops the candidate.

---

## 7) Context (v1 vs v2)

In v1, PromiseKeeper used a `SquareCtx`-style context object as the primary input.

In v2, we want a more flexible system:
- Candidates may carry different payload shapes depending on the upstream source.
- PromiseKeeper must still be reliable for the action: when it runs your action, it must hand you the mutatable target and enough “what/where/why” context to act without sensing.

Avoid: pushing a growing taxonomy of “ctx types” into mod-facing code.

---

## 8) WorldObserver Integration (Optional Adapter)

WorldObserver can provide powerful Situation streams, but PromiseKeeper should only consume them by mapping them into a PromiseKeeper candidateStream.

Adapter responsibilities:
- Subscribe to a WO stream/situation
- Map each emission to:
  - a stable `fulfillmentId` (for idempotence), and
  - a direct `target` reference, or enough information to safely rehydrate it later
- Push into PromiseKeeper router as a candidate

PromiseKeeper core should not import WO modules.

---

## 9) Testing Strategy (v2)

- Unit-test store invariants (idempotence, merge rules, serialization safety).
- Unit-test router with synthetic candidates (no engine required).
- Provide one “PZ smoke” script that simulates minimal engine globals and validates requires + basic execution envelopes.

---

## 10) Milestones (Suggested)

1) **Router split**: replace `square_events.lua` with `router.lua` + LuaEvents-driven ingress
2) **Catch-up/backfill**: clarify “no sweeps” and “no live fulfillment at registration time”, and document adapter-driven backfill/replay
3) **Cleanup/expiry**: implement pruning + TTL
4) **Policies**: run once/N, chance, cooldown, retry delay
5) **Adapters**: WorldObserver adapter (and LuaEvents patterns)

---

## 11) Glossary

- `promiseId`: Stable name for a promise (“the rule”), chosen by the modder.
- Promise: The contract “for candidates from `candidateStream`, run `action` according to `policy`”.
- `candidateStream`: A stream/event source that emits candidates for a single promise. It should be high-quality and already filtered to match the gate.
- Candidate: One emitted item that PromiseKeeper may act on.
- `fulfillmentId`: Stable identity for a candidate/target within a promise, used so PromiseKeeper can “check it off” and not redo it after reload.
- `target`: The live, safe-to-mutate world object handed to the action.
- `action`: The modder’s function that performs the side effect.
- `policy`: Simple rules about “how” to run: once/N, chance, cooldown, retry delay, expiry.
- `PromiseKeeper.forget(promiseId)`: Explicitly forget stored progress for a promise id.
- Adapter: A bridge that turns some external stream (for example a WorldObserver Situation stream) into a PromiseKeeper candidateStream (often reshaping emissions via `map`).
