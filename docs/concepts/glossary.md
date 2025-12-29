# Glossary

- **PromiseKeeper**: A persistent action runner. It listens to “situations”, runs your action according to a simple policy, and remembers progress across reloads.
- **Namespace**: A mod-chosen name that isolates persisted state so multiple mods can use PromiseKeeper without collisions. Prefer a fully-qualified name (usually your mod id).
- **`PromiseKeeper.namespace(namespace)`**: Returns a namespaced PromiseKeeper handle. All stateful operations happen under that namespace.
- **`pk`**: The short, namespaced PromiseKeeper handle name we typically use as a variable.

- **Situation**: A stream that emits “something happened” occurrences over time.
- **`situationKey`**: A stable name for a situation definition, registered at startup so promises can resume after reload.
- **`situationArgs`**: Optional, persisted arguments for building a situation stream (passed into the situation definition).
- **Situation stream**: The live, subscribable stream produced by a situation definition.
- **WorldObserver situation**: A `WorldObserver.situations` stream. PromiseKeeper treats these as already actionable (it receives observations directly).

- **Action**: Your side-effect function (“what to do when it’s time”).
- **`actionId`**: A stable name for an action function, registered at startup so promises can resume after reload.
- **`actionArgs`**: Optional, persisted arguments passed to the action function on each attempt.

- **Promise**: The durable promise definition: “for occurrences from this situation, run this action according to this policy, and remember progress across reloads”.
- **`promiseId`**: A stable name for a promise (“this promise”), chosen by the modder within a namespace.
- **`occurranceKey`**: A stable identity for a situation occurrence, used for idempotence (“don’t do this twice across reloads”). In WorldObserver streams this defaults to `observation.WoMeta.occurranceKey` (or `observation.WoMeta.key`).
- **Subject**: The value handed to the action (often the whole WorldObserver observation, or a game object like `IsoGridSquare` for event-driven situations).
- **`promiseCtx`**: A small metadata table passed to every action call (ids, policy, retry counters, etc).

- **Policy**: Simple constraints about “how” to run: once/N, chance, cooldown, retry delay, expiry.
- **`whyNot`**: A short reason code explaining why PromiseKeeper skipped an occurrence (maxRuns reached, cooldown, chance miss, missing keys, …).
- **Broken promise**: A promise that can’t start (usually because its `situationKey` or `actionId` can’t be resolved at startup). PromiseKeeper keeps the persisted entry and records a reason code.

- **`pk.remember()` / `pk.rememberAll()`**: (Re)start persisted promises at game startup (including after reload).
- **`promise.stop()`**: Stop listening for situations for this promise right now (keeps persisted progress; does not persist a “stopped” flag).
- **`promise.forget()` / `pk.forget(...)`**: Reset stored progress (occurranceKey history, counters, cooldown) and clear broken state (keeps the promise definition).
