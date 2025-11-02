# WorldScanner — Async World Scanning Framework (Draft Briefing)

> *Objective: Standalone Lua utility that discovers world targets (squares, rooms, vehicles, etc.) and publishes them to consumers such as PromiseKeeper, other mods, or developer tooling.*

---

## 1. Motivations

- **PromiseKeeper dependency** – PK needs a generic way to know when world elements become safe to mutate. The existing hard-coded `LoadGridsquare` hook is too narrow and cannot cover future needs (rooms, vehicles, map-wide scans).
- **Shared demand** – Other mods already reinvent “scan the world” loops (e.g. StoryMode world finder). A single, reusable module avoids duplication and lets modders combine scanners.
- **Loose coupling** – WorldScanner must remain useful without PromiseKeeper. Anyone should be able to require the module, register their own scanners/listeners, or use built-in helpers directly.

---

## 2. High-Level Design

### Core Pieces

| Component        | Role                                                                    |
| ---------------- | ----------------------------------------------------------------------- |
| `WorldScanner`   | Registry + dispatcher. Keeps scanner definitions and listener callbacks |
| **Scanners**     | Producers that discover world entities (squares, rooms, vehicles, …)    |
| **Listeners**    | Consumers that react to discovered contexts (PromiseKeeper, overlays)   |
| **Context types**| Structured data describing what was found (e.g. `SquareCtx`, `RoomCtx`) |

### Data Flow

```
Scanner (producer)  ── emits ctx ──► WorldScanner router ──► listener callbacks (PromiseKeeper etc.)
```

- Multiple scanners can emit the same context types (e.g. load-event scanner, periodic sweep scanner).
- Listeners subscribe per context type; they receive immutable copies.
- All dispatch happens via `WorldScanner.emit<Type>(ctx)` to keep the contract stable.

---

## 3. Planned API Surface (v0.1)

### Module Loading

```lua
local WS = require("WorldScanner")
```

### Context Structs

```lua
---@class WS.SquareCtx
---@field sq IsoGridSquare
---@field squareId number
---@field roomDef RoomDef|nil
---@field roomId number|nil
---@field cx integer  -- chunk x
---@field cy integer  -- chunk y

---@class WS.RoomCtx
---@field roomDef RoomDef
---@field roomId number
---@field buildingDef BuildingDef|nil

```

*(Context structs can expand but should remain additive. Each type denotes a dispatch channel.)*

### Scanner Registration

Scanner authors register their scanner via `WS.registerScanner(scannerId, initFn)`, where `initFn(router, config)` runs each time the scanner is enabled and may return a cleanup function.

- WorldScanner’s **built-in** scanners are already registered; skip this step for IDs listed in the built-in table.
- Custom scanners (yours or third-party) **must** register themselves during mod boot before you can enable them.

```lua
-- Instantiate a built-in scanner (periodic nearby sweep around the local player)
local ScanAllNear = WS.enableScanner("ws.square.nearby", {
    origin = getSpecificPlayer(0), -- or a specific IsoGridSquare
    radius = 30,
})

-- Register your custom scanner and enable instances of it.
WS.registerScanner("MyMod.lootSweeper", function(router) ... end)
local ScanLootWide = WS.enableScanner("MyMod.lootSweeper", { MyLootRadius = 20 }) --first instance
local ScanSofaLoot = WS.enableScanner("MyMod.lootSweeper", { MyLootRadius = 5, MyExtraCond = "Sofa_Tiles" }) -- second instance

-- disable when done
WS.disableScanner(ScanAllNear)
WS.disableScanner(ScanLootWide) 
WS.disableScanner(ScanSofaLoot)

```

`WS.enableScanner` always returns a handle; keep it if you plan to stop that particular instance later. `WS.disableScanner(handle)` is the only supported teardown path for specific instances.

### Listener Registration (Starlit-driven)

WorldScanner emits through **Starlit Events** on two layers:

