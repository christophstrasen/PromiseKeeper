# PromiseKeeper — Vision

PromiseKeeper helps mods run actions at the right moment, only as often as intended, and remember that across game reloads.

## North Star

Let modders write “do X when Y happens” without re‑implementing:
- persistence across reloads,
- idempotence (“only once per thing”),
- deterministic gating (chance / cooldown / max runs),
- retries + basic diagnostics.

## Contract (plain words)

You (the modder) provide:
- a **namespace** (usually your mod id),
- a named **situation** (`situationKey`) that produces actionable situations over time,
- a named **action** (`actionId`) to run,
- a **promise** definition (id + args + policy).

PromiseKeeper provides:
- it stores the promise + progress and restarts it after reload,
- it runs your action when situations arrive (or retries later), following your policy,
- it tells you what it acted on via `subject`, `occurranceKey`, and `promiseCtx`.

## Boundaries (what we do / don’t do)

PromiseKeeper is intentionally **light on game / domain logic**. It should not “understand the world”; it should run actions reliably when *your* upstream code says “this situation happened”.

PromiseKeeper:
- consumes streams of situations; it does **not** probe/scan the world to create its own signals,
- does not decide “game logic” like distance, room type, etc (that belongs upstream),
- keeps readiness checks minimal: if `occurranceKey` or `subject` is missing, it warns and skips.

## Key vocabulary

- `namespace`: isolates different mods’ persisted state.
- `promiseId`: stable identity of “this automation rule”.
- `situationKey`: stable identity of “where situations come from”.
- `occurranceKey`: stable identity of “the specific situation occurrence” (idempotence key).
- `subject`: the thing handed to the action (should be safe to mutate, or contain such objects).
- `promiseCtx`: metadata passed to every action call (ids, policy, retry counter, …).

## Situation sources

PromiseKeeper is standalone:
- situations can be built from PZ events (`Events.*`) or Starlit LuaEvent.

PromiseKeeper can optionally integrate with WorldObserver:
- WorldObserver situations already emit actionable observations
- In that mode, PromiseKeeper treats the whole observation as the `subject` and uses th e`occurranceKey` from `WoMeta`.
