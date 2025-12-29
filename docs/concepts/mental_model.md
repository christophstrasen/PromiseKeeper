# Mental model

PromiseKeeper is a persistent action runner that glues situations and actions together via promises:

- **Situation:** a stream that emits “something happened” occurrences over time.
- **Action:** a function you want to run when situations arrive.
- **Promise:** the durable promise definition that ties a situation to an action with a policy.

A single situation (via its `situationKey`) can produce **many** occurrences over time. `occurranceKey` is how PromiseKeeper recognizes when an occurrence refers to the same `subject` again versus a different `subject`.

Lifecycle (typical):
1) At game startup (including after reload): register situations + actions (by id), then call `pk.remember()` to resume stored promises.
2) In situ: declare a promise (PK stores it and then looks for opportunities to run your action as situations come in). This can happen at any time during play.

When a situation occurrence arrives, PromiseKeeper:
- decides whether to run the action (policy),
- runs the action focusing on the `subject`,
- remembers what it did using `occurranceKey` (so it won’t redo it after reload).

Retries are a safety net for transient action failures. PromiseKeeper is not meant to “discover readiness” by retrying for a long time: situations should usually emit only when the `subject` is ready to act on.

PromiseKeeper intentionally does not sense the world. If you need probing/scanning or game logic (distance, room type), do it upstream (WorldObserver or your mod code) and emit situations from there.