- **Shared streams** (`Starlit.Events.WorldScanner.onSquare`, `onRoom`, …) receive every context of that type regardless of origin. Useful for orchestration, debugging, or cross-scanner correlation.
- **Per-scanner streams** (`Starlit.Events.WorldScanner.onSquareFrom[key]`, `onRoomFrom[key]`, …) deliver only the contexts emitted by a specific scanner. `key` can be either the scanner ID (`"ws.square.nearby.delta"`, `"MyMod.lootSweeper"`, …) or the handle returned from `WS.enableScanner` when you want to listen to a specific instance/config.

```lua
-- Listen to every square context (very verbose, suggested only for debugging, allows to see all events move through the various scanners)
Starlit.Events.WorldScanner.onSquare.Add(function(ctx) ... end)

-- Listen only to the specific scanner
-- built-in
Starlit.Events.WorldScanner.onSquareFrom["ws.square.nearby.delta"]:Add(function(ctx) ... end)
-- custom, subscribing to all of its live configs and without de-dupe
Starlit.Events.WorldScanner.onSquareFrom["MyMod.lootSweeper"]:Add(function(ctx) ... end)
-- built-in or custom but looking up by handle assigned during WS.enableScanner
Starlit.Events.WorldScanner.onSquareFrom[handle]:Add(function(ctx) ... end)
```

### Router API (scanner init)

When a scanner is enabled, its `initFn(router, config)` receives a router with the following surface:

- `router.emitSquare(squareCtx)` / `router.emitRoom(roomCtx)` – dispatch a validated context to listeners. Throws if required fields are missing.
- `router.buildSquareCtx(square, overrides?)` – returns a `SquareCtx` with derived identifiers (`squareId`, chunk coords, room fields). Optional `overrides` merge onto the result.
- `router.buildRoomCtx(roomDef, overrides?)` – returns a `RoomCtx` with validated ids and building reference.
- `router.tagContext(ctx)` – optional helper to append custom metadata before emission (e.g., `ctx.tags`). Router automatically injects `ctx.sourceScanner` and `ctx.instanceId`.

Routers are per-scanner-instance; do not cache them globally. Logging is left to the scanner (feel free to use `print`, `Events` helpers, or your own logger). Every emitted context is enriched with:

- `ctx.sourceScanner` – the registered scanner ID (e.g., `ws.square.nearby.delta`, `MyMod.lootSweeper`).
- `ctx.instanceId` – the handle corresponding to the enabled instance (unique per `WS.enableScanner` call). This same handle is available as a key on `Starlit.Events.WorldScanner.on<Type>From[...]` for per-instance subscriptions.
- Any metadata you append via `router.tagContext`.


### Emitting Contexts (for scanner authors)

Scanners must use the router provided during `init`. The two snippets below show the common Starlit-first pattern versus a bare-metal version.

#### Example: consume an existing Starlit stream of squares and emit matching squares

```lua
return function(router, config) -- your initFn
    local emitSquare = router.emitSquare

    local function onNearbySquare(event)
        if not event.square then
            return
        end

        if YOUR_CUSTOM_LOGIC then
            print("[myFinder] picked square " .. tostring(event.square))
            emitSquare(router.buildSquareCtx(event.square))
        end
    end

    local starlitEvent = Starlit.Events.WorldScanner.onSquareFrom["ws.square.nearby"] -- replace with your existing scanner ID

    starlitEvent.Add(onNearbySquare, {
        radius = config.radius or 20,
        includeLoaded = config.includeLoaded ~= false,
    })

    return function() -- your teardown function
        starlitEvent.Remove(onNearbySquare)
    end
end
```

#### Example: Hook into the raw Project Zomboid LoadGridSquare and related rooms

```lua
return function(router) -- your initFn
    local emitSquare = router.emitSquare
    local emitRoom   = router.emitRoom

    local function onLoadSquare(sq)
        emitSquare(router.buildSquareCtx(sq))

        if sq:getRoom() and YOUR_CUSTOM_LOGIC then
            print("[myFinder] picked room " .. tostring(sq:getRoom()))
            emitRoom(router.buildRoomCtx(sq:getRoom():getRoomDef()))
        end
    end

    Events.LoadGridsquare.Add(onLoadSquare)

    return function() -- your teardown function
        Events.LoadGridsquare.Remove(onLoadSquare)
    end
end
```

