## 2026-11-11T05:56:19Z
You are Worker 2 for Milestone 2: Godot 4 Composite Explosion Hierarchy & Controller.

Working directory: /home/dkd/Documents/BellaSDK/.agents/teamwork/worker_m2/
Create your files (progress.md, changes.md, handoff.md) inside this working directory.

MANDATORY FIRST STEPS:
1. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/ORIGINAL_REQUEST.md
2. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/orchestrator/PROJECT.md and /home/dkd/Documents/BellaSDK/.agents/teamwork/orchestrator/TEST_INFRA.md
3. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/test_writer_et1/handoff.md and /home/dkd/Documents/BellaSDK/test/unit/test_explosion_crysis.gd
4. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/handoff.md and /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_3/handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Write ownership:
You exclusively own and may create/modify:
- /home/dkd/Documents/BellaSDK/scenes/vfx/explosion_crysis.tscn
- /home/dkd/Documents/BellaSDK/scenes/vfx/explosion_crysis.gd
Do NOT modify any files in test/ or assets/ or tools/.

Task Specifications (Milestone 2):
Create `res://scenes/vfx/explosion_crysis.tscn` and controller script `res://scenes/vfx/explosion_crysis.gd`:
1. Root Node:
   - Type: `Node3D`, script `res://scenes/vfx/explosion_crysis.gd`, class_name `ExplosionCrysis`.
2. Child Nodes (exact names and types required):
   - `CoreFireball` (GPUParticles3D):
     - Amount = 1, Lifetime = 1.1s, one_shot = true, explosiveness = 1.0.
     - Draw pass 1: QuadMesh (size 5.0m x 5.0m).
     - Material: Unshaded StandardMaterial3D, billboard_mode = 3 (BILLBOARD_PARTICLES), particles_anim_h_frames = 8, particles_anim_v_frames = 8, particles_anim_loop = false, albedo_texture = `res://assets/vfx/explosion/explosion_core_8x8.png`.
     - ProcessMaterial: anim_speed_min = 1.0, anim_speed_max = 1.0, scale_curve (rapid scale-up from 1.0 to 3.2), alpha_curve (linear/curve fading out alpha during the final 20% of life).
   - `LingeringSmoke` (GPUParticles3D):
     - Amount = 12, Lifetime = 3.5s, one_shot = true, explosiveness = 0.85.
     - Draw pass 1: QuadMesh (size 3.5m x 3.5m).
     - Material: StandardMaterial3D billboarded (billboard_mode = 3 or 1), proximity_fade_enabled = true (soft particle blend), transparency = 1 (alpha blend).
     - ProcessMaterial: initial radial velocity 3.0 m/s, linear damp = 4.0, gravity = Vector3(0, 0.8, 0).
   - `SparksAndDebris` (GPUParticles3D):
     - Amount = 60, Lifetime = 1.8s, one_shot = true, explosiveness = 0.98.
     - Draw pass 1: QuadMesh (size 0.08m x 0.4m).
     - Transform align: `transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY` (or particle_flag_align_y = true).
     - Material: Unshaded StandardMaterial3D with HDR albedo Color(5.0, 2.2, 0.4, 1.0).
     - ProcessMaterial: directional spread with +Z bias, initial velocity = 22.0 m/s, gravity = Vector3(0, -18.0, 0), collision_mode = GPUParticles3D.COLLISION_RIGID.
   - `DetonationFlash` (OmniLight3D):
     - Color: Color(1.0, 0.6, 0.2), Energy = 16.0, Range = 25.0m.
     - Tween collapses energy from 16.0 to 0.0 in 0.15s upon explosion.
   - `HeatDistortion` (MeshInstance3D):
     - Geometry: SphereMesh (radius 1.0m, height 2.0m, radial_segments 32, rings 16).
     - Layers: Layer 10 Volumetrics (`layers = 512` or CollisionLayers.RENDER_MASK_VOLUMETRICS).
     - Material: ShaderMaterial using `res://vfx/explosion_shockwave.gdshader`.
     - Shockwave tween: Controller drives `explosion_progress` from 0.0 to 1.0 and scales SphereMesh from 0.2 to 12.0 over ~0.4s.
3. Controller Script `res://scenes/vfx/explosion_crysis.gd`:
   - Enforce BellaSDK standards:
     - Strict typing: `untyped_declaration = 2`, `inferred_declaration = 1` (NO `:=`), zero `@warning_ignore`.
     - `.gdlintrc` formatting: max line length <= 100, strict tab indentation, no trailing whitespace, class definitions order, no leading underscores on local variables.
     - Mandatory `##` docstrings <= 100 chars above every class, signal, constant, export, var, and func.
     - Event-driven: disable `_process` and `_physics_process` in `_ready()`.
     - Tweens: use native Tween or `Utilities.reset_tween()`, kill existing tweens on re-trigger or exit tree. Pre-allocate `StringName` constants (`&"explosion_progress"`, `&"distortion_strength"`).
     - Exports: `@export var auto_play: bool = true`, `@export var free_on_finish: bool = true`.
     - Methods: `explode() -> void`, `reset() -> void`.
     - Lifecycle cleanup: if `free_on_finish` is true, queues free after maximum lifetime (3.5s + 0.3s safety buffer) via a one-shot SceneTreeTimer or Tween callback.
     - When `reset()` is called, stops emitters, restores initial flash/heat distortion properties, and cancels active tweens/timers.

Verification Requirements:
1. Run `gdlint scenes/vfx/explosion_crysis.gd` -> 0 errors.
2. Run `godot --headless --check-only -s res://scenes/vfx/explosion_crysis.gd` -> exit code 0.
3. Run `godot --headless --editor --quit` -> generates UID and import metadata.
4. Run GUT test suite:
   `godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/unit/test_explosion_crysis.gd -gexit`
   All 16 tests must pass cleanly with exit code 0!
5. Document all commands and results in `handoff.md` and notify orchestrator when done.
