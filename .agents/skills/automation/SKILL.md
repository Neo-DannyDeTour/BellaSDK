---
name: automation
description: Automated 60 FPS performance, architecture, gdlint, and Godot headless verification orchestrator for BellaSDK.
metadata:
  icon: schedule
---

# BellaSDK Performance & Verification Automation (`/automation`)

Single entrypoint orchestrating `godot-suite` audit skills (`godot-performance-audit`, `godot-arch-check`, `godot-lint`) plus CLI verification.

## Activation
- Prompt: `/automation`, `@automation`, or `Run automated performance audit`

---

## Automated Workflow

### Phase 1: Parallel Diagnostic Scan (Using `godot-suite`)
Run the checklists defined in:
1. [godot-performance-audit](file:///home/dkd/Documents/BellaSDK/.agents/plugins/godot-suite/skills/godot-performance-audit/SKILL.md) (6 focus areas: `_process` hotspots, `SubViewport`, batching `< 600` draw calls, `CollisionLayers`, leaks, static typing).
2. [godot-arch-check](file:///home/dkd/Documents/BellaSDK/.agents/plugins/godot-suite/skills/godot-arch-check/SKILL.md) (`NodeQuery`, `AudioPool`, `MaterialCache`, `MathUtils`, `Utilities`, Render/Physics layers).
3. Static CLI lint scan (excluding `addons/`):
```bash
gdlint $(find . -name "*.gd" -not -path "./addons/*" -not -path "./.godot/*")
```

### Phase 2: Ranked Findings & Locked Spec Gate
- Output a **Ranked Bottleneck Table** (`file_path:line`, category, est. CPU ms / draw call / safety impact, proposed fix).
- Grill user on architectural tradeoffs using 1 tight round with recommended answers.
- Wait for explicit `"go"` on the Locked Spec before editing `.gd` or `.tscn` files.

### Phase 3: Execute & Verify
1. Apply complete drop-in fixes following [godot-lint](file:///home/dkd/Documents/BellaSDK/.agents/plugins/godot-suite/skills/godot-lint/SKILL.md) and `GEMINI.md` rules.
2. Re-run `gdlint` on all modified `.gd` files and run Godot headless verification:
```bash
godot --headless --quit --path .
```
3. Conclude with the mandatory 2-line audit:
   - `Skipped: [Features, scenes, or callers omitted or unverified]`
   - `Risk: [Concrete breaking assumptions, scene dependencies, or edge cases]`
