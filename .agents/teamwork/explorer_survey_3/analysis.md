# Technical Analysis: Godot 4 Explosion Crysis VFX Hierarchy, Controller, and GUT Test Suite

## Executive Summary
This document provides the exhaustive specification for the R4 composite explosion system (`res://scenes/vfx/explosion_crysis.tscn`), its controller script (`res://scenes/vfx/explosion_crysis.gd`), and its headless verification suite (`test/unit/test_explosion_crysis.gd`). The design strictly follows BellaSDK architecture rules: 60 FPS event-driven lifecycle, pre-allocated StringNames, zero per-frame allocations, strict GDScript static typing (`untyped_declaration=2`, `unsafe_property_access=2`), and native C++ `Tween` coordination.

---

## 1. System Architecture & Node Hierarchy

The root node is a `Node3D` with attached script `res://scenes/vfx/explosion_crysis.gd`. The scene consists of 5 synchronized child nodes:

```
ExplosionCrysis (Node3D, script: res://scenes/vfx/explosion_crysis.gd)
├── CoreFireball (GPUParticles3D)
├── LingeringSmoke (GPUParticles3D)
├── SparksAndDebris (GPUParticles3D)
├── DetonationFlash (OmniLight3D)
└── HeatDistortion (MeshInstance3D, shader: res://vfx/explosion_shockwave.gdshader)
```

### Layer Assignments
- Render Layer 1: Environment (`CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX` = 1) for all standard particle passes.
- Render Layer 10: Volumetrics (`1 << 9`) for `HeatDistortion` refractive screen distortion.

---

## 2. Child Nodes & Exact Property Specifications

### 2.1 CoreFireball (`GPUParticles3D`)
Handles the central high-density explosion burst using the 8x8 flipbook spritesheet generated from the Mantaflow simulation bake.

- **Emitter Properties**:
  - `name`: `"CoreFireball"`
  - `amount`: `1`
  - `lifetime`: `1.1` s
  - `one_shot`: `true`
  - `explosiveness`: `1.0`
  - `fixed_fps`: `60`
  - `layers`: `1` (Render Layer 1)
- **Draw Pass 1 (`QuadMesh`)**:
  - `size`: `Vector2(5.0, 5.0)`
- **Material (`StandardMaterial3D`)**:
  - `transparency`: `1` (`BaseMaterial3D.TRANSPARENCY_ALPHA`)
  - `shading_mode`: `0` (`BaseMaterial3D.SHADING_MODE_UNSHADED`)
  - `vertex_color_use_as_albedo`: `true`
  - `albedo_texture`: `ExtResource("res://assets/vfx/explosion/explosion_core_8x8.png")`
  - `billboard_mode`: `3` (`BaseMaterial3D.BILLBOARD_PARTICLES`)
  - `billboard_keep_scale`: `true`
  - `particles_anim_h_frames`: `8`
  - `particles_anim_v_frames`: `8`
  - `particles_anim_loop`: `false`
- **Process Material (`ParticleProcessMaterial`)**:
  - `gravity`: `Vector3(0.0, 0.0, 0.0)`
  - `anim_speed_min`: `1.0`
  - `anim_speed_max`: `1.0`
  - `scale_min`: `1.0`
  - `scale_max`: `1.0`
  - `scale_curve`: `CurveTexture` with `Curve` defining rapid scale-up from `1.0` to `3.2` during the first 15-20% of lifetime:
    - Point 0: `(0.0, 1.0)`, tangent out: `14.0`
    - Point 1: `(0.18, 3.2)`, tangent in: `0.0`, tangent out: `0.0`
    - Point 2: `(1.0, 3.2)`
  - `alpha_curve`: `CurveTexture` with `Curve` holding alpha at `1.0` for 80% of lifetime and decaying to `0.0` across the final 20%:
    - Point 0: `(0.0, 1.0)`
    - Point 1: `(0.8, 1.0)`, tangent in: `0.0`, tangent out: `-4.0`
    - Point 2: `(1.0, 0.0)`

#### Flipbook Animation Mechanics in Godot 4:
In Godot 4's `ParticleProcessMaterial`, when `particles_anim_h_frames` and `particles_anim_v_frames` are configured on `StandardMaterial3D`:
1. `anim_speed_min = 1.0` and `anim_speed_max = 1.0` maps particle normalized lifetime `[0.0, 1.0]` across exactly one full loop of the 64 frames (indices 0 to 63).
2. `billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES` (value 3) ensures each quad turns towards the camera plane while GPU shaders calculate UV atlas frame sub-rectangles from vertex attributes.
3. Setting `particles_anim_loop = false` clamps the animation at the final frame at `t = 1.0` without wrapping back to frame 0.

