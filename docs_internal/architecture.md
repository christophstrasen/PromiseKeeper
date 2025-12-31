# PromiseKeeper — Architecture (current)

This document describes the **current implemented** PromiseKeeper architecture and how modules fit together.

## Conceptual flow

1) At game startup (including after reload), a mod registers actions and situations in a **namespace**.
2) A mod declares one or more **promises** (definitions are persisted) at any time.
3) At game startup, `pk.remember()` re-starts all persisted promises by subscribing to their situations.
4) When a situation emits an occurrence payload `{ occurranceKey, subject }`, PromiseKeeper applies policy and either:
   - runs the action and records progress (`done` for that `occurranceKey`),
   - skips with a `whyNot` reason,
   - schedules a retry in case issues are found (via the pacemaker).

## Key modules (code map)

Public entrypoint:
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper.lua`
  - Builds the namespaced `pk` handle.
  - Normalizes and persists policies.
  - Stores promise definitions and starts runtime (`router` + `pacemaker`).

Registries (in-memory definitions, namespaced):
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/registries/actions.lua`
  - `actionId -> actionFn(subject, actionArgs, promiseCtx)`.
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/registries/situations.lua`
  - `situationKey -> factoryFn(situationArgs) -> situationStream`.
  - Optional “search registry” for situations not defined in PK (currently only WorldObserver).

Runtime core:
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/core/store.lua`
  - ModData persistence for promise definitions + progress (see schema below).
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/core/router.lua`
  - Subscribes to situation streams, evaluates policy, calls actions, records progress, manages retries.
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/core/pacemaker.lua`
  - Drives retries from `Events.OnTick` by calling `Router.processRetries(nowMs)`.

Policies (pure gating helpers, used by the router):
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/policies/*.lua`
  - `chance.lua`, `cooldown.lua`, `run_count.lua`, `retry.lua`, `expiry.lua`.

Adapters (bridge “situation sources” into PK streams of occurrences):
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/adapters/pz_events.lua`
  - PZ native events (`Add`/`Remove`).
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/adapters/luaevent.lua`
  - Starlit LuaEvent (`addListener`/`removeListener`).
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/adapters/worldobserver.lua`
  - Wraps WorldObserver situation streams as PK occurrences.

Utilities / wiring:
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/factories.lua`
  - Thin helpers around adapters + occurrence shaping helpers (`makeCandidate`, `candidateOr`, …).
- `require("DREAMBase/util")`
  - Logging, event subscription helpers, safe calls, small utilities (shared across DREAM mods).
- `require("DREAMBase/time_ms")`
  - Game-time helpers (used for cooldown / retry scheduling).

Diagnostics:
- `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/debug/status.lua`
  - Status, `whyNot`, and debug dumps based on persisted progress.

## Situation stream contract

PromiseKeeper expects a “situation stream” to be a table with:
- `subscribe(onNext)` returning a subscription object with `:unsubscribe()`.

Situation streams must emit **occurrences**:

```lua
{
  occurranceKey = <stable-ish identity for idempotence>,
  subject = <what the action should mutate or act upon>,
}
```

Notes:
- PromiseKeeper does not create occurrences for you unless you use an adapter helper.
- If `occurranceKey` or `subject` is missing, PromiseKeeper warns and skips.

## Persistence schema (ModData)

Root ModData key: `PromiseKeeper`

```lua
root = {
  version = 2,
  namespaces = {
    [namespace] = {
      promises = {
        [promiseId] = {
          definition = { ... },
          progress = { ... },
        },
      },
    },
  },
}
```

Definition fields:
- `promiseId`
- `situationKey`, `situationArgs`
- `actionId`, `actionArgs`
- `policy` (expanded + scalar-only)

Progress fields (high-level):
- `status` (`active` | `stopped` | `broken`)
- `brokenReason?` (`{ code, message }`)
- `totalRuns` (per `promiseId`)
- `cooldownUntilMs` (per `promiseId`)
- `createdAtMs`
- `occurrences` (table keyed by `tostring(occurranceKey)`)

Per-occurrence fields:
- `state` (`pending` | `done`)
- `retryCounter`, `nextRetryAtMs`
- `lastWhyNot` (string code)
- `lastError` (best-effort)
- `createdAtMs`

## Diagnostics and “reason codes”

PromiseKeeper tries to keep the reason vocabulary small:
- Promise-level “broken”: persistent until the mod fixes the root cause.
- Per-occurrence `whyNot`: last reason for skipping a specific `occurranceKey`.

See `Contents/mods/PromiseKeeper/42/media/lua/shared/PromiseKeeper/debug/status.lua` for current codes.
