# Guide: occurranceKey (idempotence)

This page is the practical playbook. For the concept overview, start with `concepts/ids.md`.

Plain guidance:
- `occurranceKey` should mean **“the identity of what this occurrence is about”**
- not “the time you saw it”.

Why you should care:
- PromiseKeeper remembers what it already did **per `occurranceKey`** (even after reload).
- Policy and diagnostics are keyed per `occurranceKey` (`chance`, retries, `whyNot`).

## Collisions (same key seen twice)

Collisions are often intentional:
- if you want “once per square”, all observations of that square should collide on the same key.

What happens:
- after the action succeeds once, the occurrence becomes `done`,
- when the same `occurranceKey` appears again, PromiseKeeper skips it as `already_fulfilled`.

If collisions are accidental (bad key), you’ll see “it only ran once”.

## Missing or unstable keys

- Missing `occurranceKey` → PromiseKeeper warns and skips (it can’t remember or apply policy safely).
- Unstable `occurranceKey` → PromiseKeeper will treat the same thing as “new” and run too often.

## Practical recipes

### PZ events: players

```lua
occurranceKey = "player:" .. tostring(player:getPlayerNum() or 0)
```

### PZ events: squares

Prefer coordinates:

```lua
occurranceKey = ("sq:x%dy%dz%d"):format(square:getX(), square:getY(), square:getZ())
```

### LuaEvent payloads

If the payload is already a stable scalar (string/number), `tostring(payload)` is fine.

If the payload is a table/userdata, extract a stable id field instead:

```lua
occurranceKey = "evt:" .. tostring(payload.id)
subject = payload
```

### WorldObserver situations (recommended pairing)

WorldObserver observations already carry stable keys in `WoMeta`.

When you use a WorldObserver situation with PromiseKeeper:
- subject is the whole observation,
- PromiseKeeper uses `observation.WoMeta.occurranceKey` (or `observation.WoMeta.key`) as the occurranceKey.

If you need a different key for a specific situation, override it where the situation is defined in WorldObserver (WO provides `:withOccurrenceKey(...)`).

## Anti-patterns (avoid these)

- timestamps (`tostring(getTimestampMs())`) → always new → runs forever
- random numbers → always new → runs forever
- `tostring(userdata)` → often unstable across reloads

## Debugging

To understand “why didn’t it run?”:

```lua
promise.status()
promise.whyNot(myKey)
pk.listPromises()
```

See also:
- `guides/troubleshooting.md`
