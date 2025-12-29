# Troubleshooting (and diagnostics)

TODO:
- **Diagnostics (status / whyNot / broken)**
  - `promise.status()`, `promise.whyNot(occurranceKey)`
  - typical “nothing happens” causes:
    - missing interest upstream (WO)
    - missing situation/action registration at boot
    - missing/unstable occurranceKey
- **Common pitfalls**
  - “I see no logs” checklist
  - “It worked once and never again” (maxRuns / collisions / cooldown)
  - “It runs too often” (unstable occurranceKey)
  - “It doesn’t resume after reload” (missing `remember()` call at boot)
