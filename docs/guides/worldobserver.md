# Guide: WorldObserver integration

WorldObserver (WO) is the sensing layer. PromiseKeeper (PK) is the action + persistence layer.

This is the recommended pairing when:
- you already use WorldObserver to detect situations,
- you want idempotent actions that persist across reloads.

## Key idea: WO situations are already actionable

In this mode, PromiseKeeper does **not** require you to do any per-situation mapping.

- The **subject** passed into your action is the full WorldObserver observation.
- The **occurranceKey** is taken from `observation.WoMeta.occurranceKey` (or `observation.WoMeta.key`).

If `WoMeta` keys are missing, PromiseKeeper will warn and skip.

## One-time bridge: `pk.situations.searchIn(WorldObserver)`

PromiseKeeper has its own situation registry (`pk.situations.define(...)`), but it can also “search” other registries.

For WorldObserver integration, do this once at game startup:

```lua
pk.situations.searchIn(WorldObserver)
```

After that, if a `situationKey` isn’t defined in PromiseKeeper, it can be resolved from `WorldObserver.situations` instead.

## Convention: shared namespace

Use the same namespace for both modules:

```lua
local namespace = "MyMod"
local pk = PromiseKeeper.namespace(namespace)
local wo = WorldObserver.namespace(namespace)
```

## Full example (startup + in situ)

```lua
local PromiseKeeper = require("PromiseKeeper")
local WorldObserver = require("WorldObserver")

local namespace = "MyMod"
local pk = PromiseKeeper.namespace(namespace)
local wo = WorldObserver.namespace(namespace)

-- Startup (once per game startup, including after reload)
pk.situations.searchIn(WorldObserver)

pk.actions.define("markSquare", function(subject, _args, promiseCtx)
  local square = subject.square
  print(("[PK] square key=%s at=%s"):format(
    tostring(promiseCtx.occurranceKey),
    tostring(square and square.tileLocation)
  ))
end)

wo.situations.define("nearSquares", function()
  -- You can filter/derive here (this is where game logic belongs).
  return wo.observations:squares()
end)

-- WO interest is explicit (WO decides what to observe and at what cost).
local lease = wo.factInterest:declare("near", { type = "squares", scope = "near", highlight = true })

-- Resume stored promises for this namespace.
pk.remember()

-- In situ (any time at runtime): make a promise.
pk.promise({
  promiseId = "markOneSquare",
  situationKey = "nearSquares",
  actionId = "markSquare",
  policy = { maxRuns = 1, chance = 1 },
})

-- When your feature stops:
-- lease:stop()
```

## Overriding the occurranceKey (advanced)

If you want a different occurranceKey than `WoMeta.occurranceKey` provides, do it on the WorldObserver side where the situation is defined. WorldObserver provides `:withOccurrenceKey(...)` for that purpose.
