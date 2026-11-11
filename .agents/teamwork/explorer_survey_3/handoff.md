# Handoff Report: Explorer Survey 3 — Explosion Crysis VFX, Controller, and GUT Test Suite

## 1. Observation
1. **`ORIGINAL_REQUEST.md` (lines 26-34, 55-57)**:
   - R4 specifies root `Node3D` at `res://scenes/vfx/explosion_crysis.tscn` with controller script `res://scenes/vfx/explosion_crysis.gd`.
   - Child node specifications:
     - `CoreFireball` (GPUParticles3D): Amount 1, Lifetime 1.1s, one_shot true, explosiveness 1.0, QuadMesh (5.0m x 5.0m), unshaded StandardMaterial3D billboard using `res://assets/vfx/explosion/explosion_core_8x8.png` (H_frames 8, V_frames 8), ProcessMaterial with anim_speed 1.0, rapid scale-up (1.0 -> 3.2), alpha fade-out during final 20%.
     - `LingeringSmoke` (GPUParticles3D): Amount 12, Lifetime 3.5s, one_shot true, explosiveness 0.85, QuadMesh billboarded with soft particle blend, initial radial velocity 3.0 m/s with linear damp 4.0, gravity Vector3(0, 0.8, 0).
     - `SparksAndDebris` (GPUParticles3D): Amount 60, Lifetime 1.8s, one_shot true, explosiveness 0.98, QuadMesh (0.08m x 0.4m), particle billboard BILLBOARD_PARTICLES_ACCEL_Y, unshaded StandardMaterial3D with HDR albedo Color(5.0, 2.2, 0.4, 1.0), directional spread with +Z bias, initial velocity 22.0 m/s, gravity Vector3(0, -18.0, 0), collision mode COLLIDE_RIGID.
     - `DetonationFlash` (OmniLight3D): Warm orange Color(1.0, 0.6, 0.2), Energy 16.0, Range 25.0m, Tween collapses energy from 16.0 to 0.0 in 0.15s.
     - `HeatDistortion`: Child node utilizing `res://vfx/explosion_shockwave.gdshader` to produce screen refraction distortion during the initial blast phase.
     - Controller script coordinates one-shot emission triggers, handles flash tween, and manages lifecycle cleanup after all emitters complete.
   - GUT test script `test/unit/test_explosion_crysis.gd` must pass under headless GUT execution.
2. **`vfx/explosion_shockwave.gdshader` (lines 4-7, 14-27)**:
   - Uses `instance uniform float explosion_progress` and `instance uniform float distortion_strength`.
   - Calculates fresnel from `dot(NORMAL, VIEW)`, requiring a curved surface mesh (e.g. `SphereMesh`) rather than a flat quad to produce radial screen refraction rings.
3. **`vfx/vfx_smoke_flipbook.tscn` (lines 5-16, 32-33)** and **`vfx/smoke_puff.tscn` (lines 26-36)**:
   - Demonstrates Godot 4 flipbook setup: `StandardMaterial3D` with `billboard_mode = 3` (`BILLBOARD_PARTICLES`), `particles_anim_h_frames = 8`, `particles_anim_v_frames = 8`, `particles_anim_loop = false`, and `ParticleProcessMaterial` with `anim_speed_min = 1.0, anim_speed_max = 1.0`.
4. **Godot 4 Engine Introspection via CLI**:
   - `BaseMaterial3D.BillboardMode`: `BILLBOARD_DISABLED = 0`, `BILLBOARD_ENABLED = 1`, `BILLBOARD_FIXED_Y = 2`, `BILLBOARD_PARTICLES = 3`.
   - `ParticleProcessMaterial.ParticleFlags`: `PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY = 0` (property `particle_flag_align_y = true`).
   - `GPUParticles3D.TransformAlign`: `TRANSFORM_ALIGN_Y_TO_VELOCITY = 2`, `TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY = 3`.
