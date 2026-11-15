---
name: godot-lint
description: Lint and format GDScript files according to the project's .gdlintrc and formatting constraints.
---

# Godot Lint & Format Workflow

Use this skill whenever checking or cleaning up GDScript code in the BellaSDK workspace.

## Reference Configuration
- Config file: [`.gdlintrc`](file:///home/dkd/Documents/BellaSDK/.gdlintrc)
- Max line length: 100 characters.
- Tabs: 1 tab indentation.
- Excluded paths: `.git`, `TESTS(delete later)`, `addons`.

## Execution Runbook

### 1. Verification with gdlint
Run gdlint against modified or target scripts:
```bash
gdlint scripts/
```

### 2. Format with gdformat
```bash
gdformat scripts/<target_file>.gd
```

### 3. Strict Rule Invariants
- Max line length 100 chars, tabs (`1` tab), zero trailing whitespace.
- Local function variables must NEVER start with a leading underscore `_`.
- Strict static typing required on all variables, signal signatures, and return types (`-> void`).
