# Quickstart (PromiseKeeper in 5 minutes)

PromiseKeeper has two common “paths”:
- **Standalone:** your situations come from Engine `Events.*` or Starlit `LuaEvent`.
- **With WorldObserver:** your situations come from `wo.situations` (recommended when you already use WO for sensing).

## Example A — Standalone (PZ event)

Goal: run an action once when we have a player (using `Events.OnTick` as the situation source).

Copy/paste (Project Zomboid debug console, in-game):

```lua
local PromiseKeeper = require("PromiseKeeper")
local pk = PromiseKeeper.namespace("MyMod")

-- 1) Define a situation (where situations come from)
pk.situations.defineFromPZEvent("onTickPlayer", Events.OnTick, function(situationArgs)
  local player = getPlayer()

  if not player then return nil end

  -- occurranceKey is how PromiseKeeper remembers “we already acted on this”.
  return {
    occurranceKey = tostring(situationArgs.keyPrefix or "player:") .. tostring(player:getPlayerNum() or 0),
    subject = player,
  }
end)

-- 2) Define an action (what to do)
pk.actions.define("logTick", function(subject, actionArgs, promiseCtx)
  print(("[PK] tick note=%s occurranceKey=%s subject=%s"):format(
    tostring(actionArgs.note),
    tostring(promiseCtx.occurranceKey),
    tostring(subject)
  ))
end)

-- 3) Declare the promise (tie situation → action with a policy)
local promise = pk.promise({
  promiseId = "logTickOnce",
  situationKey = "onTickPlayer",
  situationArgs = { keyPrefix = "player:" },
  actionId = "logTick",
  actionArgs = { note = "once" },
  policy = { maxRuns = 1, chance = 1 },
})
```

Cleanup (still in console):

```lua
promise.forget() -- stop + reset stored progress (good for iteration)
```

## Example B — With WorldObserver (recommended)

Goal: run an action once when WorldObserver observes squares near the player.

Copy/paste (Project Zomboid debug console, in-game):

```lua
local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")

local namespace = "MyMod"
local pk = PromiseKeeper.namespace(namespace)
local wo = WorldObserver.namespace(namespace)

-- One-time bridge: allow PromiseKeeper to resolve situationKey from WorldObserver.
-- Typically you do this once at game startup (including after reload).
pk.situations.searchIn(WorldObserver)

-- 1) Define a WorldObserver situation (WO does sensing; PromiseKeeper has no such logic)
wo.situations.define("nearSquares", function()
  return wo.observations:squares()
end)

-- WO still needs explicit interest (what to observe + where).
local lease = wo.factInterest:declare("near", {
  type = "squares",
  scope = "near",
  highlight = true,
})

-- 2) Define an action (subject is the full WorldObserver observation)
pk.actions.define("logSquare", function(subject, _actionArgs, promiseCtx)
  local square = subject.square
  print(("[PK] square occurranceKey=%s at=%s"):format(
    tostring(promiseCtx.occurranceKey),
    tostring(square and square.tileLocation)
  ))
end)

-- 3) Declare the promise
local promise = pk.promise({
  promiseId = "logOneNearSquare",
  situationKey = "nearSquares",
  actionId = "logSquare",
  policy = { maxRuns = 1, chance = 1 },
})
```

Cleanup (still in console):

```lua
promise.forget()
lease:stop()
```

## Notes

- `pk.promise(...)` starts listening right away. To resume stored promises after reload, call `pk.remember()` at game startup.
- More detail:
  - `concepts/mental_model.md`
  - `concepts/ids.md` and `concepts/glossary.md`
  - `guides/occurrance_key.md`, `guides/policy.md`, `guides/lifecycle.md`

## Verified smoke examples

PromiseKeeper ships a few smoke scripts you can run from the debug console:

```lua
smoke = require("examples/smoke_pk_pz_events")
handle = smoke.start()
handle.stop()
```

```lua
smoke = require("examples/smoke_pk_luaevent")
handle = smoke.start()
handle.fire("hello")
handle.stop()
```

```lua
smoke = require("examples/smoke_pk_worldobserver")
handle = smoke.start()
handle.stop()
```