5. **GUT CLI Execution Verification**:
   - Running `godot --headless -s addons/gut/gut_cmdln.gd -gtest=...` without `-gconfig=` attempts to load all configured directories from `.gutconfig.json` (`res://test/unit`).
   - Running with `-gconfig= -gtest=res://test/unit/test_collision_layers.gd -gexit` runs isolated tests in 0.437s and cleanly exits with exit code 0.
   - `project.godot` enforces `gdscript/warnings/unsafe_property_access=2` and `untyped_declaration=2`. Missing or untyped properties fail at the parser stage.

## 2. Logic Chain
1. *From Observation 1 and 3*: Flipbook sprite playback across 64 frames (8x8) over 1.1s is natively supported in Godot 4 by setting `StandardMaterial3D` billboard mode to 3 (`BILLBOARD_PARTICLES`), frames to 8x8, and `ParticleProcessMaterial` `anim_speed_min = 1.0` and `anim_speed_max = 1.0`. The rapid scale-up (1.0 -> 3.2) and final 20% alpha fade-out map directly to `scale_curve` and `alpha_curve` `CurveTexture` resources.
2. *From Observation 2*: Because `explosion_shockwave.gdshader` relies on `1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)` to compute its ring mask, a flat quad billboard facing the camera produces a uniform or zero fresnel. A `SphereMesh` provides radial surface normals that generate an expanding circular refraction ring when scaled up by the controller tween.
3. *From Observation 4*: Godot 4 does not have a literal enum constant `BILLBOARD_PARTICLES_ACCEL_Y` on `BaseMaterial3D`. Instead, Godot 4 provides `particle_flag_align_y = true` on `ParticleProcessMaterial` and `transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY` with elongated `QuadMesh(0.08, 0.4)`. This aligns sparks along their velocity trajectory with ground rigid collision.
4. *From Observation 1 and 5*: The controller script `res://scenes/vfx/explosion_crysis.gd` must expose `auto_play`, `free_on_finish`, and explicit typed properties/methods so the GUT test suite `test/unit/test_explosion_crysis.gd` can disable `auto_play` during property inspections without triggering parser errors under `unsafe_property_access=2`.
5. *From Observation 5*: Headless automated testing requires `-gconfig=` and `-gexit` to execute strictly the target test file and exit automatically.

## 3. Caveats
1. **Asset Generation Timing**: `res://scenes/vfx/explosion_crysis.tscn` depends on `res://assets/vfx/explosion/explosion_core_8x8.png`. If the scene is parsed before R3 (spritesheet assembly) completes and imports, Godot will report a missing dependency.
2. **Global Particle Collision Support**: `SparksAndDebris` specifies `COLLISION_RIGID`. In Godot 4, GPU particle collision requires a `GPUParticlesCollisionHeightField3D` or `GPUParticlesCollisionBox3D` in the scene or level to physically bounce. Without a collision volume, particles follow ballistic trajectories and gravity cleanly without crashing.

## 4. Conclusion
The scene `res://scenes/vfx/explosion_crysis.tscn`, controller script `res://scenes/vfx/explosion_crysis.gd`, and GUT unit test `test/unit/test_explosion_crysis.gd` are completely specified and ready for the implementation phase. Full specifications and draft implementations are documented in `.agents/teamwork/explorer_survey_3/analysis.md`.

## 5. Verification Method
1. **Inspect Analysis and Scene Specs**:
   - View `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_3/analysis.md` for exact node parameters and code drafts.
2. **Execute Headless Unit Test (Post-Implementation)**:
   ```bash
   godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/unit/test_explosion_crysis.gd -gexit
   ```
   *Expected result*: Exit code 0, 8 passing tests, 0 failed tests, 0 errors.
3. **Invalidation Conditions**:
   - Any missing child node (`CoreFireball`, `LingeringSmoke`, `SparksAndDebris`, `DetonationFlash`, `HeatDistortion`).
   - Any untyped declaration or `unsafe_property_access` warning treated as error by `project.godot`.
   - GUT test hanging indefinitely (missing `-gexit`).