Router helpers (`buildSquareCtx`, `buildRoomCtx`, etc.) ensure consistent formatting, and the router validates required fields before dispatching to consumers.

> **Reduction-only:** Scanners are expected to filter, dedupe, or enrich whatever upstream stream they attach to; they should never invent additional world entities beyond what their source provided. If you need to broaden the stream, add another producer scanner instead of mutating a downstream one.

The shared `Starlit.Events.WorldScanner.on<Type>` streams exist primarily for orchestration, tooling, and debugging—expect duplicate contexts from different scanners as they hand off responsibility. Consumer mods that care about a particular producer should subscribe via `on<Type>From[scannerId]` or filter by `ctx.sourceScanner`.

### AsyncScanning utility (preview)

To keep long-running sweeps lightweight, WorldScanner will expose `WorldScanner.AsyncScanning`, inspired by `StoryModeMod.WorldFinder.searchAroundSquareAsync` but refit for the Starlit router. The surface we are targeting:

```lua
local AsyncScanning = require("WorldScanner.AsyncScanning")

return function(router, config)
    local emitSquare = router.emitSquare

    local handle = AsyncScanning.startSquareSweep({
        origin = config.origin or getSpecificPlayer(0), -- defaults to the local player
        radius = config.radius or 80,
        batchSize = config.batchSize or 32,
        throttleMs = config.throttleMs or 25,
        onBatch = function(batch)
            for _, sq in ipairs(batch) do
                emitSquare(router.buildSquareCtx(sq))
            end
        end,
        onComplete = function(stats)
            if stats then
                print(string.format("[AsyncSweep] finished (%d squares)", stats.total or 0))
            end
        end,
    })

    return function()
        handle:cancel()
    end
end
```

Key pieces (subject to adjustment as we prototype):
- `AsyncScanning.startSquareSweep(opts)` / `startRoomSweep(opts)` return a handle with `:cancel()` and `:isRunning()`.
- `opts.origin` must be an `IsoPlayer` (default: `getSpecificPlayer(0)`; ensure one exists in your context) or an `IsoGridSquare`. Any other type raises a validation error.
- `opts.onBatch(batch)` receives arrays of `IsoGridSquare` or `RoomDef` that the scanner can turn into contexts.
- Optional `opts.onComplete()` fires after the sweep finishes or is cancelled.

---

## 4. Lifecycle

1. **Module require:** Mods call `require("WorldScanner")`. This returns the singleton table with registration methods.
2. **Scanner setup:** Scanners register themselves (either built-in or third-party). Registration is idempotent.
3. **WS.start(config?) (orchestrator-controlled):** An orchestrator (PromiseKeeper, your mod, or tooling) calls `WS.start()` once to wire up the router and apply global configuration (logging levels, validation flags, etc.). If another orchestrator already started WS, the call is a no-op. Scanners remain inactive until explicitly enabled.
4. **Enable instances:** Call `WS.enableScanner(id, config?)` for each scanner you want running; stash the returned handle(s). Disable them via `WS.disableScanner(handle)` when the instance should stop.
5. **Events dispatch:** As scanners emit contexts, WS validates them and forwards to listeners. Listeners should be fast and offload heavy work to their own coroutines if needed.
6. **Shutdown (optional, orchestrator-controlled):** `WS.stop()` tears down scanners (calls dispose functions) and clears listeners. Call this when unloading the orchestrator (e.g., hot-reload). Repeated `stop` calls are safe no-ops.

---

## 5. Built-in Scanners (initial target set)

