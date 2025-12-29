Document date: 2025-03-01

# PromiseKeeper — Deferred Fulfilment System (v1, square-first)

PromiseKeeper lets modders declare “promises” of world changes that should occur later, once the relevant world elements (squares, rooms, vehicles in the future) are safe to mutate. Version 1 focuses on Build 42 square/room fulfilment and integrates with the external **WorldScanner** module for candidate discovery.

---

## 0) Purpose & Principles

**Goal:**  
Allow modders to queue deterministic fulfilment work (“build this prefab here”) that triggers automatically when its target comes online.

**Key principles**

* **Idempotence:** Every `(request id + target key)` is fulfilled at most once.
* **Persistence:** Requests survive reloads and are stored in world `ModData`.
* **Safety:** Fulfiller functions are wrapped; errors are logged, not rethrown.
* **Modularity:** PromiseKeeper listens to WorldScanner events instead of probing chunks directly.
* **Extensibility:** Future context types (vehicles, meta zones) can be added without altering the persistence layer.

---

## 1) Quickstart Examples

### Single known target (`ensureAt`)

```lua
local PromiseKeeper = require("PromiseKeeper")

PromiseKeeper.registerFulfiller("destroyed_lab_scene", function(ctx)
    MyPrefabs.LabScene.makeForRoomDef(ctx.target, ctx.meta)
end, "Scene")

local LabRoomDef = MyFinder.pickRoomForLab()

PromiseKeeper.ensureAt({
    id        = "intro-destroyed-lab-A",
    fulfiller = "destroyed_lab_scene",
    target    = LabRoomDef,            -- RoomDef or IsoGridSquare
    tag       = "Story",
})
```

PromiseKeeper immediately attempts to resolve the room (if already loaded) and also listens for future square/room contexts from WorldScanner.

### Matcher-driven (`ensureMatchingForSquare`)

```lua
local PromiseKeeper = require("PromiseKeeper")

PromiseKeeper.registerFulfiller("kitchen_oddity_scene", MyPrefabs.KitchenScene.makeForRoomDef, "Scene")

local function matchKitchens(squareCtx, matchParams)
    if not squareCtx.roomDef then return nil end
    if squareCtx.roomDef:getName() ~= "kitchen" then return nil end

    local chance = (matchParams and matchParams.chance) or 1.0
    if ZombRandFloat(0.0, 1.0) > chance then return nil end

    return {
        {
            key = tostring(squareCtx.roomId),
            roomId = squareCtx.roomId,
            ref = squareCtx.roomDef,
        },
    }
end

PromiseKeeper.ensureMatchingForSquare({
    id            = "global-kitchen-oddities",
    fulfiller     = "kitchen_oddity_scene",
    matchFn       = matchKitchens,
    matchParams   = { chance = 0.2 },
    maxFulfillments = 999999, -- essentially infinite
})
```

PromiseKeeper subscribes to square contexts produced by enabled WorldScanner scanners and feeds them through `matchFn`.

---

## 2) Public Surface

| Method / Property                               | Purpose                                                                    |
| ------------------------------------------------| ---------------------------------------------------------------------------|
| `registerFulfiller(name, fn, tag?)`             | Register fulfiller callbacks. Tag is informational.                        |
| `ensureAt(request)`                             | Persist a single-target promise (RoomDef or IsoGridSquare).                |
| `ensureMatchingForSquare(request)`              | Persist a matcher that evaluates each candidate square context once.       |
| `getStatus(id)` / `listDelivered(id)`           | Debug helpers (read-only copies).                                          |
| `PromiseKeeper.config`                          | Runtime-adjustable defaults (`cleanAfterDays`, `maxFulfillments`, etc.).   |

**Internal modules** (not part of public API but relevant for architecture):
`registry.lua`, `requests_store.lua`, `square_events.lua` (soon to be replaced by router), `util.lua`.

---

## 3) Data Model (Persisted)

Each promise lives in world `ModData.PromiseKeeper.requests`.

```lua
---@class PKStoredEntry
---@field id               string
---@field fulfiller        string
---@field tag?             string
---@field createdAtDays    number
---@field cleanAfterDays   number
---@field status           '"Requested"'|'"Evaluating"'|'"Fulfilled"'
---@field maxFulfillments  number
---@field fulfillments     number
---@field target           { key:string, squareId?:number, roomId?:number }
```

* `fulfillmentKey = id .. "|" .. target.key`.
* `requestsRoot.byId[id].entries[fulfillmentKey] = PKStoredEntry`.
* `requestsRoot.byId[id].delivered = { fulfillmentKey, ... }` (append-only history).

Runtime-only:

* `matchFn`, `matchParams`, and candidate refs stay in memory; they are not serialized.
* Fulfiller registry keeps `{ fn, tag }` pairs keyed by name.

---

## 4) Fulfilment Pipeline

1. **Registration**
   * `ensureAt` / `ensureMatchingForSquare` validate input and persist the request (or merge with existing entry).
   * `ensureAt` immediately attempts to resolve the target via `Fulfillment.tryFulfillNow` (uses `getCell():getGridSquare` or room square iteration) before returning.

