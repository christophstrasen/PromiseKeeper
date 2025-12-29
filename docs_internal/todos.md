# PromiseKeeper — Todos (must do)

This file is intentionally short: only the work we should do next with high confidence.

## Docs and onboarding
- Write a short “PromiseKeeper in 5 minutes” quickstart (1 page): mental model + one event example + one WorldObserver example.
- Add a dedicated `occurranceKey` guide (what it means, collisions, stability recipes).

## Validation
- Verify persistence + behavior in multiplayer (where ModData lives, and what should run client vs server).
- Add one real gameplay example (not a smoke) that demonstrates a full pattern (interest → situation → promise → action).

## Tooling
- Tighten diagnostics output for “broken” promises (make the missing registration / missing situationKey case obvious).



Please craft a really good `external/PromiseKeeper/readme.md`. Which is the first impression anyone will get for PromiseKeeper. It should answer in the first 40 seconds.
1. What is this
2. For whom is this
3. When would I want to use this (and when not, honest expectation management e.g. not designer for and not tested in Multiplayer)
4. How can I get started (showing real code)

Overall, and especially for these top points the tone should be not too braggy and every statement should be "specific" and not fluff just to fill lines. Ideally we use one strong sentence right at the beginning that makes the contract clear and gives the "A-ha!"

In the next 60 seconds of reading it should establish more facts in this order
5. Further documentation (User facing and Internal)
6. What is good or unique about Promisekeeper (here it can be a bit more braggy but honest)
7. Contributing
8. AI Disclosuree
9. Disclaimer

You can take inspiration from the WorldObserver and the LQR readmes which are strong.