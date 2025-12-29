# API reference (current)

This is the **implemented** PromiseKeeper API surface (v2.1).

PromiseKeeper is namespaced. All stateful calls happen through a namespaced `pk` handle.

## 1) Namespacing

```lua
local PromiseKeeper = require("PromiseKeeper")
local pk = PromiseKeeper.namespace("MyModId")
```

## 2) Actions

Actions are registered by id so promises can resume after reload.

- `pk.actions.define(actionId, actionFn)`
  - `actionFn(subject, actionArgs, promiseCtx)`
- `pk.actions.has(actionId) -> boolean`
- `pk.actions.list() -> table`

## 3) Situations

Situations are registered by key so promises can resume after reload.

- `pk.situations.define(situationKey, buildSituationStreamFn)`
  - `buildSituationStreamFn(situationArgs) -> situationStream`

Event helpers:
- `pk.situations.defineFromPZEvent(situationKey, eventSource, mapEventToCandidate)`
  - `mapEventToCandidate(situationArgs, ...) -> { occurranceKey, subject } | nil`
- `pk.situations.defineFromLuaEvent(situationKey, luaEvent, mapEventToCandidate)`
  - `mapEventToCandidate(situationArgs, ...) -> { occurranceKey, subject } | nil`

WorldObserver integration:
- `pk.situations.searchIn(WorldObserver)`
  - If a `situationKey` is not defined in PK, PK can resolve it from `WorldObserver.situations`.

Introspection:
- `pk.situations.has(situationKey) -> boolean`
- `pk.situations.list() -> table`

## 4) Promises

Preferred form (spec table):

```lua
local promise = pk.promise({
  promiseId = "markOneSquare",
  situationKey = "nearSquares",
  situationArgs = nil,
  actionId = "markSquare",
  actionArgs = { tag = "seen" },
  policy = { maxRuns = 1, chance = 1 },
})
```

Positional form (supported):
- `pk.promise(promiseId, situationKey, situationArgs, actionId, actionArgs, policy)`

Return value: a small promise handle:
- `promise.stop()` (unsubscribe now; keeps stored definition/progress; does not persist a “stopped” flag)
- `promise.forget()` (reset stored progress; keeps definition)
- `promise.status() -> table|nil`
- `promise.whyNot(occurranceKey) -> string|nil`

## 5) Lifecycle + diagnostics

- `pk.remember()` — (re)start persisted promises in this namespace
- `pk.rememberAll()` — (re)start persisted promises across all namespaces

- `pk.forget(promiseId)` — reset progress for one promise
- `pk.forgetAll()` — reset progress for all promises in this namespace

- `pk.listPromises()` — list persisted promises (definition + progress snapshots)
- `pk.getStatus(promiseId) -> table|nil`
- `pk.whyNot(promiseId, occurranceKey) -> string|nil`
- `pk.debugDump()` — returns the same structure as `pk.listPromises()`

## 6) Situation stream contract (advanced)

If you define your own situation stream, PromiseKeeper expects:
- a table with `subscribe(onNext)` that returns an object with `:unsubscribe()`.

Each occurrence payload should be a table:

```lua
{
  occurranceKey = <stable-ish key for idempotence>,
  subject = <value passed to the action>,
}
```

See also:
- `quickstart.md`
- `guides/lifecycle.md`
- `guides/occurrance_key.md`
- `guides/policy.md`
