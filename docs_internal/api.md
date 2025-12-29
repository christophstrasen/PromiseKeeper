# PromiseKeeper — API overview (current)

This is the **implemented** PromiseKeeper API surface (v2.1).

## 1) Create a namespaced handle

```lua
local PromiseKeeper = require("PromiseKeeper")
local pk = PromiseKeeper.namespace("MyModId")
```

All persisted state is scoped under this namespace.

## 2) Actions

Actions are looked up by `actionId` so promises can resume after reload.

- `pk.actions.define(actionId, actionFn)`
  - `actionFn(subject, actionArgs, promiseCtx)`
- `pk.actions.has(actionId)` → boolean
- `pk.actions.list()` → table of actionIds

## 3) Situations

Situations are looked up by `situationKey` so promises can resume after reload.

- `pk.situations.define(situationKey, buildSituationStreamFn)`
  - `buildSituationStreamFn(situationArgs) -> situationStream`

Event helpers:
- `pk.situations.defineFromPZEvent(situationKey, eventSource, mapEventToCandidate)`
  - `mapEventToCandidate(situationArgs, ...) -> { occurranceKey, subject } | nil`
- `pk.situations.defineFromLuaEvent(situationKey, eventSource, mapEventToCandidate)`
  - `mapEventToCandidate(situationArgs, ...) -> { occurranceKey, subject } | nil`

WorldObserver integration:
- `pk.situations.searchIn(WorldObserver)`
  - One-time bridge: if a situation is not defined in PK, PK can resolve it from `WorldObserver.situations`.
  - Convention: PromiseKeeper namespace == WorldObserver situations namespace.

Introspection:
- `pk.situations.has(situationKey)` → boolean
- `pk.situations.list()` → table of situationKeys

## 4) Promises

Preferred shape:

```lua
local promise = pk.promise({
  promiseId = "markCorpseSquares",
  situationKey = "corpseSquares",
  situationArgs = nil,
  actionId = "markSquare",
  actionArgs = { tag = "seen" },
  policy = { maxRuns = 1, chance = 1 },
})
```

Positional form (supported):
- `pk.promise(promiseId, situationKey, situationArgs, actionId, actionArgs, policy)`

The returned handle contains:
- `promise.stop()`
- `promise.forget()` (reset progress; keeps definition)
- `promise.status()` (status summary)
- `promise.whyNot(occurranceKey)` (last skip reason for this occurrence)

## 5) Lifecycle helpers

- `pk.remember()` → (re)start all persisted promises in this namespace.
- `pk.rememberAll()` → (re)start all persisted promises across all namespaces.
- `pk.forget(promiseId)`
- `pk.forgetAll()`
- `pk.listPromises()` → list persisted promises (definition + progress snapshots)

Diagnostics:
- `pk.getStatus(promiseId)`
- `pk.whyNot(promiseId, occurranceKey)`
- `pk.debugDump()`

## 6) Policy table (current)

Policy values are expanded with defaults and persisted as scalar-only tables.

Top-level:
- `maxRuns` (number, default `1`) — per `promiseId` across all occurrences
- `chance` (number `0..1`, default `1`) — deterministic per `occurranceKey` (no re-rolls)
- `cooldownSeconds` (number, default `0`) — per `promiseId`

Retry:
- `retry = { maxRetries = 3, delaySeconds = 10 }` — per `occurranceKey`

Expiry (safety valve):
- `expiry = { enabled = true, ttlSeconds = 86400 }`
  - Only prunes when there are **many** unfulfilled occurrences (see router implementation).

## 7) Example: PZ event → action (standalone)

```lua
local PromiseKeeper = require("PromiseKeeper")
local pk = PromiseKeeper.namespace("MyModId")

pk.situations.defineFromPZEvent("onTickPlayer", Events.OnTick, function(args)
  local player = getPlayer()
  if not player then return nil end
  return {
    occurranceKey = tostring(args.keyPrefix or "player:") .. tostring(player:getPlayerNum() or 0),
    subject = player,
  }
end)

pk.actions.define("logTick", function(subject, args, promiseCtx)
  print(("[PK] tick key=%s note=%s subject=%s"):format(
    tostring(promiseCtx.occurranceKey),
    tostring(args.note),
    tostring(subject)
  ))
end)

pk.promise({
  promiseId = "logOnce",
  situationKey = "onTickPlayer",
  situationArgs = { keyPrefix = "player:" },
  actionId = "logTick",
  actionArgs = { note = "once" },
  policy = { maxRuns = 1, chance = 1 },
})

-- Note: `pk.promise(...)` starts the promise immediately.
-- Use `pk.remember()` at game startup to resume previously persisted promises.
```

## 8) Example: WorldObserver situation (no mapping)

Assume WorldObserver already defines a situation under the same namespace:

```lua
local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")

local namespace = "MyModId"
local pk = PromiseKeeper.namespace(namespace)
local wo = WorldObserver.namespace(namespace)

-- One-time bridge (typically at game startup).
pk.situations.searchIn(WorldObserver)

-- Define a WO situation (WO is the sensing layer; PK does not probe).
wo.situations.define("corpseSquares", function()
  return wo.observations:squares():squareHasCorpse()
end)

-- Declare interest separately (still a WO concern).
local lease = wo.factInterest:declare("corpseSquares", { type = "squares", scope = "near", highlight = true })

pk.actions.define("markSquare", function(subject, _args, promiseCtx)
  local square = subject.square
  print(("[PK] corpse square key=%s at=%s"):format(
    tostring(promiseCtx.occurranceKey),
    tostring(square and square.tileLocation)
  ))
end)

pk.promise({
  promiseId = "markCorpseSquares",
  situationKey = "corpseSquares",
  actionId = "markSquare",
  policy = { maxRuns = 1, chance = 1 },
})
-- Note: `pk.promise(...)` starts the promise immediately.
-- Use `pk.remember()` at game startup to resume previously persisted promises.
-- remember to stop the WO lease when your feature stops:
-- lease:stop()
```
