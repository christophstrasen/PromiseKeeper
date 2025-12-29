# Guide: lifecycle (promise / remember / stop / forget)

PromiseKeeper has two “moments”:

1) **Game startup (including after reload):** you register situations + actions, then call `pk.remember()` to resume stored promises.
2) **In situ:** you declare promises whenever you want.

For what is persisted (and how to reset it), see `guides/persistence.md`.

## `pk.promise(...)`

`pk.promise(...)`:
- persists (or overwrites) the **promise definition** under `promiseId`,
- starts listening for situations right away by subscribing to the situation stream.

Important detail:
- Re-declaring the same `promiseId` **updates the definition** (policy/args/situation/action) without resetting stored progress.
- If you want a “clean slate”, call `pk.forget(promiseId)` first.

## `pk.remember()`

`pk.remember()` is what makes PromiseKeeper “persist across reloads”.

Call it at game startup, after you registered all `situationKey` and `actionId` definitions:

```lua
local pk = PromiseKeeper.namespace("MyMod")

-- register pk.situations.* and pk.actions.* here...

pk.remember()
```

If a persisted promise can’t be started (missing `actionId`, missing `situationKey`, invalid stream), it is marked `broken` and keeps a reason code.

## `promise.stop()`

`promise.stop()`:
- unsubscribes from the situation stream for now,
- keeps the persisted definition and progress as-is.

This is mainly useful for scripting (smoke tests, debug console) when you want to stop listening without changing stored state.

Note: `promise.stop()` is a runtime convenience. It does not persist a “stopped” flag. If you call `pk.remember()` later (or after a reload), the promise will start listening again.

## `promise.forget()` / `pk.forget(promiseId)`

`forget` is “reset progress”:
- stops listening,
- clears stored progress (`occurranceKey` history, counters, cooldown),
- clears broken state,
- keeps the promise definition (so it can be resumed later).

This is why smoke tests often call `forget()` at the end: it avoids “I already did that” surprises while iterating.

## `pk.forgetAll()` / `pk.rememberAll()`

- `pk.forgetAll()` resets progress for all promises in this namespace.
- `pk.rememberAll()` starts all persisted promises across all namespaces (mostly for tooling).

## What counts as “done”?

PromiseKeeper remembers “done” per `occurranceKey`. If your upstream emits the same `occurranceKey` again, PromiseKeeper will skip it as `already_fulfilled`.

If `policy.maxRuns` is reached, PromiseKeeper stops listening to avoid wasting upstream work.