---

### 2.2 LingeringSmoke (`GPUParticles3D`)
Simulates heavy, turbulent smoke plumes rising slowly after the primary core fireball dissipates.

- **Emitter Properties**:
  - `name`: `"LingeringSmoke"`
  - `amount`: `12`
  - `lifetime`: `3.5` s
  - `one_shot`: `true`
  - `explosiveness`: `0.85`
  - `fixed_fps`: `60`
  - `layers`: `1`
- **Draw Pass 1 (`QuadMesh`)**:
  - `size`: `Vector2(4.2, 4.2)`
- **Material (`StandardMaterial3D`)**:
  - `transparency`: `1` (`BaseMaterial3D.TRANSPARENCY_ALPHA`)
  - `shading_mode`: `0` (`BaseMaterial3D.SHADING_MODE_UNSHADED` or soft vertex lit)
  - `vertex_color_use_as_albedo`: `true`
  - `billboard_mode`: `3` (`BaseMaterial3D.BILLBOARD_PARTICLES`)
  - `billboard_keep_scale`: `true`
  - `proximity_fade_enabled`: `true` (Enables soft particle blending against floor and obstacles)
  - `proximity_fade_distance`: `0.6` m
- **Process Material (`ParticleProcessMaterial`)**:
  - `emission_shape`: `1` (`EMISSION_SHAPE_SPHERE`)
  - `emission_sphere_radius`: `0.6` m
  - `direction`: `Vector3(0.0, 1.0, 0.0)`
  - `spread`: `180.0`
  - `radial_velocity_min`: `3.0` m/s
  - `radial_velocity_max`: `3.0` m/s
  - `damping_min`: `4.0` (linear damp = 4.0 rapidly decelerates initial expansion)
  - `damping_max`: `4.0`
  - `gravity`: `Vector3(0.0, 0.8, 0.0)` (buoyant upward drift)
  - `scale_min`: `1.2`
  - `scale_max`: `2.8`
  - `scale_curve`: `Curve` expanding smoke puffs from `1.0` to `2.4` over 3.5s
  - `color_ramp` / `alpha_curve`: Smooth alpha fade-out over duration:
    - Offset `0.0`: `Color(0.35, 0.35, 0.37, 0.0)`
    - Offset `0.1`: `Color(0.35, 0.35, 0.37, 0.75)`
    - Offset `0.7`: `Color(0.28, 0.28, 0.30, 0.55)`
    - Offset `1.0`: `Color(0.20, 0.20, 0.22, 0.0)`

---

### 2.3 SparksAndDebris (`GPUParticles3D`)
Fast ballistic fragments and sparks with strong downward gravity and floor bounce.

- **Emitter Properties**:
  - `name`: `"SparksAndDebris"`
  - `amount`: `60`
  - `lifetime`: `1.8` s
  - `one_shot`: `true`
  - `explosiveness`: `0.98`
  - `fixed_fps`: `60`
  - `transform_align`: `GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY` (aligns QuadMesh along velocity vector)
- **Draw Pass 1 (`QuadMesh`)**:
  - `size`: `Vector2(0.08, 0.4)` (elongated needle streak)
- **Material (`StandardMaterial3D`)**:
  - `shading_mode`: `0` (`BaseMaterial3D.SHADING_MODE_UNSHADED`)
  - `vertex_color_use_as_albedo`: `true`
  - `albedo_color`: `Color(5.0, 2.2, 0.4, 1.0)` (HDR values produce glow in Godot WorldEnvironment bloom)
- **Process Material (`ParticleProcessMaterial`)**:
  - `particle_flag_align_y`: `true`
  - `direction`: `Vector3(0.0, 0.5, 0.866).normalized()` (+Z bias directional spread)
  - `spread`: `65.0`
  - `initial_velocity_min`: `20.0` m/s
  - `initial_velocity_max`: `24.0` m/s (centered on 22.0 m/s)
  - `gravity`: `Vector3(0.0, -18.0, 0.0)` (strong ballistic gravity)
  - `damping_min`: `1.2`
  - `damping_max`: `2.0`
  - `collision_mode`: `1` (`ParticleProcessMaterial.COLLISION_RIGID`)
  - `collision_bounce`: `0.45` (ground bounce)
  - `collision_friction`: `0.25`
  - `scale_curve`: `Curve` tapering from `1.0` down to `0.0` over 1.8s

---

### 2.4 DetonationFlash (`OmniLight3D`)
High-intensity transient point light illuminating nearby geometry.