2. **WorldScanner events**
   * PromiseKeeper depends on **WorldScanner** and enables standard scanners (`ws.square.loadEvent`, `ws.square.initialSweep`, etc.).
   * Scanners publish `SquareCtx`/`RoomCtx` via `Starlit.Events.WorldScanner.*`. PromiseKeeper registers listeners (`Starlit.Events.WorldScanner.onSquare.Add(...)`).
   * **Macro contract (Scanner → PromiseKeeper):** WorldScanner must only emit contexts that satisfy the published contract for that type (`squareId`, `roomId`, etc.). If `ref` is omitted, the context must contain enough identifiers for PromiseKeeper to re-resolve the target efficiently.

3. **Dispatch**
   * Candidate contexts pass through the PromiseKeeper router (currently `square_events.lua`, will be replaced by `router.lua`).
   * For each stored entry with matching IDs:
     * If eligible (`fulfillments < maxFulfillments`) and not yet fulfilled, execute the fulfiller inside a `pcall`.
     * On success: increment counters, append to `delivered`, log once.
     * On failure: log once per `(fulfillmentKey)`, leave status as `Requested` for future attempts.
   * **Macro contract (Matcher → PromiseKeeper):** Matchers must treat incoming contexts as read-only, return stable keys, and only yield matches that their associated fulfiller can handle. Returning an empty table means “no match.” Returning `nil` is considered a faulty matcher and triggers a debug warning.

4. **Cleanup**
   * Daily (or hourly fallback) cleanup removes fulfilled entries older than `cleanAfterDays`.
   * Logs summarise count removed and oldest/youngest age.

---

## 5) WorldScanner Integration

PromiseKeeper assumes WorldScanner is present and:

* Calls `WorldScanner.start({ enable = { "ws.square.loadEvent", "ws.square.initialSweep" } })` during its own `startOnce`.
* Subscribes to `Starlit.Events.WorldScanner.onSquare` (and later `onRoom`, `onVehicle` when relevant).
* Provides minimal helpers (`PromiseKeeper.enableScanner(id)`, `PromiseKeeper.disableScanner(id)`) that proxy to WorldScanner for modder convenience (future work).
* (Future) Emit a debug warning if the required context type has no active scanners.

**Context expectations**

```lua
---@class PKSquareCtx
---@field sq IsoGridSquare
---@field squareId number
---@field roomDef RoomDef|nil
---@field roomId number|nil
---@field cx integer
---@field cy integer
```

Matcher functions receive `PKSquareCtx` plus the `matchParams` supplied at registration.

---

## 6) Logging

PromiseKeeper uses concise logging (no colons) via `PromiseKeeper/util`:

* `initialized` — store + scanner bootstrap complete.
* `ensureAt queued id <id> key <fKey>`
* `ensureAt merge id <id> key <fKey>`
* `square matcher attached` / `matched via square matchers` etc.
* Error envelope logs: `fulfiller error id=<id> key=<fKey> err=<message>`
* Cleanup summary: `cleanup removed=<count> oldestDays=<..> newestDays=<..>`
* **Macro contract (PromiseKeeper → Fulfiller):** Fulfillers may be invoked multiple times if they throw; they must handle idempotence internally (PromiseKeeper only guards at the `(id,key)` level).

Logs only print when `getDebug()` is true to reduce noise in production.

---

## 7) Configuration Defaults

```lua
PromiseKeeper.config = {
    cleanAfterDays = 30,
    maxFulfillments = 1,
}
```

Mods can mutate `PromiseKeeper.config` before registering requests to override defaults (per-request values still win).

---

## 8) Save & Load

* **On load**: `Store.loadOrInit(config)` reads/initialises the ModData tables, then PromiseKeeper starts WorldScanner scanners and performs a first pass over already loaded squares via the scanner’s `initialSweep`.
* **On save**: any mutated `requestsRoot` state lives directly in ModData and is written by the game; no extra work required.
* **Hot reload**: re-registering a fulfiller replaces the previous entry (with a warning). Requests referencing the fulfiller continue using the new function.

---

## 9) Validation Plan

| Scenario                        | Expectation                                                               |
| --------------------------------| --------------------------------------------------------------------------|
| Immediate `ensureAt`            | Fulfilled instantly if target square/room already loaded.                 |
| Deferred `ensureAt`             | Fulfilled once the square arrives via WorldScanner events.                |
| Matcher dedupe                  | Each `(id,key)` pair fulfilled at most once, even if matcher returns often.|
| Error resilience                | Fulfiller exceptions are logged; request remains pending for future retry.|
| Cleanup                         | Fulfilled entries pruned after `cleanAfterDays`.                          |
| Hot reload                      | Re-register fulfilers without duplicating requests.                       |
| Scanner toggling (future)       | Enabling/disabling scanners does not corrupt stored requests.             |

---

## 10) Future Extensions

* **Router refactor:** Replace `square_events.lua` with a more general `router.lua` that consumes multiple context types.
* **Scanner control API:** Surface `PromiseKeeper.enableScanner(id)` / `disableScanner(id)` once WorldScanner exposes them.
* **Additional context support:** Room-level matchers, vehicle matchers, meta-grid selectors.
* **Promise expiry:** Optional TTL for requests that never become eligible.
* **Analytics:** Lightweight metrics for fulfilled/matched counts over time.

---

## Summary

* PromiseKeeper stores and fulfils world promises safely and deterministically.
* WorldScanner supplies the “what squares/rooms are live” signal so PromiseKeeper stays lean.
* The API remains simple for mod authors: register a fulfiller, declare a promise, and let the system handle the rest.
