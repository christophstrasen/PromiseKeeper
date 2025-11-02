Document date: 2025-11-01

# Given that

> The modder wants to change or create something in the world.
> They know exactly what they want to change/create and have the code for it.
> They either know exactly where/when in the game that should happen or they are flexible and may indeed wish to set dynamic rules.
> **Problem**: They cannot change/create it _yet_ because the world isn't ready (chunk load or any other condition, world-time etc. ..)
> **Vision**: So they ask a system that tracks their wishes and fulfills them _when_ and _where_ the world is ready for them.

# Solution (pre-implement)

Single world change at precise location, when location is ready
```lua

local PromiseKeeper = require("PromiseKeeper")

--- User provided function to serve as fulfiller: called once per roomDef
---@param roomDef RoomDef
---@param meta { id:string, fulfiller:string, tag:string|nil }
function MyPrefabs.LabScene.makeForRoomDef(roomDef, meta)
  -- build with SceneBuilder ...
end


PromiseKeeper.registerFulfiller("destroyed_lab_scene", LabScene.makeForRoomDef, "Scene")

---@type RoomDef
local LabRoomDef = MyFinder.pickRoomForLab()  -- your own resolver
-- or local LabRoomDef = getCell():getGridSquare(10677, 9783, 0) -- example coords

PromiseKeeper.ensureAt({
  id        = "intro-destroyed-lab-A",
  fulfiller = "destroyed_lab_scene",
  target    = LabRoomDef,
})

```

Permanent promise that affects all chunks
```lua

local PromiseKeeper = require("PromiseKeeper")

--- User provided function to serve as fulfiller: called once per roomDef
function MyPrefabs.KitchenScene.makeForRoomDef(roomDef, meta)
  -- build with SceneBuilder ...
end

PromiseKeeper.registerFulfiller("kitchen_oddity_scene", KitchenScene.makeForRoomDef, "Scene")

-- Matcher: receives both chunkCtx and optional matchParam table
local function matchKitchens(chunkCtx, matchParam)
  local results = {}
  local chance = (matchParam and matchParam.chance) or 1.0

  for _, roomDef in pairs(chunkCtx.roomDefs) do
    if roomDef:getName() == "kitchen" and ZombRandFloat(0.0, 1.0) < chance then
      local key = tostring(roomDef:getID())  -- stable keys avoid double-spawning
      results[#results+1] = { key = key, roomId = roomDef:getID(), ref = roomDef }
    end
  end
  return results
end

-- PromiseKeeper ensures these scenes exist once per unique target
PromiseKeeper.ensureMatchingForChunk({
  id          = "global-kitchen-oddities",
  fulfiller   = "kitchen_oddity_scene",
  matchFn     = matchKitchens,
  matchParams = { chance = 0.2},  -- every 5th kitchen
  maxFulfillments = 999999        -- GLOBAL cap to this promise ID. For "permanent promises" set > total chunks on the map
})

```


# **PromiseKeeper — Deferred Spawning System Top-Down Implementation Plan (v1, chunk-first))**

---

## 0) Purpose & Principles

**Goal:**
Let modders *declare* world changes that should happen **later**, when the target area (chunk, room, square) becomes safe to modify.

**Model:**

* Version 1 focuses on **chunk-first** triggers (no proximity polling).
* Promises are **idempotent** per `(id + targetKey)` — safe from duplicates.
* Persistent data lives in **world ModData**.
* Cleanup happens automatically after `cleanAfterDays`.
* Uses **Starlit `LuaEvent`** internally for lifecycle hooks.

Think of it as:

> “Register a fulfiller. Declare a promise. It gets kept when the world is ready.”

---

## 1) Public Surface

| Method                                             | Purpose                                  |
| -------------------------------------------------- | ---------------------------------------- |
| `registerFulfiller(name, fn, tag?)`                | Register callable fulfillers.            |
| `ensureAt(request)`                                | Single known target (roomDef or square). |
| `ensureMatchingForChunk(request)`                  | Repeating matcher for chunk scanning.    |
| *(optional)* `getStatus(id)` / `listDelivered(id)` | Debug helpers.                           |

Private internals:
`_registry`, `_requests`, `_events`, `_config`.

---

## 2) Data Model

**Request record (persisted in ModData):**

* `id` — unique string (per author).
* `fulfiller` — key into registry.
* `tag` — optional grouping label.
* `createdAtDays`, `cleanAfterDays` (default = 30).
* `status ∈ Requested | Evaluating | Fulfilled`.
* `maxFulfillments` (default = 1), `fulfillments` (start = 0).
* `target` holds the stable `key` plus either `roomId` or `squareId`.
* For matchers: `mode="chunk"`, `target.key="chunk:<cx,cy>"`.

**In-memory only:**

* `ref` — actual resolved roomDef or square.
* `fulfillmentKey = id .. "|" .. target.key`.
* `matchFn` — transient function, not serialized.

