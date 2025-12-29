# Guide: policy (deterministic semantics)

PromiseKeeper policies are intentionally simple:
- they are persisted as plain tables (no functions),
- they avoid game/domain logic (distance, room types, etc),
- they are deterministic when possible.

## Policy table (current)

```lua
policy = {
  maxRuns = 1,
  chance = 1,
  cooldownSeconds = 0,
  retry = { maxRetries = 3, delaySeconds = 0 },
  expiry = { enabled = true, ttlSeconds = 86400 },
}
```

You can omit any fields; defaults apply.

## `maxRuns` (per promise)

`maxRuns` limits how many times a promise may successfully run its action.

- Scope: **per `promiseId`** (not per `occurranceKey`)
- Default: `1`
- Special: use a negative number for “unlimited”

Example:

```lua
policy = { maxRuns = 3 }
```

If you want “only once ever for this promise”, keep the default (`maxRuns = 1`).

## `chance` (deterministic per occurranceKey)

`chance` is a `0..1` number that decides if an occurrence is eligible.

- Scope: deterministic per (`namespace`, `promiseId`, `occurranceKey`)
- Default: `1` (always)
- No re-rolls: the same occurrence either always passes or always fails

Example:

```lua
policy = { chance = 0.25 } -- about 25% of distinct occurranceKeys will pass
```

## `cooldownSeconds` (per promise)

Cooldown is a “quiet period” after a successful action run.

- Scope: **per `promiseId`**
- Default: `0` (off)
- Only applies after a successful action run

Example:

```lua
policy = { maxRuns = -1, cooldownSeconds = 30 }
```

## `retry` (per occurranceKey, on action errors)

Retries exist for one reason: your action threw an error.

If an action errors:
- PromiseKeeper records `whyNot = "action_error"`,
- schedules a retry using an internal pacemaker (driven by `Events.OnTick`),
- retries the **last seen situation payload** (PromiseKeeper does not “re-sense” the world).

Intent: retries are for transient failures (ordering hiccups, rare engine nils, timing edges). If you regularly need to “wait until the world is ready”, model that upstream by having the situation emit later (when the `subject` is ready) instead of relying on long-running retries.

Fields:
- `retry.maxRetries` (default `3`)
  - counts failures
  - `0` means: allow the first attempt, then never retry after a failure
  - negative means: unlimited retries
- `retry.delaySeconds` (default `0`)
  - delay between attempts

Example:

```lua
policy = {
  retry = { maxRetries = 5, delaySeconds = 10 },
}
```

Disable retries:

```lua
policy = {
  retry = { maxRetries = 0 },
}
```

## `expiry` (safety valve)

Expiry is not “delete the promise”. It is a pruning safety valve for long-lived promises with *very chatty* situation streams.

Current behavior:
- only prunes when there are **more than 1000 unfulfilled occurrences** recorded for a promise,
- only prunes occurrences (not the definition),
- only prunes occurrences older than `ttlSeconds`,
- `enabled = false` disables pruning.

Example:

```lua
policy = {
  expiry = { enabled = true, ttlSeconds = 86400 }, -- 1 day
}
```