| Scanner ID                 | Primary context(s) | Starlit event(s) emitted                                   | Description                                               | Notes                                 |
| -------------------------- | ------------------ | ---------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------- |
| `ws.square.load`           | `SquareCtx`        | `Starlit.Events.WorldScanner.onSquare`,<br>`Starlit.Events.WorldScanner.onSquareFrom["ws.square.load"]`               | Listens to `Events.LoadGridsquare`                        | Equivalent to PK’s current wiring     |
| `ws.square.initial`        | `SquareCtx`        | `Starlit.Events.WorldScanner.onSquare`,<br>`Starlit.Events.WorldScanner.onSquareFrom["ws.square.initial"]`            | One-time pass across squares already loaded at startup    | Fills cold-start gap                  |
| `ws.square.nearby`         | `SquareCtx`        | `Starlit.Events.WorldScanner.onSquare`,<br>`Starlit.Events.WorldScanner.onSquareFrom["ws.square.nearby"]`             | Periodic scan around player vicinity (configurable radius)| Emits firehose stream of nearby squares|
| `ws.square.nearby.delta`   | `SquareCtx`        | `Starlit.Events.WorldScanner.onSquare`,<br>`Starlit.Events.WorldScanner.onSquareFrom["ws.square.nearby.delta"]`       | Emits only newly-seen nearby squares (built atop firehose)| Deduped by squareId                   |
| `ws.room.nearby`           | `RoomCtx`          | `Starlit.Events.WorldScanner.onRoom`,<br>`Starlit.Events.WorldScanner.onRoomFrom["ws.room.nearby"]`                   | Uses square scan + room resolution to emit `RoomCtx`      | Optional; off by default              |

> Scanners may emit more than one context type as an optimisation (e.g., a square sweep that also emits corresponding room contexts). Document additional emissions in the scanner notes so consumers know what to expect.

Built-ins are disabled until explicitly enabled via `WS.enableScanner`.

> Listener hint: `Starlit.Events.WorldScanner.onSquareFrom["ws.square.nearby"]` delivers only this scanner’s contexts, while `Starlit.Events.WorldScanner.onSquare` provides the aggregate stream for tooling and cross-scanner coordination.

---

## 6. PromiseKeeper Integration Concept

1. PromiseKeeper requires WorldScanner and calls `WS.start()`.
2. PromiseKeeper enables the built-ins it needs, keeping the returned handles for teardown:

   ```lua
   local loadHandle = WS.enableScanner("ws.square.load")
   local sweepHandle = WS.enableScanner("ws.square.initial")
   ```

3. PromiseKeeper registers as listener:

```lua
Starlit.Events.WorldScanner.onSquare.Add(function(ctx)
       FulfillmentEngine.handleSquare(ctx)
   end)
   Starlit.Events.WorldScanner.onRoom.Add(function(ctx)
       FulfillmentEngine.handleRoom(ctx)
   end)
```

(`Starlit.Events.WorldScanner.onSquareFrom["ws.square.nearby.delta"]` is available if PromiseKeeper ever wants the deduped feed only.)

4. Fulfillment engine stays responsible for:
   - Evaluating outstanding requests.
   - Running matchers (`ensureMatchingForSquare`, future room/vehicle matchers).
   - abstracting and providing short-hands/shims like `ensureAt`
   - Logging, error guards, idempotence.

5. PromiseKeeper may check-for/enable/disable scanners on-demand per the needs the "requests" have (store the handles for later `WS.disableScanner` calls).

> In environments without PromiseKeeper, your mod becomes the orchestrator: register any custom scanners during boot, call `WS.start()` once, then enable/disable scanners as needed. Remember that built-ins are already registered; you only need to enable them.

This keeps the coupling one-way: PK depends on WS, not vice versa.

---

## 7. Extensibility & Modder Experience

