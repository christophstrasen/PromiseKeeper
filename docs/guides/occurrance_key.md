# Guide: occurranceKey (idempotence)

TODO (high priority):
- Plain guidance: “identity of the thing you mean”, not “time you saw it”.
- Collisions: within a promise, collisions suppress re-acting (expected).
- Recipes:
  - squares: `#square(x..y..z..)` or `squareId`
  - zombies: `zombieId`
  - event payloads: when `tostring(payload)` is safe vs not
- Anti-patterns: timestamp-as-id
- Focus on Events more than on WorldObserver but hint at worldObserver documentation about `:withOccurrenceKey` 