**Storage layout:**
`ModData.PromiseKeeper.requests[id] = { … }`
Optionally `byTarget[fulfillmentKey] = true` for quick duplicate checks.

---

## 3) Lifecycle

**States:** `Requested → Evaluating → Fulfilled`

1. **Requested:** waiting for matching chunk load.
2. **Evaluating:** chunk loads; resolve target; call fulfiller.
3. **Fulfilled:** increment counter; mark complete if limit reached.

**Idempotence:** skip fulfillment if count ≥ maxFulfillments.

**Cleanup:** once per game day, remove fulfilled entries older than `cleanAfterDays`.
Emit one summary log per cleanup cycle.

---

## 4) Events & Integration

**Internal (private) events:**

* `onRequestCreated(request)`
* `onEvaluating(request, ctx)`
* `onFulfilled(request, key, info?)`
* `onDuplicateSuppressed(request, key)`
* `onCleaned(count)`

**Chunk hook:**

* Subscribe to Build 42 *chunk-loaded* event.
* For each loaded chunk:

  * Create a lightweight `chunkCtx` with `(cx, cy)` and iterators for contained rooms/squares.
  * Run all **Requested** entries that might apply:

    * `ensureAt`: if target lies in this chunk.
    * `ensureMatchingForChunk`: call its `matchFn(chunkCtx)` to get candidate targets.

**Startup:**
On game load, perform one initial sweep over already loaded chunks.

---

## 5) Public API Behavior

### `registerFulfiller(name, fn, tag?)`

* Adds or replaces a fulfiller (`fn(ctx)`).
* Tag is informational (e.g. `"Scene"`, `"Ambient"`).
* Log a warning on overwrite.

### `ensureAt({ id, fulfiller, target, ... })`

* `target`: a `roomDef` or `IsoGridSquare`.
* Normalizes to `{ key = "...", roomId? = ..., squareId? = ... }` (IDs only).
* If `(id + targetKey)` exists, merge and keep earliest creation date.
* Persist immediately, emit `onRequestCreated`.
* On future chunk load: resolve `ref`, call fulfiller if eligible.

### `ensureMatchingForChunk({ id, fulfiller, matchFn, matchParams, ... })`

* Persistent record with `mode="chunk"`.
* `matchFn` is **kept in memory only**.
* On each chunk load:

  * `matchFn(chunkCtx, matchParams)` returns `{ key, roomId?/squareId?, ref? }` targets.
  * Each unique `(id + key)` checked and fulfilled once.

---

## 6) Fulfiller Context

Each fulfiller receives:

```lua
{
  request = <immutable request table>,
  target  = <resolved roomDef or square>,
  meta    = { id = ..., fulfiller = ..., tag = ... }
}
```

Determinism inside the fulfiller remains the author’s responsibility.

---

## 7) Logging

Short, single-line logs (no colons `:`):

* Creation: `id`, `fulfiller`, `mode`.
* Evaluation: chunk coords, candidate count.
* Fulfillment: `id`, `key`, `count/max`.
* Suppression: logged once.
* Cleanup: removed count, oldest/youngest ages.

---

## 8) Defaults

```lua
PromiseKeeper.config = {
  cleanAfterDays = 30,
  maxFulfillments = 1
}
```

---

## 9) Chunk Utilities

Expose simple helpers:

* `rooms(typeName?) → iterator`
* `squares(filterFn?) → iterator`

Authors must return **stable keys** from matchers to ensure idempotence.

---

## 10) Save & Load

**On game load:**

* Load persisted ModData.
* For any matching requests whose fulfillers were re-registered, re-attach their in-memory `matchFn`.
  (If the mod didn’t re-register it, leave dormant and warn.)
* Sweep loaded chunks once to deliver pending promises.

**On save:**
Sync current `_requests` back to ModData (omit any functions or refs).

---

## 11) Validation Plan (no code)

| Scenario              | Expectation                                                  |
| --------------------- | ------------------------------------------------------------ |
| Single `ensureAt`     | Fulfilled once on entering target chunk; survives reloads.   |
| Chunk matcher         | Each unique target fulfilled once; revisits don’t duplicate. |
| Duplicate suppression | Second identical `ensureAt` ignored with log.                |
| Cleanup               | Old fulfilled entries removed after threshold.               |
| Hot-reload            | Re-register fulfillers without duplication.                  |

---

## 12) Future Extensions

Planned later versions may add:

* Proximity-based matchers (`ensureMatchingNearPlayer`, etc.).
* Expiry for undelivered requests.
* Priorities or ordering.
* Optional public read-only events (`onDelivered`, `onCleaned`).

---

### Summary

This plan keeps **PromiseKeeper** small, deterministic, and safe:

* **Chunk-driven** world changes.
* **Persistent and idempotent** behavior.
* **Minimal author friction** — register → declare → forget.
