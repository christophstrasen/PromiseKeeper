# Contributing to PromiseKeeper

PromiseKeeper is a persistent action runner for Project Zomboid mods: it connects *situations* to *actions* via persisted *promises*.

Contributions are welcome, especially:
- API ergonomics improvements for modders,
- correctness fixes for persistence / `whyNot` / retries,
- documentation improvements (the main adoption surface),
- integration improvements with WorldObserver.

PromiseKeeper is intentionally light on game/domain logic (distance, room types, scanning). If a change pulls PromiseKeeper toward “world sensing”, we should discuss alternatives (typically: keep it upstream in WorldObserver or the mod).

## Quick links

- User docs: `docs/index.md`
- Architecture (IS): `docs_internal/architecture.md`
- Internal API notes: `docs_internal/api.md`
- Documentation principles: `docs_internal/documentation_principles.md`

## Development workflow

See:
- Development quickstart (single repo): `development.md`
- Internal notes: `docs_internal/developing.md`

## DREAM suite

PromiseKeeper is one module in the DREAM family (WorldObserver, PromiseKeeper, SceneBuilder, LQR, reactivex, DREAM).

Maintainer convenience repo (multi-repo sync/watch): https://github.com/christophstrasen/DREAM-Workspace

## Expectations

- Keep changes small and easy to review.
- Keep the public API stable and coherent (unless we explicitly do a hard-cut refactor).
- Prefer deterministic behavior and persisted state clarity.
- Add or update `busted` tests when changing logic:
  - Run: `busted tests`
