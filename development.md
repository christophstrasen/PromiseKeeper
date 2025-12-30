# PromiseKeeper — Development

PromiseKeeper is part of the DREAM mod family (Build 42):
- DREAM-Workspace (multi-repo convenience): https://github.com/christophstrasen/DREAM-Workspace

## Quickstart (single repo)

Prereqs: `rsync`, `inotifywait` (`inotify-tools`), `inkscape`.

Watch + deploy (default: Workshop wrapper under `~/Zomboid/Workshop`):

```bash
./dev/watch.sh
```

Switch destination:

```bash
TARGET=mods ./dev/watch.sh
```

## Tests

PromiseKeeper has headless unit tests:

```bash
busted tests
```

