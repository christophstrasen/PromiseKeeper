# Guide: persistence (ModData)

PromiseKeeper persists promises so they survive game reloads. This page explains what is stored, where it lives, and how you can reset it while developing.

For “when to call what” (startup vs in situ), see `guides/lifecycle.md`.

## Where state lives

In Project Zomboid, PromiseKeeper stores data in `ModData` under the root key:
- `ModData["PromiseKeeper"]`

This data is tied to the current save.

## What is persisted

PromiseKeeper persists:
- promise **definitions** (which `situationKey` + `actionId` + args + policy),
- promise **progress** (which `occurranceKey`s are already done, counters, cooldown, retry state),
- broken state (`brokenReason`) when a promise can’t be started on startup.

It does not persist:
- live subscriptions (those are recreated when you call `pk.remember()`),
- “stopped by `promise.stop()`” (that is runtime-only).

## High-level structure

Conceptually, the data looks like this:

```lua
ModData["PromiseKeeper"] = {
  version = 2,
  namespaces = {
    ["MyMod"] = {
      promises = {
        ["myPromiseId"] = {
          definition = {
            promiseId = "myPromiseId",
            situationKey = "nearSquares",
            situationArgs = nil,
            actionId = "markSquare",
            actionArgs = { tag = "seen" },
            policy = { maxRuns = 1, chance = 1 },
          },
          progress = {
            status = "active" | "broken" | "stopped",
            totalRuns = 0,
            cooldownUntilMs = 0,
            createdAtMs = 0,
            brokenReason = { code = "...", message = "..." } | nil,
            occurrences = {
              ["someOccurranceKey"] = {
                state = "pending" | "done",
                lastWhyNot = "..." | nil,
                retryCounter = 0,
                nextRetryAtMs = 0,
                lastError = "..." | nil,
                createdAtMs = 0,
              },
            },
          },
        },
      },
    },
  },
}
```

## Inspecting persisted state

From the debug console:

```lua
local pk = PromiseKeeper.namespace("MyMod")
print(pk.listPromises())
```

Or:

```lua
print(pk.debugDump())
```

## Resetting state (development)

### Reset progress (recommended)

Use these during iteration to avoid “already fulfilled” surprises:

- `promise.forget()` — stop + reset progress for that promise (keeps the definition)
- `pk.forget(promiseId)` — same as above
- `pk.forgetAll()` — reset progress for all promises in your namespace (keeps definitions)

### Full wipe (advanced)

If you want to remove all stored PromiseKeeper state for a save (including definitions), you currently need to delete the ModData entry.

In-game (debug console), you can do:

```lua
local root = ModData.getOrCreate("PromiseKeeper")
root.namespaces["MyMod"] = nil
```

This is intentionally “sharp”: it deletes everything for that namespace.

