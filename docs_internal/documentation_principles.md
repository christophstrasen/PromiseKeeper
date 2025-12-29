# PromiseKeeper Documentation Principles

This note captures the guiding principles for **PromiseKeeper (PK)** documentation. It is intended for maintainers and contributors so new docs and examples stay coherent as the project evolves.

PromiseKeeper’s audience is **primarily beginner → intermediate Project Zomboid Lua modders** who can write `Events.*` handlers, but who don’t want to reinvent persistence, idempotence, and retry/policy logic.

## 1) Goals and audience

- **Primary audience:** modders who want reliable “do X when Y happens” with persistence across reloads.
- **Secondary audience:** advanced modders integrating with WorldObserver and/or shaping richer situation streams.
- **Goal:** make it possible to adopt PromiseKeeper by copy‑pasting one small example, then learning the model (situations → promises → actions → policy) without reading the whole codebase.

Non-goals:
- Teach ReactiveX or LQR. Only mention them when unavoidable (WorldObserver adapter).
- Teach game-domain logic (distance, room types, etc). PromiseKeeper is intentionally light on domain logic.

## 2) Layered documentation structure

Keep a clear split between stable docs and exploratory notes.

- **User-facing (stable, task-oriented)**
  - `docs_internal/vision.md` — what PK is/is-not, in plain words.
  - `docs_internal/api.md` — the *implemented* API surface with small runnable examples.
  - `docs_internal/architecture.md` — the *implemented* module layout and persistence shape (for maintainers).

- **Internal / archival**
  - `docs_internal/drafts/` — design explorations, refactor plans, historical docs, raw notes.
  - `docs_internal/brownbag.md` — catch-all for notes that aren’t ready for stable docs.
  - `docs_internal/project_history.md` — short pointers for “why is this here?” and where older docs live.

When in doubt:
- If it helps modders *use* PromiseKeeper today, it belongs in `docs_internal/api.md`.
- If it records trade-offs, history, or partial designs, it belongs in `docs_internal/drafts/`.

## 3) Content principles (PromiseKeeper-specific)

### 3.1 Start from outcomes, then reveal mechanics

PromiseKeeper docs should begin with “what you want to achieve”, for example:
- “Run an action once when a LuaEvent fires”
- “Run an action once per square (idempotent), even across reloads”
- “Retry an action a few times if it fails”

Only after the example works do we explain the machinery (namespaces, persistence, policy, retries, whyNot).

### 3.2 Keep vocabulary sticky, but don’t over-jargon

Use the shipped terms consistently:
- **namespace** — isolates mod state
- **situationKey** — where situations come from (registered situation definition)
- **promiseId** — the durable rule id
- **occurranceKey** — the durable per-occurrence id (idempotence hinge)
- **subject** — what the action receives (ideally safe to mutate)
- **policy** — deterministic gating rules (chance/cooldown/maxRuns/retry)
- **promiseCtx** — metadata passed into actions

Avoid older v1 terms in new docs (fulfillers, ensureAt, matchers) except inside archived drafts.

### 3.3 Be explicit about what PK does *not* do

Repeat this early and often:
- PK does **not** scan/probe the world to create signals.
- PK does **not** encode game/domain logic like distance ≤ 30.
- PK only performs minimal readiness checks (missing `occurranceKey` or missing `subject` → warn + skip).

### 3.4 The “occurranceKey” rule is first-class documentation

`occurranceKey` is the make-or-break concept. Docs must:
- state the rule in plain words (“identity of the thing you mean”, not “time you saw it”),
- explain collisions and consequences (idempotence means collisions suppress re-acting),
- give a few concrete recipes (square key, zombie key, event payload key),
- show anti-patterns (timestamp-as-id).

This is currently a top todo (`docs_internal/todos.md`) and should be treated as a “required doc” before expanding the API.

### 3.5 Be honest about current unknowns

PromiseKeeper touches persistence and runtime scheduling; docs must clearly mark what is verified vs not:
- multiplayer semantics (server/client responsibilities) are not fully verified yet,
- ModData persistence location and sharing rules should be documented once confirmed.

## 4) Examples and teaching style

- Prefer Project Zomboid domains only (player/square/zombie/rooms).
- Keep examples runnable and “small enough to paste”.
- Show stop/cleanup patterns early:
  - `promise.stop()` vs `promise.forget()` and what each means.
- For WorldObserver integration:
  - keep it explicit that WO is the sensing layer,
  - show `pk.situations.searchIn(WorldObserver)` as a one-time bridge,
  - avoid hiding WorldObserver behind PromiseKeeper abstractions unless the ergonomics gain is obvious.

## 5) Style and tone

- Write for modders, not framework authors.
- Use short sentences, concrete instructions, and minimal abstraction.
- Prefer a single canonical way to do a thing; mention alternatives only as an “advanced” note.

## 6) Keeping docs aligned with code

Update docs whenever any of these change:
- public API names and call signatures (`pk.situations.*`, `pk.promise`, action signature),
- policy semantics (what is deterministic, what is keyed per promiseId vs per occurranceKey),
- persistence schema (root key, definition/progress layout),
- WorldObserver integration contract (what PK expects from `WoMeta`).

If a change is subtle but important, record it in:
- `docs_internal/project_history.md` (short pointer), and/or
- `docs_internal/brownbag.md` (notes) until it deserves a stable page.

## 7) “Good citizen” checklist for new docs

Before merging a new or heavily edited PK doc:
- Does it start with a runnable outcome and minimal code?
- Does it introduce at most **one major new concept**?
- Does it use PK vocabulary consistently (namespace/promiseId/situationKey/occurranceKey)?
- Does it clearly explain cleanup (`stop` / `forget`)?
- Does it avoid leaking draft planning into stable docs?
- Is it correctly placed (stable vs `drafts`)?

