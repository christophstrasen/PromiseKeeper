# Mental model

PromiseKeeper is a persistent action runner:

- **Situation:** a stream that emits “something happened” occurrences over time.
- **Action:** a function you want to run when situations arrive.
- **Promise:** the durable promise definition that ties a situation to an action with a policy.

Lifecycle (typical):
1) At game startup (including after reload): register situations + actions (by id), then call `pk.remember()` to resume stored promises.
2) In situ: declare a promise (stores it and then starts looking for opportunities to fulfill it as situations come in). This can happen at any time during play.

PromiseKeeper intentionally does not sense the world. If you need probing/scanning or game logic (distance, room type), do it upstream (WorldObserver or your mod code) and emit situations from there.
