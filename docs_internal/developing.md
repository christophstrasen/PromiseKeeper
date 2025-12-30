# PromiseKeeper - Developing

Internal notes for working on PromiseKeeper locally.

## 1) Run tests (busted)

PromiseKeeper uses `busted` for headless tests.

From the PromiseKeeper repo root:

```bash
busted tests
```

Notes:
- These tests run outside the Project Zomboid engine.
- They validate persistence logic, policy semantics, and basic APIs.

## 2) Pre-commit (optional)

If you use `pre-commit`, install it and enable hooks:

```bash
pre-commit install
```

Then run:

```bash
pre-commit run --all-files
```

## 3) Building and syncing to Project Zomboid

PromiseKeeper is packaged as a standard Project Zomboid Build 42 mod under `Contents/`.

One-off deploy:

```bash
./dev/sync-workshop.sh
# or:
./dev/sync-mods.sh
```

Watch mode (defaults to Workshop wrapper deploy):

```bash
./dev/watch.sh
```

Notes:
- `./dev/watch.sh` defaults to `TARGET=workshop`. To deploy to `~/Zomboid/mods`, run: `TARGET=mods ./dev/watch.sh`
- You can override destinations with `PZ_WORKSHOP_DIR` / `PZ_MODS_DIR`.
