# Troubleshooting (and diagnostics)

This guide is a checklist for “nothing happens” moments and common mistakes.

## First: is the situation even firing?

### Events-only

- Does the event fire at all?
  - Add a temporary `print("event fired")` inside your mapper.
- Does your mapper return `{ occurranceKey, subject }` (not `nil`)?
- Is `occurranceKey` stable (not just a timestamp)?

### With WorldObserver

- Did you declare WorldObserver interest (`wo.factInterest:declare(...)`)?
- Are you in the correct namespace (WO + PK must match)?
- Does your WO situation return a stream that actually emits observations right now?

## Check promise status

From the debug console (or your own debug UI):

```lua
local promise = pk.promise({ ... })
print(promise.status().status)
```

Useful status fields:
- `status`: `active` | `stopped` | `broken`
- `brokenReason`: `{ code, message }` when broken
- `totalRuns`: number of successful action runs (per promise)
- `cooldownUntilMs`: non-zero when cooldown is active

Note: `stopped` usually means PromiseKeeper stopped the promise (for example because `policy.maxRuns` was reached). `promise.stop()` is a runtime unsubscribe and does not persist a stopped status.

List everything for your namespace:

```lua
pk.listPromises()
-- or:
pk.debugDump()
```

## Check “whyNot” (why was it skipped?)

If you know an `occurranceKey` you expected to run:

```lua
promise.whyNot(myOccurranceKey)
-- or:
pk.whyNot("myPromiseId", myOccurranceKey)
```

Common `whyNot` codes:
- `missing_occurrance_key`: your situation emitted no occurranceKey
- `missing_subject`: your situation emitted no subject
- `already_fulfilled`: the occurranceKey was already completed for this promise
- `max_runs_reached`: `policy.maxRuns` is reached for this promise
- `policy_skip_chance`: deterministic chance did not pass
- `policy_skip_cooldown`: promise is in cooldown
- `retry_waiting`: waiting until the next retry time
- `retries_exhausted`: too many action failures for this occurranceKey
- `action_error`: the action threw an error

## Common problems

### “I see no logs”

- Ensure you actually defined the action under the `actionId` you reference.
- Ensure you actually defined the situation under the `situationKey` you reference.
- If using `pk.situations.searchIn(WorldObserver)`, ensure you called it before `pk.remember()`.
- If using WorldObserver, ensure you declared interest and didn’t immediately stop the lease.

### “It worked once and never again”

Likely causes:
- `policy.maxRuns` is `1` (default) and the promise stopped itself after the first success.
- `occurranceKey` collided (you are intentionally idempotent per key).
- `policy.cooldownSeconds` is active.

Fix:
- set `maxRuns = -1` for “unlimited”, or increase it,
- adjust `occurranceKey` if collisions are accidental,
- remove or shorten cooldown.

### “It runs too often”

Your `occurranceKey` is unstable.

Anti-patterns:
- using timestamps
- using random numbers
- using `tostring(userdata)` as the key

See: `guides/occurrance_key.md`.

### “It doesn’t resume after reload”

Common causes:
- you didn’t call `pk.remember()` at game startup,
- the promise is `broken` because its `actionId` or `situationKey` wasn’t registered at startup.

Fix:
- register actions + situations first,
- then call `pk.remember()`.

### “It keeps retrying / spams errors”

Retries only happen when the action throws.

Fix:
- fix the action error (check the stack trace),
- or reduce/disable retries in policy:

```lua
policy = { retry = { maxRetries = 0 } }
```

## When in doubt

Run the shipped smoke examples to validate your environment:
- `examples/smoke_pk_pz_events.lua`
- `examples/smoke_pk_luaevent.lua`
- `examples/smoke_pk_worldobserver.lua`
