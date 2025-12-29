# Archived: older action plan / notes

> This file predates the PromiseKeeper docs cleanup. The current “must do” list is:
> - `docs_internal/todos.md`

**Reflection on `ai_feedback.md`**

The feedback feels very fair and (importantly) it describes exactly the “adoption cliff” PromiseKeeper will face:

- The smokes *do* communicate a consistent pattern (“define situation stream → define action → promise”), but a mid-level PZ modder will still feel: “this is a framework, not normal PZ event-handler code”.
- The biggest missing piece is a **mental model + lifecycle**: persistence, when work runs, what resumes on reload, what `forget()` actually does, where state lives, and what happens in MP/client/server.
- The second biggest cliff is **`occurranceKey`**: it’s central to correctness, but the rules and consequences (collisions, stability, scope) aren’t obvious.
- Third: **policy** looks promising but under-explained (semantics, what exists, what doesn’t, and what’s deterministic).
- Fourth: the **WO integration** is powerful but feels like “two layers of define + mapping”, and modders won’t know if it’s overkill or why it matters for performance.
- Strengths are also real: clean Lua, consistent structure, explicit stop/cleanup handles, and the separation of *situation* vs *action* is genuinely a good habit.

Some of the naming confusion called out there has already been improved (e.g. `situationKey`, `searchIn`, clearer smoke comments), but the core critiques still stand: docs + guidance + ergonomic defaults are now the leverage.

---

## Action plan to improve PromiseKeeper (serious, concrete, user-facing)

### 1) Documentation: “PromiseKeeper in 5 minutes” (mental model)
Add a short doc aimed at mid-level modders:
- What PromiseKeeper is (persistent idempotent rule runner) and isn’t (no scanning, no world logic).
- The lifecycle: when to call `pk.promise(...)`, when to call `pk.remember()`, what happens on reload.
- The three ids (namespace / promiseId / occurranceKey) and what each is for.
- `stop()` vs `forget()` vs `forgetAll()` (and why smokes use forget for iteration).
- A “plain PZ equivalent” section: show `Events.OnTick.Add(...)` next to the PromiseKeeper version and explain what PK adds (persistence, idempotence, retry/policy, diagnostics).

### 2) Documentation: occurranceKey guide (this is the make-or-break)
A dedicated page with:
- The *real* rule: occurranceKey should represent “the thing you mean”, not “the time you saw it”.
- Scope: uniqueness is only meaningful within `(namespace, promiseId)`; collisions there cause skipped actions.
- Recipes: squares (`squareId`), zombies (`zombieId`), rooms (`roomId`), players (stable id strategy), event payloads (when `tostring(payload)` is safe vs not).
- Anti-patterns: timestamp-as-id (turns everything into “new occurrences”, breaks idempotence, bloats persistence).

### 3) Documentation: policy semantics (with real examples)
One doc that spells out:
- `maxRuns` is per `promiseId` (current behavior), not per occurrence.
- chance is deterministic per occurrence (no re-rolls).
- cooldown is per promise.
- retry is per occurrence + pacemaker.
Then show 3–5 small recipes: “once per square”, “once per day”, “20% chance per occurrence”, “cooldown 10 minutes between successes”, “retry up to N”.

### 4) Documentation: WorldObserver integration (performance + interest)
A guide that answers:
- Why PK doesn’t “just listen directly”: WO is the sensing layer, PK is the acting/persistence layer.
- What `interest` does in plain words (“tell WO to spend effort to keep this situation fresh”) and why it’s tied to subscription.
- What needs to be true for WO → PK to work well: the situation should emit observations that include (or allow) a safe-to-mutate subject.

### 5) System: default automatic mapping for “most” WO observations (overrideable)
Implement this in the **WO adapter** (not PK core), since it’s WO-shaped knowledge:

- Provide `pk.adapters.worldobserver.mappers` (patchable table):
  - `mappers.square(observation) -> { occurranceKey, subject, observation = observation }`
  - `mappers.zombie(...)`, `mappers.player(...)`, etc for the common schemas you already have.
  - `mappers.schema(observation)` that dispatches via `observation.rxMeta.schema` when available (falls back to field detection).
- Then the common case becomes:
  - `mapWO(id, pk.adapters.worldobserver.mappers.schema, opts)`
  - Or even `mapWO(id, pk.adapters.worldobserver.mappers.square, opts)` if the situation is known to be “square”.
- Override story:
  - Per-promise override: pass a custom map fn instead of a default mapper.
  - Global override: mods can replace `pk.adapters.worldobserver.mappers.square = function(...) ... end` (fits your “patchable helpers” style).

Important constraint to document clearly:
- Default mapping can only produce a good `subject` if the WO observation actually carries a live object (e.g. `square.IsoGridSquare`, `zombie.IsoZombie`). If it doesn’t, the default mapper should either drop (with a clear whyNot) or carry the observation as extra context but still require the modder to provide a subject.

### 6) Examples beyond smokes (real gameplay examples)
Add 2–3 examples that look like modder problems:
- “Spawn loot in kitchens within radius 30, only once per room”
- “Mark corpse squares once (what you already have), but show how to act again if policy allows”
- “React once to a specific LuaEvent payload id”
These should be the “happy path copy/paste” docs, not just smoke harnesses.

### 7) Multiplayer + runtime notes (explicitly state what we know / don’t know)
The feedback is right to ask this. Even if we don’t fully solve MP now, we should:
- State where ModData lives in SP/MP (and what we *haven’t verified*).
- Recommend an initial stance (e.g. server-side actions only) and mark it as a guideline pending verification.
- Add a tiny test plan: “how to verify in MP” checklist.

### 8) Tests to support the above
Add busted tests specifically for:
- Default WO mappers: given sample WO-shaped observations, they produce stable `{occurranceKey, subject}`.
- occurranceKey collisions: show how a collision suppresses re-acting (so modders understand the consequences).
- policy determinism: same occurranceKey always same chance result.

If you want, I can turn this plan into a prioritized “next 5 PRs” breakdown (what to do first to maximize adoption).
