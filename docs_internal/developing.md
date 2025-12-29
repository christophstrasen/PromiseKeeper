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

@TODO: Document how we package/sync PromiseKeeper for in-game testing.
@TODO: Document how to run in-game smoke scripts (if/when we keep them).