- **Properties**:
  - `name`: `"DetonationFlash"`
  - `light_color`: `Color(1.0, 0.6, 0.2)` (warm orange)
  - `light_energy`: `16.0` (peak energy at blast trigger)
  - `omni_range`: `25.0` m
  - `omni_attenuation`: `1.5`
  - `shadow_enabled`: `true`
  - `visible`: `false` (until `detonate()` is invoked)
- **Tween Collapse Behavior**:
  - Collapses `light_energy` from `16.0` to `0.0` over `0.15` s using `Tween.TRANS_EXPO`, `Tween.EASE_OUT`.
  - Hides node (`visible = false`) at `0.15` s to release GPU omni light evaluation.

---

### 2.5 HeatDistortion (`MeshInstance3D`)
Spherical mesh with `res://vfx/explosion_shockwave.gdshader` generating refractive normal-based screen distortion.

- **Properties**:
  - `name`: `"HeatDistortion"`
  - `layers`: `1024` (Render Layer 10: Volumetrics and distortion)
  - `cast_shadow`: `0` (`GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`)
  - `visible`: `false` (until `detonate()` is invoked)
  - `mesh`: `SphereMesh`
    - `radius`: `1.0`
    - `height`: `2.0`
    - `radial_segments`: `32`
    - `rings`: `16`
    - `material`: `ShaderMaterial`
      - `shader`: `ExtResource("res://vfx/explosion_shockwave.gdshader")`
- **Controller Tween Behavior**:
  - Shockwave duration: `0.4` s.
  - Initial scale: `Vector3(0.2, 0.2, 0.2)`.
  - Target scale: `Vector3(12.0, 12.0, 12.0)`.
  - At trigger: sets `visible = true`, scale to `Vector3(0.2, 0.2, 0.2)`.
  - Tween 1: `scale` from `0.2` to `12.0` over `0.4` s (`Tween.TRANS_CUBIC`, `Tween.EASE_OUT`).
  - Tween 2: `set_instance_shader_parameter(&"explosion_progress", t)` from `0.0` to `1.0` over `0.4` s (`Tween.TRANS_QUAD`, `Tween.EASE_OUT`).
  - Callback at `0.4` s: sets `visible = false`.

---

## 3. Controller Script Architecture: `res://scenes/vfx/explosion_crysis.gd`

### Strict Standards Compliance:
1. `class_name ExplosionCrysis extends Node3D`
2. Explicit static typing on every declaration and return type.
3. No per-frame polling: `set_process(false)` and `set_physics_process(false)` in `_ready()`.
4. Pre-allocated `StringName` constants (`PARAM_PROGRESS`, `PARAM_DISTORTION`).
5. Safe tween management using `Utilities.reset_tween()` and `Utilities.safe_kill_tween()`.
6. Descriptive `##` docstrings <= 100 characters per line.

