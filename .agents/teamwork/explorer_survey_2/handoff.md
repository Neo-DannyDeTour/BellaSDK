# Handoff Report: VFX Conventions, Shader Mechanics & BellaSDK Architecture Survey

**Agent**: Explorer Survey 2
**Date**: 2026-11-11
**Handoff Type**: Hard (Task Complete)
**Target Directory**: `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/`

---

## 1. Observation

1. **`res://vfx/explosion_shockwave.gdshader`**:
   - Declared as `shader_type spatial;` with `render_mode blend_mix, depth_draw_never, cull_back, unshaded;` (lines 1-2).
   - Uniforms:
     - `uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;` (line 4).
     - `instance uniform float explosion_progress : hint_range(0.0, 1.0) = 0.0;` (line 5).
     - `instance uniform float distortion_strength : hint_range(0.0, 0.15) = 0.045;` (line 6).
     - `uniform float aberration_amount : hint_range(0.0, 0.03) = 0.008;` (line 7).
   - Ring calculation: `float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0); float ring_mask = smoothstep(0.25, 0.78, fresnel) * smoothstep(1.0, 0.82, fresnel);` (lines 14-15).
   - Screen sampling: `texture(screen_texture, SCREEN_UV + offset * (1.0 + aberration_amount)).r` (lines 22-24).
   - Mesh expectation: Requires curved 3D geometry (`SphereMesh`). On a flat QuadMesh, `dot(NORMAL, VIEW) == 1.0`, resulting in `fresnel == 0.0` and `ring_mask == 0.0` (zero refraction).

2. **`res://test/unit/test_smoke_explosion_vfx.gd`**:
   - GUT Test extending `GutTest` (lines 2-3).
   - Loads scene via `load(SMOKE_SCENE_PATH) as PackedScene` and calls `add_child_autofree(instance)` (lines 10-15).
   - Testing invocation via CLI: `godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_smoke_explosion_vfx -gexit`.
   - Result: Failed with Godot GDScript Parse Error:
     ```
     SCRIPT ERROR: Parse Error: The property "preview_active" is not present on the inferred type "SmokeExplosionVfx" (but may be present on a subtype). (Warning treated as error.)
     at: GDScript::reload (res://test/unit/test_smoke_explosion_vfx.gd:35)
     ```
     Also failed on undeclared properties `loop` and `loop_interval`.
   - Control test `res://test/unit/test_collision_layers.gd` passed 3/3 tests in 0.406s under `godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_collision_layers -gexit`.

3. **Existing VFX Scenes & Flipbooks**:
   - `res://vfx/vfx_smoke_flipbook.tscn`: Uses `StandardMaterial3D` with `billboard_mode = 3` (`BILLBOARD_PARTICLES`), `particles_anim_h_frames = 8`, `particles_anim_v_frames = 8`, `particles_anim_loop = false`, with `QuadMesh` and `ParticleProcessMaterial` (`anim_speed_min = 1.0`, `anim_speed_max = 1.0`).
   - `res://vfx/smoke_explosion.tscn`: Uses `QuadMesh` (size 0.06 x 0.45) with `particle_flag_align_y = true` for ballistic sparks, and `MeshInstance3D` with `SphereMesh` (radius 1.0, height 2.0, radial_segments 32, rings 16) for shockwave refraction.
   - `generate_vertical_smoke_flipbook.py`: Demonstrates headless Blender 4.x Mantaflow setup with `BLENDER_EEVEE` / `BLENDER_EEVEE_NEXT`, Principled Volume emission driven by attributes, and orthographic rendering.

4. **BellaSDK Architectural Constraints (`GEMINI.md`, `.gdlintrc`, `res://core/`)**:
   - Strict typing: `untyped_declaration = 2`, `unsafe_property_access = 2`, `unsafe_method_access = 2`, `inferred_declaration = 1` (no `:=`), `unsafe_cast = 1` (no `as` on Variant or primitives). Zero tolerance for `@warning_ignore`.
   - Formatting: Max line length 100 characters, strict tab indentation, zero trailing whitespace.
   - Variable naming: Local function variables must NEVER start with a leading underscore (`_`).
   - Lifecycle & tweens: Disable `_process` and `_physics_process` in `_ready()`; manage tweens via `Utilities.reset_tween(self, _active_tween)` and kill in `_exit_tree()`.
   - Pre-allocate `StringName` constants (`&"explosion_progress"`, `&"distortion_strength"`).
   - Mandatory BBCode `##` docstrings <= 100 chars above every declaration.

---

## 2. Logic Chain

