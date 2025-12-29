# PromiseKeeper — Brownbag (catch-all)

This file is intentionally messy: it’s the place to keep notes that don’t (yet) deserve a stable doc.

## Where to look first (stable docs)

- Vision: `docs_internal/vision.md`
- Architecture (implemented): `docs_internal/architecture.md`
- API surface (implemented): `docs_internal/api.md`
- Documentation principles: `docs_internal/documentation_principles.md`
- History (very short): `docs_internal/project_history.md`
- Ideas (later): `docs_internal/ideas.md`
- Hard todos (must do): `docs_internal/todos.md`

## Drafts / archive

Older material lives here (often with outdated terms):
- `docs_internal/drafts/ai_feedback.md` (external clean-room feedback)
- `docs_internal/drafts/PromiseKeeper_v2vision.md` (design exploration + draft API)
- `docs_internal/drafts/refactor_v2dot1.md` (refactor plan notes)
- `docs_internal/drafts/PromiseKeeper_deferred_spawning_system.md` (v1 archived)
- `docs_internal/drafts/example.lua` (old snippets)
- `docs_internal/drafts/todos_action_plan.md` (older action plan / notes)

## Notes (grab bag)

- PromiseKeeper intentionally does not “sense the world”. If something needs probing/scanning, it belongs upstream (WorldObserver or a mod’s own logic).
- `occurranceKey` is the idempotence hinge: collisions mean “we already did it”, and missing keys mean we can’t remember doing it.
- WorldObserver integration is about division of responsibility:
  - WO: sensing + shaping observations into situations (including `WoMeta.key` and `WoMeta.occurranceKey`).
  - PK: persistence + idempotence + deterministic action running.