- **Scanner authorship:** Third-party mods can ship scanners to, say, detect parked cars, hazard zones, etc. They simply depend on WorldScanner, register under a unique ID, and emit contexts.
- **Consumer usage:** Mods write listeners that subscribe to the context types they care about. PromiseKeeper is just one consumer.
- **Starlit integration:** Every dispatch flows through `Starlit.Events.WorldScanner.*`, ensuring Starlit-aware mods/tools stay in sync while the helper wrappers remain available.
- **Per-scanner channels:** Subscribe via `Starlit.Events.WorldScanner.on<Type>From[scannerId]` to consume only a single scanner; use the aggregate `on<Type>` streams for orchestration or diagnostics.
- **Async support:** Scanners can schedule themselves via `Events.OnTick` or coroutines; WS itself stays synchronous (it just dispatches contexts when `emit<Type>` is called).
- **Telemetry (later idea):** Provide optional metrics or debug overlays to inspect scanner performance (e.g., squares per minute, backlog size).
- **Composable streams:** Expensive emitters (e.g., wide-radius square sweeps) should expose their context stream so downstream scanners can chain and filter instead of re-scanning the same area. This keeps multiple finders lightweight by “sharing the train” of base candidates.
- **Map/filter pipeline:** Treat the scanner chain as a series of map + filter stages. Primary producers map raw world data into contexts; downstream scanners only narrow or annotate those contexts rather than expanding the set.
- **Context contract:** Scanners must emit contexts that satisfy the published type contract. For example, `SquareCtx` must include `squareId` (and ideally a `ref` or enough information for consumers to resolve it). If a field is omitted, the consumer **must** be able to recover the reference cheaply. Document any deviations so downstream matchers aren’t surprised.
- **Configurable instances:** `WS.enableScanner(id, config)` accepts a flat config table. You can enable the same scanner ID multiple times with different configs (e.g., “kitchen” vs “bathroom” room matchers); WorldScanner returns a distinct handle for each instance so you can disable them independently.
- **Validation & logging:** The router validates contexts before emission; invalid payloads are dropped with a debug log so scanner authors can adjust without crashing consumers.

---

## 8. Roadmap Sketch

1. **Bootstrap (v0.1)**
   - Implement module skeleton, scanner/ listener registries, router helpers.
   - Port the current PromiseKeeper `LoadGridsquare` logic into a built-in scanner.
   - Add initial sweep and simple envelope scanner.
2. **PromiseKeeper adoption**
   - Update PromiseKeeper to depend on WS and consume its events.
   - Verify ensureAt/ matcher flows with the new router.
3. **Vehicle / Room expansions (v0.2+)**
   - Introduce additional context types and built-in scanners as needed.
   - Document the standard context fields.
4. **Public release**
   - Publish API docs, sample scanners, debugging utilities.

---

## 9. Naming & Packaging

- **Module name:** `WorldScanner` (or `StarlitWorldScanner` if we want a namespace prefix).
- **Directory layout (suggested for new repo):**

```
world-scanner/
 ├─ media/lua/shared/WorldScanner.lua
 ├─ media/lua/shared/WorldScanner/scanners/*.lua   -- built-ins
 ├─ media/lua/shared/WorldScanner/types.lua        -- context structs
 ├─ docs/overview.md
 ├─ examples/*.lua
```

- PromiseKeeper would depend on this repo (as submodule or packaged mod).

---

## 10. Open Questions

- How to handle conflicting scanner IDs or double-registration (plan: overwrite with warning).
- Whether to ship a minimal scheduler inside WS for coroutine-based scanners (leaning no—authors can attach to `Events.OnTick` themselves).
- Config surface: do we expose `WS.config` for tuning envelope radius, batch sizes, etc., or leave that to each scanner?
- Should WS expose a global dedupe layer (e.g., once a square is emitted, never emit again unless explicitly reset), or leave dedupe to consumers like PromiseKeeper?

---

### Summary

WorldScanner aims to be the shared “world discovery” backbone:

- Standalone, reusable, extensible.
- PromiseKeeper consumes it but doesn’t own it.
- Scanners emit typed contexts; listeners act on them.
- Built-in support for square/room scans with room for future context types.

Once this briefing is approved, we can spin up the dedicated repo and start porting the current PromiseKeeper scanning logic into WorldScanner’s first built-in scanners.
