# IDs and keys

PromiseKeeper uses a small set of ids. Each has a different job:

- `namespace`: isolates your mod’s persisted state.
- `promiseId`: the stable id of the promise
- `situationKey`: the stable id of the situation definition (“where situations come from”).
- `occurranceKey`: the stable id of the specific situation occurrence (“the thing we acted on”).

Short version:
- `promiseId` identifies the promise.
- `occurranceKey` identifies the thing the promise should act on only once.

See:
- `guides/occurrance_key.md`
- `concepts/glossary.md`