### Draft Implementation Reference:
```gdscript
## Synchronized multi-emitter explosion controller implementing R4 Crysis specifications.
## Coordinates CoreFireball flipbook, LingeringSmoke plumes, ballistic sparks,
## omni light flash collapse, and screen-space heat distortion shockwave.
class_name ExplosionCrysis
extends Node3D

## Emitted when the detonation sequence starts.
@warning_ignore("unused_signal")
signal detonation_started(origin: Vector3)

## Emitted when all particle emitters and transient passes finish emission.
@warning_ignore("unused_signal")
signal detonation_finished(explosion_node: ExplosionCrysis)

## Pre-allocated instance uniform for shockwave progress.
const PARAM_PROGRESS: StringName = &"explosion_progress"
## Pre-allocated instance uniform for shockwave refraction distortion strength.
const PARAM_DISTORTION: StringName = &"distortion_strength"

## Peak detonation flash light energy.
const FLASH_PEAK_ENERGY: float = 16.0
## Duration (seconds) of the omni light flash decay.
const FLASH_DURATION: float = 0.15
## Duration (seconds) of the screen-space refractive shockwave.
const SHOCKWAVE_DURATION: float = 0.4
## Maximum particle lifetime across emitters (LingeringSmoke = 3.5s).
const MAX_PARTICLE_LIFETIME: float = 3.5
## Safety buffer before triggering node cleanup.
const CLEANUP_BUFFER: float = 0.3

## Automatically triggers detonation upon entering the scene tree.
@export var auto_play: bool = true
## Automatically frees the node from the tree once all emitters complete.
@export var free_on_finish: bool = true

## Active [Tween] managing flash decay and shockwave expansion.
var _active_tween: Tween = null
## Flag indicating whether a detonation sequence is actively running.
var _is_detonating: bool = false

## Primary 8x8 flipbook core fireball emitter.
@onready var core_fireball: GPUParticles3D = $CoreFireball
## Slow rising lingering smoke puff emitter.
@onready var lingering_smoke: GPUParticles3D = $LingeringSmoke
## Ballistic high-speed bouncing sparks emitter.
@onready var sparks_and_debris: GPUParticles3D = $SparksAndDebris
## Transient warm orange detonation omni light.
@onready var detonation_flash: OmniLight3D = $DetonationFlash
## Refractive screen distortion shockwave sphere mesh.
@onready var heat_distortion: MeshInstance3D = $HeatDistortion


## Validates child node invariants, disables per-frame polling, and triggers auto-play.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(core_fireball), "ExplosionCrysis: missing CoreFireball.")
	assert(is_instance_valid(lingering_smoke), "ExplosionCrysis: missing LingeringSmoke.")
	assert(is_instance_valid(sparks_and_debris), "ExplosionCrysis: missing SparksAndDebris.")
	assert(is_instance_valid(detonation_flash), "ExplosionCrysis: missing DetonationFlash.")
	assert(is_instance_valid(heat_distortion), "ExplosionCrysis: missing HeatDistortion.")

	detonation_flash.visible = false
	detonation_flash.light_energy = 0.0
	heat_distortion.visible = false

	if auto_play:
		detonate()


## Ensures active tweens are cleanly killed when removed from the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_active_tween)


## Triggers synchronized emission across all particle passes and begins tween sequences.
func detonate() -> void:
	if not is_inside_tree():
		return

	_is_detonating = true
	detonation_started.emit(global_position)
	print("ExplosionCrysis: detonated at ", global_position)

	# Restart and fire particle emitters.
	core_fireball.restart()
	core_fireball.emitting = true
	lingering_smoke.restart()
	lingering_smoke.emitting = true
	sparks_and_debris.restart()
	sparks_and_debris.emitting = true

	# Initialize transient flash and shockwave nodes.
	detonation_flash.visible = true
	detonation_flash.light_energy = FLASH_PEAK_ENERGY

	heat_distortion.visible = true
	heat_distortion.scale = Vector3(0.2, 0.2, 0.2)
	heat_distortion.set_instance_shader_parameter(PARAM_PROGRESS, 0.0)
	heat_distortion.set_instance_shader_parameter(PARAM_DISTORTION, 0.06)

	_start_detonation_tween()
	_schedule_lifecycle_cleanup()


## Drives light collapse and shockwave scaling using a synchronized C++ [Tween].
func _start_detonation_tween() -> void:
	_active_tween = Utilities.reset_tween(self, _active_tween)
	if not is_instance_valid(_active_tween):
		return

	_active_tween.set_parallel(true)

	(
		_active_tween
		. tween_property(detonation_flash, "light_energy", 0.0, FLASH_DURATION)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_OUT)
	)

	(
		_active_tween
		. tween_property(heat_distortion, "scale", Vector3(12.0, 12.0, 12.0), SHOCKWAVE_DURATION)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	(
		_active_tween
		. tween_method(_update_shockwave_progress, 0.0, 1.0, SHOCKWAVE_DURATION)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	_active_tween.chain().tween_callback(_on_flash_and_shockwave_complete)


## Updates per-instance shockwave progress parameter on [member heat_distortion].
func _update_shockwave_progress(progress: float) -> void:
	if is_instance_valid(heat_distortion):
		heat_distortion.set_instance_shader_parameter(PARAM_PROGRESS, progress)


## Hides transient light and shockwave meshes upon tween completion.
func _on_flash_and_shockwave_complete() -> void:
	if is_instance_valid(detonation_flash):
		detonation_flash.visible = false
	if is_instance_valid(heat_distortion):
		heat_distortion.visible = false


## Schedules deferred lifecycle cleanup once the longest particle pass completes.
func _schedule_lifecycle_cleanup() -> void:
	var total_lifetime: float = MAX_PARTICLE_LIFETIME + CLEANUP_BUFFER
	get_tree().create_timer(total_lifetime, false).timeout.connect(
		_on_detonation_lifecycle_finished, CONNECT_ONE_SHOT
	)


## Emits [signal detonation_finished] and queues node destruction if enabled.
func _on_detonation_lifecycle_finished() -> void:
	_is_detonating = false
	detonation_finished.emit(self)
	if free_on_finish and is_inside_tree():
		call_deferred(&"queue_free")
```

---

## 4. GUT Test Suite Specification: `test/unit/test_explosion_crysis.gd`

The GUT test suite verifies that the scene loads headlessly, all required child nodes exist with exact types, default properties match R4 constraints, and execution triggers behave correctly.