1. **Shockwave Geometry Requirement**:
   - Observation 1 demonstrates that `res://vfx/explosion_shockwave.gdshader` calculates distortion ring opacity using `fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)`.
   - On a planar Quad facing the camera, `NORMAL` is parallel to `VIEW`, making `dot(NORMAL, VIEW) = 1.0`, so `fresnel = 0.0` and `ring_mask = 0.0`.
   - Therefore, the shockwave node (`HeatDistortion`) must use a 3D curved mesh (`SphereMesh`), as corroborated by `ControlExplosion` (`res://vfx/effects/control_explosion.gd`: line 340) and `SmokeExplosionVfx` (`res://vfx/smoke_explosion.tscn`: line 163).

2. **GUT Test Construction & Safety**:
   - Observation 2 demonstrates that in Godot 4.7 with BellaSDK's warning settings, referencing undeclared properties on an instantiated typed scene produces a fatal compile-time Parse Error.
   - Therefore, the new GUT test `test/unit/test_explosion_crysis.gd` must only assert on properties, exported variables, and child nodes that are explicitly declared and typed on `res://scenes/vfx/explosion_crysis.gd`.

3. **Composite Explosion Node Hierarchy**:
   - Comparing ORIGINAL_REQUEST.md requirements with Observation 3 confirms the standard structure:
     - `CoreFireball`: `GPUParticles3D` with QuadMesh, `StandardMaterial3D` unshaded, `billboard_mode = 3`, 8x8 frames, `anim_speed = 1.0`.
     - `LingeringSmoke`: `GPUParticles3D` with QuadMesh, `StandardMaterial3D` soft blend, `billboard_mode = 3`.
     - `SparksAndDebris`: `GPUParticles3D` with elongated QuadMesh, `particle_flag_align_y = true`, HDR albedo `Color(5.0, 2.2, 0.4, 1.0)`.
     - `DetonationFlash`: `OmniLight3D` with Tween energy decay (16.0 -> 0.0 in 0.15s).
     - `HeatDistortion`: `MeshInstance3D` with `SphereMesh` and `res://vfx/explosion_shockwave.gdshader`.

4. **Engine Rules Compliance**:
   - From Observation 4, all code for `explosion_crysis.gd` and `test_explosion_crysis.gd` must be strictly typed without `:=`, without leading underscores on local variables, with 100% docstrings, and using `Utilities.reset_tween()`.

---

## 3. Caveats

1. **Existing Test Failure**: `res://test/unit/test_smoke_explosion_vfx.gd` currently fails in the repository due to pre-existing missing properties on `SmokeExplosionVfx`. We did not modify `test_smoke_explosion_vfx.gd` as our role is strictly read-only investigation.
2. **Blender EEVEE Next vs EEVEE**: In Blender 4.2+, EEVEE has been overhauled to EEVEE Next. The Python bake script `tools/generate_explosion_flipbook.py` should query available engines (`BLENDER_EEVEE_NEXT`, `BLENDER_EEVEE`, `CYCLES`) dynamically.

---

## 4. Conclusion

The VFX conventions, shader mechanics, and BellaSDK project rules are fully mapped and verified. Downstream implementation agents have complete specifications:
- `res://vfx/explosion_shockwave.gdshader` requires a `SphereMesh` on `HeatDistortion` modulated via `set_instance_shader_parameter()`.
- `res://scenes/vfx/explosion_crysis.tscn` must implement the 5 synchronized child nodes (`CoreFireball`, `LingeringSmoke`, `SparksAndDebris`, `DetonationFlash`, `HeatDistortion`) following Godot 4 flipbook and particle billboard standards.
- `res://scenes/vfx/explosion_crysis.gd` and `test/unit/test_explosion_crysis.gd` must strictly satisfy BellaSDK zero-warning typing, `.gdlintrc` formatting, and GUT test patterns.

---

## 5. Verification Method

1. **Verify Shader Uniforms & Fresnel Mechanics**:
   ```bash
   grep -n -E "shader_type|uniform|fresnel|ring_mask" vfx/explosion_shockwave.gdshader
   ```
2. **Verify Working GUT Test Pattern**:
   ```bash
   godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_collision_layers -gexit
   ```
   (Must output `3/3 passed` with exit code 0).
3. **Verify GDLint Rules**:
   ```bash
   cat .gdlintrc
   ```
4. **Invalidation Condition**:
   - If `HeatDistortion` is assigned a flat QuadMesh, refraction will be completely invisible.
   - If `test_explosion_crysis.gd` accesses undeclared properties, Godot compiler will abort with Parse Error.
