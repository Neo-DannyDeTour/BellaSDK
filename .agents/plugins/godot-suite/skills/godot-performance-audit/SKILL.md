---
name: godot-performance-audit
description: Run 60 FPS Performance, Render Pipeline & Scene Misconfiguration Audit + Fix on Godot 4 scripts and scenes.
---

# 60 FPS Performance, Render Pipeline & Scene Misconfiguration Audit

Execute a structured 3-phase performance audit across all `.gd` and `.tscn` files (excluding `addons/`). Follow all rules in `GEMINI.md`.

## Target Metrics
- CPU script execution budget: < 4 ms
- Draw call count: < 600 calls
- Strict typing, zero warnings, and `gdlint` compliance

---

## Phase 1: Diagnostic Scan (6 Focus Areas)

Scan `.gd` and `.tscn` files across:

1. **Global `_process()` & `_physics_process()` Bottlenecks**:
   - Continuous polling that should use Signals or throttled timers (5-10 Hz).
   - Per-tick tree traversals (`get_node()`, `find_child()`, `get_children()`, `get_nodes_in_group()`) missing `@onready` caching or `NodeQuery`.
   - Per-frame heap allocations (`Array`, `Dictionary`, string formatting, `SurfaceTool`/`ImmediateMesh` rebuilds).
   - Missing `VisibleOnScreenNotifier3D` or `distance_squared_to()` process culling (`set_process(false)`).
   - `diagnostics_panel.gd` or UI scripts querying engine monitors or formatting strings every frame instead of every 0.2s.

2. **SubViewport & Render Pipeline Misconfigurations**:
   - Direct `SubViewport.size` mutation while parent `SubViewportContainer.stretch == true`.
   - 2D/UI `SubViewport` nodes missing `disable_3d = true`.
   - Secondary viewports (mirrors, minimaps, security cams, inactive tabs) running `UPDATE_ALWAYS` instead of `UPDATE_WHEN_VISIBLE` / `UPDATE_ONCE`.
   - Secondary viewports inheriting heavy root `WorldEnvironment` (SDFGI, SSAO, SSIL, Volumetric Fog) or lacking `positional_shadow_atlas_size` / `msaa_3d` / `stretch_shrink` clamps.
   - Destructive camera/environment overrides failing to cache and restore pre-debug state.

3. **Draw Calls, Geometry & Batching (< 600 Draw Call Target)**:
   - Dense duplicate `MeshInstance3D` clusters (`DestructibleGlass`, `animated_cube_wall`, `ProceduralBarbwire`, `ClimableRope`, `FastRope`, `PhysicsCableGenerator`, `DoubleCable`) that should batch via `MultiMeshInstance3D`.
   - Runtime `CSGShape3D` nodes incurring dynamic rebuild/physics overhead instead of static meshes.
   - Unique material instances breaking batching instead of `set_instance_shader_parameter()` or `MaterialCache`.
   - Shadow-casting lights multiplying passes across dense clusters.

4. **Physics & Collider Hazards**:
   - Broad collision masks (`0xFFFFFFFF`) instead of `CollisionLayers.MASK_*`.
   - Dynamic bodies (`RigidBody3D`, `CharacterBody3D`) using `ConcavePolygonShape3D` trimeshes instead of primitive/convex shapes.
   - `RigidBody3D` nodes with `can_sleep = false`.

5. **Scene Inheritance, Signal & Node Leaks**:
   - `.tscn` files with vanished node overrides from base scenes.
   - Redundant `.emit()` calls after setting native UI properties (`HSlider.value`, `BaseButton.button_pressed`).
   - `PackedScene.instantiate()` cast via `as Type` where a `null` cast leaks unparented nodes without `queue_free()`.
   - Pause controllers (`toggle_pause()`) set to `PROCESS_MODE_INHERIT` instead of `PROCESS_MODE_ALWAYS`.

6. **Godot 4 Architecture Rules**:
   - Verify `distance_squared_to()` used for proximity checks.
   - Verify pre-allocated `StringName` constants (`&"name"`).
   - Ensure signals connect via typed Callables (`Events.signal.connect(_on_signal)`).
   - Enforce explicit static typing on all declarations.

---

## Phase 2: Interrogate & Lock Spec

1. Present a **Ranked Bottleneck Table** (`file_path:line`, category, est. CPU ms / draw call impact, proposed fix).
2. Interrogate the user on architectural tradeoffs (e.g., `MultiMeshInstance3D` batching vs. dynamic rigid body simulation).
3. Wait for explicit confirmation of the Locked Spec before modifying code.

---

## Phase 3: Execute & Verify

1. Apply approved fixes across `.gd` and `.tscn` files.
2. Run `gdlint` and verify zero errors.
3. Conclude with a 1-2 line reply audit:
   - `- Skipped: [What features, options, or callers were omitted or unverified]`
   - `- Risk: [Concrete breaking assumptions, scene dependencies, or edge cases]`
