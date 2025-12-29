# Guide: situations from events (PZ Events and LuaEvent)

PromiseKeeper is intentionally light on world logic. For “events-only” usage, you turn an event source into a **situation**.

The key idea:
- events don’t automatically come with an idempotence key,
- PromiseKeeper needs `{ occurranceKey, subject }`,
- so your mapping function provides both.

## PZ Events (`Events.*`)

Use:

```lua
pk.situations.defineFromPZEvent(situationKey, eventSource, mapEventToCandidate)
```

Where:
- `eventSource` is a PZ event object with `Add(fn)` and `Remove(fn)`.
- `mapEventToCandidate(situationArgs, ...)` returns `{ occurranceKey, subject }` or `nil` to skip.
- `situationArgs` is whatever you pass via `pk.promise({ situationArgs = ... })` (it is persisted).

Example:

```lua
pk.situations.defineFromPZEvent("onTickPlayer", Events.OnTick, function(args)
  local player = getPlayer()
  if not player then return nil end
  return {
    occurranceKey = tostring(args.keyPrefix or "player:") .. tostring(player:getPlayerNum() or 0),
    subject = player,
  }
end)
```

## Starlit LuaEvent

Use:

```lua
pk.situations.defineFromLuaEvent(situationKey, luaEvent, mapEventToCandidate)
```

Where:
- `luaEvent` is a Starlit `LuaEvent` (supports `:addListener(fn)` / `:removeListener(fn)`).
- `mapEventToCandidate(situationArgs, ...)` returns `{ occurranceKey, subject }` or `nil`.

Example:

```lua
local LuaEvent = require("Starlit/LuaEvent")
local event = LuaEvent.new()

pk.situations.defineFromLuaEvent("myEvent", event, function(args, payload)
  return {
    occurranceKey = tostring(args.keyPrefix or "") .. tostring(payload),
    subject = payload,
  }
end)
```

## Picking a good `occurranceKey` (events)

Events don’t come with an idempotence key by default. Your mapper needs to provide one.

Read these two short pages:
- `concepts/ids.md` (what `occurranceKey` is and why it matters)
- `guides/occurrance_key.md` (recipes, anti-patterns, debugging)

## Advanced: custom situation streams

You can define a situation directly if you already have a stream-like object:

```lua
pk.situations.define("mySituation", function(situationArgs)
  return mySituationStream
end)
```

PromiseKeeper expects the stream to support:
- `subscribe(onNext)` returning an object with `:unsubscribe()`.
