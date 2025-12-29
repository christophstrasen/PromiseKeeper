# PromiseKeeper — Project history (very short)

This is a tiny “where did this come from?” document so we can move older material out of the way without losing it.

## v1 (archived)

PromiseKeeper originally explored a square-first “deferred fulfilment” system.
This design is not current, but it’s useful as background:
- `docs_internal/drafts/PromiseKeeper_deferred_spawning_system.md`

## v2 (design exploration)

The v2 vision document captured vocabulary and the intended ecosystem role, but it also contains draft API and implementation planning:
- `docs_internal/drafts/PromiseKeeper_v2vision.md`

## v2.1 (implemented direction)

v2.1 aligned PromiseKeeper with WorldObserver “situations are already actionable”:
- PK resolves WorldObserver situations via `pk.situations.searchIn(WorldObserver)` (no mapping layer).
- Event sources remain explicit via `defineFromPZEvent` / `defineFromLuaEvent`.

Implementation notes / refactor plan:
- `docs_internal/drafts/refactor_v2dot1.md`

External feedback that shaped docs and ergonomics:
- `docs_internal/drafts/ai_feedback.md`
