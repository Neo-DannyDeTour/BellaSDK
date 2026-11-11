## 2026-11-11T05:24:52Z
You are Explorer 3 for the Project Survey phase.
Your working directory is: /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_3/
You must create your working directory files (e.g. progress.md, analysis.md, handoff.md) inside this directory.

MANDATORY FIRST STEP: Read /home/dkd/Documents/BellaSDK/.agents/teamwork/ORIGINAL_REQUEST.md before doing anything else.

Your objective:
Investigate specifications and design for `res://scenes/vfx/explosion_crysis.tscn`, controller script `res://scenes/vfx/explosion_crysis.gd`, and GUT test suite `test/unit/test_explosion_crysis.gd`.
Specifically:
1. Break down all child nodes and exact properties required by R4 in `ORIGINAL_REQUEST.md`:
   - `CoreFireball` (GPUParticles3D): Amount = 1, Lifetime = 1.1s, one_shot = true, explosiveness = 1.0. QuadMesh (5.0m x 5.0m), unshaded StandardMaterial3D billboard using `res://assets/vfx/explosion/explosion_core_8x8.png` (H_frames = 8, V_frames = 8). ProcessMaterial with anim_speed = 1.0, rapid scale-up (1.0 -> 3.2), alpha fade-out during final 20%. Check how Godot 4 ParticleProcessMaterial handles flipbook animation (`anim_speed`, `anim_speed_curve`, `anim_offset`, particle flags, billboard mode).
   - `LingeringSmoke` (GPUParticles3D): Amount = 12, Lifetime = 3.5s, one_shot = true, explosiveness = 0.85. QuadMesh billboarded with soft particle blend. Initial radial velocity 3.0 m/s with linear damp = 4.0, gravity = Vector3(0, 0.8, 0).
   - `SparksAndDebris` (GPUParticles3D): Amount = 60, Lifetime = 1.8s, one_shot = true, explosiveness = 0.98. QuadMesh (0.08m x 0.4m), particle billboard BILLBOARD_PARTICLES_ACCEL_Y. Unshaded StandardMaterial3D with HDR albedo Color(5.0, 2.2, 0.4, 1.0). Directional spread with +Z bias, initial velocity = 22.0 m/s, gravity = Vector3(0, -18.0, 0), collision mode = COLLIDE_RIGID (or ground bounce).
   - `DetonationFlash` (OmniLight3D): Warm orange Color(1.0, 0.6, 0.2), Energy = 16.0, Range = 25.0m. Tween collapses energy from 16.0 to 0.0 in 0.15s.
   - `HeatDistortion`: Child node utilizing `res://vfx/explosion_shockwave.gdshader` to produce screen refraction distortion during the initial blast phase. Determine node type (MeshInstance3D with QuadMesh / sphere mesh / etc.) and how controller script drives the shockwave progress/radius over time.
   - Controller script `res://scenes/vfx/explosion_crysis.gd`: Coordinates one-shot emission triggers, handles the `DetonationFlash` tween, and manages lifecycle cleanup after all particle emitters complete (e.g. queue_free() after max lifetime or timer).
2. Design the GUT test `test/unit/test_explosion_crysis.gd`:
   - Scene instantiation check.
   - Child node presence and types (`CoreFireball`, `LingeringSmoke`, `SparksAndDebris`, `DetonationFlash`, `HeatDistortion`).
   - Default property values verification (lifetimes, amounts, one_shot, explosiveness, light energy/color/range).
   - Triggering explosion execution and verifying tween / emission state changes.
   - Headless test execution command and expectations.
3. Record all findings in `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_3/analysis.md` and provide a complete handoff report in `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_3/handoff.md`.
4. Send a completion message to orchestrator with summary and links to the files.
