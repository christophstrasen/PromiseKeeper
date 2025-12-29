# PromiseKeeper v2.1 Refactor Plan (hard cut)

Goal: remove the WO mapping layer, treat WorldObserver situations as already actionable, and keep event-based situations explicit. No compatibility shims.

## 0) Scope assumptions
- PromiseKeeper must remain resumable (registries persist definitions).
- WorldObserver situations now emit actionable observations with `WoMeta.key` and `WoMeta.occurranceKey`.
- For non-WO event sources (PZ Events / Starlit LuaEvent) we still must shape `{ occurranceKey, subject }`.

## 1) Rename concepts (hard cut)
- Rename `situationMapId` → `situationKey` everywhere in PromiseKeeper.
- Rename registry surface `pk.situationMaps` → `pk.situations`.
- Rename `occurrenceId` → `occurranceKey` everywhere in PromiseKeeper.
- Rename backing registry module/file names as needed to match (`registries/situations.lua`, `core/router.lua`, `requests_store.lua`, etc.).
- Remove any leftover “map” terminology in docs/examples.

## 2) New public surface for situations
Add the following API on the namespaced `pk` handle:
- `pk.situations.define(situationKey, buildStreamFn)`
- `pk.situations.defineFromLuaEvent(situationKey, luaEvent, toCandidateFn)`
- `pk.situations.defineFromPZEvent(situationKey, pzEvent, toCandidateFn)`
- `pk.situations.searchIn(WorldObserver)`
  - One-time bridge: caches the registry reference and binds the namespace.
  - Auto-detects the WorldObserver adapter for situations.
  - Convention: PromiseKeeper namespace == WorldObserver situations namespace.
  - Error if no namespace is set.
  - Resolution rule: if `situationKey` exists in `pk.situations`, it wins; otherwise fall back to the search registry.

## 3) Promise shape update
- `pk.promise` accepts `situationKey` instead of `situationMapId`.
- Stored promise definitions and in-memory routing use `situationKey`.

## 4) Router behavior changes
- When resolving a situation for a promise:
  1) Check `pk.situations` registry for `situationKey`.
  2) If not found, and `pk.situations.searchIn` is active, resolve from WO:
     - `WorldObserver.situations.namespace(namespace).get(situationKey, situationArgs)`
  3) If still missing, mark promise broken and warn.

- For WO streams:
  - `subject = observation` (whole observation, including multi-family).
  - `occurranceKey = observation.WoMeta.occurranceKey or observation.WoMeta.key`.
  - If missing: warn + skip (PromiseKeeper side).

## 5) Registry + persistence changes
- Update the persisted definition schema to store `situationKey` (not `situationMapId`).
- Hard-cut behavior: delete/ignore old persisted entries with `situationMapId`.
  - Clear old definitions on load if an old field is detected (warn once).

## 6) Remove old mapping helpers
- Remove `pk.adapters.worldobserver.mapFrom` and any related mapping utilities.
- Remove “map” helpers from `factories.lua` if they are only used for WO.

## 7) Update smokes and docs
- Smokes:
  - `smoke_pk_worldobserver.lua` should use only `pk.situations.searchIn(...)` and `pk.promise{ situationKey = ... }`.
  - `smoke_pk_luaevent.lua` and `smoke_pk_pz_events.lua` should use `pk.situations.defineFromLuaEvent` / `defineFromPZEvent`.
- Docs:
  - `external/PromiseKeeper/docs/PromiseKeeper_v2vision.md` (rename fields + clarify WO path)
  - `external/PromiseKeeper/docs/example.lua` (align with new API)

## 8) Tests
- Update existing unit tests to new API names.
- Add tests for:
  - `pk.situations.defineFromLuaEvent` and `defineFromPZEvent` wiring.
  - WO fallback resolution path when `pk.situations.searchIn` is active.
  - Missing WO situation key → broken + warn (no crash).

## 9) Cleanup + consistency sweep
- Replace all references to `situationMapId` with `situationKey` (code, docs, tests, smokes).
- Replace all references to `occurrenceId` with `occurranceKey` (code, docs, tests, smokes).
- Align logging wording (“situation” vs “map”).
- Ensure error messages match the new terms.

## 10) Manual validation
- Run `busted tests` inside `external/PromiseKeeper`.
- Smoke test in-game:
  - LuaEvent and PZ event examples still emit.
  - WO example works with zero PK mapping calls.

## 11) Decisions locked
- WO bridge method name: `pk.situations.searchIn(WorldObserver)`.
- Missing namespace when calling `searchIn` is a hard error.
- Persistence is a hard cut: old `situationMapId` definitions are dropped (warn once).
