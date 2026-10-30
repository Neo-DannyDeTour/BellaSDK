---
name: automation
description: Automated 60 FPS performance, render pipeline, and scene misconfiguration audit runner for BellaSDK.
metadata:
  icon: schedule
---

# BellaSDK Performance & Architecture Automation Skill

Automated task runner for Principal Godot 4 Performance Engineer ("Bolt" ⚡).

## Activation
Trigger this skill anytime to execute an end-to-end 60 FPS audit:
- Prompt: `/automation` or `@automation` or `Run automated performance audit`

## Automated Execution Procedure

### Phase 1: Diagnostic Scan
Scans `.gd` and `.tscn` files across the 6 core bottlenecks (excluding `addons/`):
1. **Global `_process()` & `_physics_process()`**: Uncached tree traversals, continuous polling without signals, per-frame heap allocations (`Array`, `Dictionary`), un-culled distance checks (must use `distance_squared_to()`).
2. **SubViewport & Render Pipeline**: Verify `disable_3d = true` on 2D viewports, ensure `render_target_update_mode` uses `UPDATE_WHEN_VISIBLE` (2) instead of `UPDATE_ALWAYS` (4), check `SubViewportContainer.stretch` size coupling.
3. **Draw Calls & Batching**: Identify duplicate `MeshInstance3D` clusters for `MultiMeshInstance3D` batching, runtime `CSGShape3D` overhead, and unshared materials.
4. **Physics & Colliders**: Flag `0xFFFFFFFF` broad masks, `ConcavePolygonShape3D` on dynamic bodies, and `RigidBody3D.can_sleep == false`.
5. **Scene & Signal Leaks**: Vanished base scene overrides, redundant `.emit()` calls after UI setter mutations, and unsafe `as Type` casts leaking instantiated nodes.
6. **Code Rules**: Enforce strict typing, typed Callables, pre-allocated `StringName` constants (`&"name"`), and `gdlint` class ordering.

### Phase 2: Interrogation & Locked Spec
- Generate a Ranked Bottleneck Table (`file_path:line`, category, est. CPU ms / draw call impact, proposed fix).
- Formulate concrete recommendations and stress-test tradeoffs with the user before editing code.
- Wait for explicit user confirmation of the Locked Spec.

### Phase 3: Execute & Audit
- Apply complete, drop-in scripts and `.tscn` modifications.
- Run `gdlint` verification.
- Output required 1-2 line reply audit:
  - `- Skipped: [Omitted or unverified features/callers]`
  - `- Risk: [Concrete breaking assumptions or scene dependencies]`