### Headless Execution Command:
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/unit/test_explosion_crysis.gd -gexit
```
- `-gconfig=` prevents GUT from executing every test in `res://test/unit/`.
- `-gexit` ensures Godot automatically terminates after the test suite completes.

### Test Structure & Assertions:
1. `test_scene_instantiation()`:
   - Verifies `PackedScene` loads from `"res://scenes/vfx/explosion_crysis.tscn"`.
   - Asserts instance is type `ExplosionCrysis`.
   - Verifies default flags (`auto_play == true`, `free_on_finish == true`).
2. `test_child_nodes_presence_and_types()`:
   - Asserts `CoreFireball` exists and is `GPUParticles3D`.
   - Asserts `LingeringSmoke` exists and is `GPUParticles3D`.
   - Asserts `SparksAndDebris` exists and is `GPUParticles3D`.
   - Asserts `DetonationFlash` exists and is `OmniLight3D`.
   - Asserts `HeatDistortion` exists and is `MeshInstance3D`.
3. `test_core_fireball_properties()`:
   - `amount == 1`
   - `is_equal_approx(lifetime, 1.1)`
   - `one_shot == true`
   - `is_equal_approx(explosiveness, 1.0)`
   - `draw_pass_1` is `QuadMesh` with `size == Vector2(5.0, 5.0)`.
   - Material is `StandardMaterial3D` with:
     - `shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED`
     - `billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES`
     - `particles_anim_h_frames == 8`
     - `particles_anim_v_frames == 8`
     - `particles_anim_loop == false`
   - ProcessMaterial has `anim_speed_min == 1.0` and `anim_speed_max == 1.0`.
4. `test_lingering_smoke_properties()`:
   - `amount == 12`
   - `is_equal_approx(lifetime, 3.5)`
   - `one_shot == true`
   - `is_equal_approx(explosiveness, 0.85)`
   - ProcessMaterial `gravity == Vector3(0.0, 0.8, 0.0)`.
   - ProcessMaterial damping is `4.0` (`damping_min` or `damping_max`).
5. `test_sparks_and_debris_properties()`:
   - `amount == 60`
   - `is_equal_approx(lifetime, 1.8)`
   - `one_shot == true`
   - `is_equal_approx(explosiveness, 0.98)`
   - `draw_pass_1` is `QuadMesh` with `size == Vector2(0.08, 0.4)`.
   - Material albedo color is `Color(5.0, 2.2, 0.4, 1.0)`.
   - ProcessMaterial `gravity == Vector3(0.0, -18.0, 0.0)`.
   - ProcessMaterial `collision_mode == ParticleProcessMaterial.COLLISION_RIGID`.
6. `test_detonation_flash_properties()`:
   - `light_color == Color(1.0, 0.6, 0.2)`.
   - `is_equal_approx(omni_range, 25.0)`.
   - Controller constant `FLASH_PEAK_ENERGY == 16.0`.
7. `test_heat_distortion_properties()`:
   - `mesh` is `SphereMesh`.
   - Material is `ShaderMaterial` with shader `res://vfx/explosion_shockwave.gdshader`.
8. `test_detonate_execution()`:
   - Configures `auto_play = false` and `free_on_finish = false`.
   - Adds instance to tree via `add_child_autofree(instance)`.
   - Calls `instance.detonate()`.
   - Asserts `core_fireball.emitting == true`.
   - Asserts `lingering_smoke.emitting == true`.
   - Asserts `sparks_and_debris.emitting == true`.
   - Asserts `detonation_flash.visible == true`.
   - Asserts `heat_distortion.visible == true`.

---

## 5. Pipeline Dependency & Risk Analysis

1. **Asset Prerequisite**:
   - `res://scenes/vfx/explosion_crysis.tscn` directly references `res://assets/vfx/explosion/explosion_core_8x8.png`.
   - The spritesheet assembly step (R3) must finish and `godot --headless --editor --quit` must run to generate `explosion_core_8x8.png.import` and `.uid` BEFORE the scene file is opened or tested in Godot.
2. **GUT CLI Scoping**:
   - Running GUT without `-gconfig=` triggers `.gutconfig.json`, which runs all tests in `res://test/unit/` (including failing or unmaintained tests).
   - The test command for this task MUST include `-gconfig= -gtest=res://test/unit/test_explosion_crysis.gd -gexit`.
3. **Strict Warning Policy**:
   - `unsafe_property_access=2` turns untyped property access into fatal parse errors. The unit test must explicitly type the instantiated scene as `ExplosionCrysis` (`var instance: ExplosionCrysis = packed_scene.instantiate() as ExplosionCrysis`).
