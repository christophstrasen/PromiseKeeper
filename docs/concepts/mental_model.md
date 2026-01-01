# Mental model

PromiseKeeper is a persistent “when this happens, do that” runner:
- it listens for **situation occurrences** from your situation sources,
- applies a **policy** (chance, cooldown, retry, max runs),
- runs an **action** against the occurrence’s `subject`,
- remembers what it did across reloads (using `namespace`, `promiseId`, and `occurranceKey`).

## The three nouns

- **Situation:** a stream that emits occurrences (“something happened”) over time.
- **Action:** a function you want to run when a situation occurrence arrives.
- **Promise:** the durable rule that ties a situation to an action with a policy.

In code, that rule is created by `pk.promise({...})`:

- `situationKey` says when.
- `actionId` says what to do.
- `policy` says how often (and under which constraints).

A single situation (via its `situationKey`) can produce **many** occurrences over time. `occurranceKey` is how PromiseKeeper recognizes when an occurrence refers to the same `subject` again versus a different `subject`.

## What actually happens when a situation emits

Think of each situation emission as an *occurrence record*:

- `occurranceKey` identifies “what this occurrence is about” (e.g. a tile, a zombie, a player).
- `subject` is what your action will receive (usually the thing you want to mutate, or an observation
  that contains it).

Then PromiseKeeper evaluates:

1) Resolve the promise definition (`promiseId`) to its `situationKey`, `actionId`, and `policy`.
2) Check policy gates (in rough order):
   - Is the promise already “done” (`maxRuns`)?
   - Is the promise currently cooling down?
   - Does deterministic `chance` allow this occurrence?
3) If allowed, call the action with `(subject, actionArgs, promiseCtx)`.
4) If the action succeeds, record progress for this occurrence, so the same `occurranceKey` won’t act
   again after reload (unless you explicitly reset it).

This is why PromiseKeeper is “when this, then that”, but with two extra properties:
- **Identity:** “which rule is this?” (`namespace` + `promiseId`)
- **Instance:** “which specific thing did the rule run on?” (`occurranceKey`)

## Deterministic chance is per occurranceKey (no re-rolls)

If you set `policy.chance = 0.25`, PromiseKeeper does not roll each time it sees an occurrence.

Instead it deterministically decides based on:
- `namespace`
- `promiseId`
- `occurranceKey`

So:
- the same tile will consistently pass or fail,
- repeated emissions on the same tile will repeat the same decision,
- across many different tiles you will see the expected distribution.

This makes chance debuggable and stable across reloads.

Lifecycle (typical):
1) At game startup (including after reload): register situations + actions (by id), then call `pk.remember()` to resume stored promises.
2) In situ: declare a promise (PK stores it and then looks for opportunities to run your action as situations come in). This can happen at any time during play.

## “Unmaking” promises (how modders turn rules off again)

The common workflow is:

- Keep your `promiseId` stable across versions.
- When iterating in console, call `promise.forget()` to stop listening and clear stored progress.

`promiseId` is the human-meaningful “name” of the rule. If a modder wants to later disable a rule or
replace it, they do it by addressing the same `namespace` + `promiseId`.

Retries are a safety net for transient action failures. PromiseKeeper is not meant to “discover readiness” by retrying for a long time: situations should usually emit only when the `subject` is ready to act on.

PromiseKeeper intentionally does not sense the world. If you need probing/scanning or game logic (distance, room type), do it upstream (WorldObserver or your mod code) and emit situations from there.

## Next reads

- IDs and keys: `ids.md`
- Policy semantics: `../guides/policy.md`
- Occurrence keys: `../guides/occurrance_key.md`
