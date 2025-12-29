# IDs and keys

PromiseKeeper persists promises, so it needs **stable names**. You provide them.

## IDs you choose (stable across reloads)

- `namespace`: isolates your mod’s persisted state (usually your mod id).
- `promiseId`: the stable id of the promise (“this promise”).
- `situationKey`: the stable id of the situation definition (“where situations come from”).
- `actionId`: the stable id of the action function (“what to do”).

These are “names of things you register” and “names of promises you store”.

## The key inside each occurrence (how PromiseKeeper remembers)

A single situation (identified by its `situationKey`) can produce many occurrences over time.

Each time your situation produces an occurrence, it should include:
- `occurranceKey`: a stable key for “what this occurrence is about”.

PromiseKeeper uses `occurranceKey` to remember:
- “I already acted on this” (so it won’t do it twice after reload),
- deterministic chance (no re-rolls per key),
- retries and `whyNot` tracking per key.

Short version:
- `promiseId` identifies the promise.
- `occurranceKey` identifies what the promise should act on only once.

Practical intuition:
- If you want “once per square”, use a square key.
- If you want “once per zombie”, use a zombie key.

### Relatable examples (Project Zomboid)

Think of `situationKey` as the *name of a situation template*, and `occurranceKey` as the *identity of what this particular occurrence is about*.

Example: “zombie on fire”

- `situationKey = "zombiesOnFire"` means: “this situation stream will produce occurrences whenever it notices a zombie that is on fire”.
- If you want to act **once per zombie**, set:
  - `occurranceKey = zombieId`
  - `subject = zombie` (or the whole observation that contains the zombie)
- If the same burning zombie is observed again later, it will produce the same `occurranceKey` and PromiseKeeper will treat it as “already fulfilled”.

Example: “mark nearby squares”

- `situationKey = "nearSquares"` means: “this situation stream produces occurrences for squares near the player”.
- If you want to act **once per square**, set:
  - `occurranceKey = "sq:x..y..z.."` (or another stable square key)
  - `subject = square`

## Example

```lua
local pk = PromiseKeeper.namespace("MyMod") -- namespace

pk.situations.defineFromPZEvent("onTickPlayer", Events.OnTick, function(_args)
  local player = getPlayer()
  if not player then return nil end
  return {
    -- This is the per-occurrence identity. Collisions are expected and useful:
    -- you are saying “this occurrence is about *this player*”.
    occurranceKey = "player:" .. tostring(player:getPlayerNum() or 0),
    subject = player,
  }
end)

pk.actions.define("logTick", function(subject, _args, promiseCtx)
  print("tick for " .. tostring(promiseCtx.occurranceKey) .. " subject=" .. tostring(subject))
end)

pk.promise({
  promiseId = "logTickOnce",      -- promiseId
  situationKey = "onTickPlayer",  -- situationKey
  actionId = "logTick",           -- actionId
  policy = { maxRuns = 1 },
})
```

See:
- `concepts/glossary.md`
- `guides/occurrance_key.md`
