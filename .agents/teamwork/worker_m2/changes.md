# Changes Summary: Milestone 2 (Godot 4 Composite Explosion Hierarchy & Controller)

## Files Created
1. `res://scenes/vfx/explosion_crysis.gd`:
   - Class: `ExplosionCrysis` extending `Node3D`.
   - Signals: `detonation_started(origin: Vector3)`, `detonation_finished(explosion_node: ExplosionCrysis)`.
   - Pre-allocated StringName constants: `PARAM_PROGRESS = &"explosion_progress"`, `PARAM_DISTORTION = &"distortion_strength"`.
   - Timing & Energy constants: `FLASH_PEAK_ENERGY = 16.0`, `FLASH_DURATION = 0.15`, `FIREBALL_DURATION = 1.1`, `SHOCKWAVE_DURATION = 0.4`, `MAX_PARTICLE_LIFETIME = 3.5`, `CLEANUP_BUFFER = 0.3`.
   - Exports: `@export var auto_play: bool = true`, `@export var free_on_finish: bool = true`.
   - Cached `@onready` node references:
     - `core_fireball: GPUParticles3D = $CoreFireball`
     - `lingering_smoke: GPUParticles3D = $LingeringSmoke`
     - `sparks_and_debris: GPUParticles3D = $SparksAndDebris`
     - `detonation_flash: OmniLight3D = $DetonationFlash`
     - `heat_distortion: MeshInstance3D = $HeatDistortion`
   - Public methods:
     - `explode() -> void`: Synchronizes all emitters, sets flash energy to 16.0, initiates parallel tween decay, scales shockwave sphere from 0.2 to 12.0 and drives `explosion_progress` from 0.0 to 1.0, and schedules lifecycle cleanup.
     - `detonate() -> void`: Compatibility alias for `explode()`.
     - `reset() -> void`: Ceases emissions, hides flash/shockwave, resets properties, and cleanly terminates active tweens.
   - Lifecycle safety:
     - Disabled `_process()` and `_physics_process()` in `_ready()`.
     - Active and cleanup tweens safely managed via `Utilities.reset_tween()` and killed in `_exit_tree()`.
   - GDLint & static typing compliance:
     - 100% strictly typed (no `:=`, no Variant inference, no `@warning_ignore`).
     - Strict tab indentation, max line length <= 100, no trailing whitespace.
     - Mandatory `##` docstrings on all declarations.

2. `res://scenes/vfx/explosion_crysis.tscn`:
   - Composite explosion hierarchy with 5 synchronized child nodes:
     - `CoreFireball` (`GPUParticles3D`): `amount = 1`, `lifetime = 1.1`, `one_shot = true`, `explosiveness = 1.0`, `QuadMesh` 5.0m x 5.0m, unshaded `StandardMaterial3D` with `billboard_mode = 3` (BILLBOARD_PARTICLES), `particles_anim_h_frames = 8`, `particles_anim_v_frames = 8`, `albedo_texture = res://assets/vfx/explosion/explosion_core_8x8.png` (uid://mpc6axbfwyt3), `ParticleProcessMaterial` with `anim_speed = 1.0`, scale curve (1.0 -> 3.2), alpha curve (fading final 20%).
     - `LingeringSmoke` (`GPUParticles3D`): `amount = 12`, `lifetime = 3.5`, `one_shot = true`, `explosiveness = 0.85`, `QuadMesh` 3.5m x 3.5m, billboarded `StandardMaterial3D` with `proximity_fade_enabled = true` (0.6m soft fade), `ParticleProcessMaterial` with `radial_velocity = 3.0 m/s`, `damping = 4.0`, buoyant `gravity = Vector3(0, 0.8, 0)`.
     - `SparksAndDebris` (`GPUParticles3D`): `amount = 60`, `lifetime = 1.8`, `one_shot = true`, `explosiveness = 0.98`, `transform_align = 2` (TRANSFORM_ALIGN_Y_TO_VELOCITY), `QuadMesh` 0.08m x 0.4m, unshaded `StandardMaterial3D` with HDR `albedo_color = Color(5.0, 2.2, 0.4, 1.0)`, `ParticleProcessMaterial` with `particle_flag_align_y = true`, directional spread with +Z bias, initial velocity 20-24 m/s, `gravity = Vector3(0, -18.0, 0)`, `collision_mode = 1` (COLLISION_RIGID).
     - `DetonationFlash` (`OmniLight3D`): `light_color = Color(1.0, 0.6, 0.2)`, `light_energy = 16.0`, `omni_range = 25.0m`, `omni_attenuation = 1.5`, `shadow_enabled = true`.
     - `HeatDistortion` (`MeshInstance3D`): `SphereMesh` (radius 1.0m, height 2.0m, 32 radial segments, 16 rings), `layers = 512` (Render Layer 10 Volumetrics), `ShaderMaterial` referencing `res://vfx/explosion_shockwave.gdshader` (uid://dbuao7wa4enfq).
