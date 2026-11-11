# Technical Survey Analysis: Godot VFX Architecture, Shaders & BellaSDK Standards

**Author**: Explorer Survey Agent 2
**Date**: 2026-11-11
**Working Directory**: `/home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/`
**Reference Task**: Headless Mantaflow Explosion, Flipbook Assembly & Composite Godot 4 Explosion Hierarchy (`res://scenes/vfx/explosion_crysis.tscn`)

---

## 1. Executive Summary

This survey provides comprehensive analysis of the existing Godot VFX infrastructure, shader mechanics, testing paradigms, and strict architectural standards governing BellaSDK.

Key findings:
1. **Refraction Shockwave**: `res://vfx/explosion_shockwave.gdshader` is a `spatial` unshaded shader utilizing `hint_screen_texture`, chromatic aberration, and radial fresnel falloff (`dot(NORMAL, VIEW)`). It **strictly requires a 3D curved mesh** (such as `SphereMesh`), because on flat Quad meshes the normal is planar, yielding zero Fresnel rim.
2. **GUT Testing & Strict Typing Alert**: Analysis of `res://test/unit/test_smoke_explosion_vfx.gd` revealed a runtime parse error in Godot 4.7 due to BellaSDK's zero-tolerance warning configuration (`UNSAFE_PROPERTY_ACCESS = 2`). The test accesses undeclared properties (`preview_active`, `loop`). This provides a critical design lesson: all properties tested on `ExplosionCrysis` in `test_explosion_crysis.gd` must be explicitly declared and statically typed on `res://scenes/vfx/explosion_crysis.gd`.
3. **VFX Flipbook Standard**: Existing flipbook VFX (`vfx_smoke_flipbook.tscn`, `smoke_puff_8x8.png`) establish standard Godot 4 flipbook mechanics: `QuadMesh` with `StandardMaterial3D` (`billboard_mode = 3` / `BILLBOARD_PARTICLES`, `particles_anim_h_frames = 8`, `particles_anim_v_frames = 8`, `particles_anim_loop = false`), driven by `ParticleProcessMaterial` with `anim_speed_min = 1.0` and `anim_speed_max = 1.0`.
4. **BellaSDK Compliance**: All new scripts must adhere to strict static typing (zero `Variant` leakage, no `:=` inference, explicit constructor conversions, no `@warning_ignore`), `.gdlintrc` formatting (tabs, <=100 chars, no leading underscore on function locals), BBCode docstrings (`## [Class]`), and 60 FPS zero-allocation event architecture (`Utilities.reset_tween()`, pre-allocated `&"param"` StringNames).

---

## 2. Inspection of `res://vfx/explosion_shockwave.gdshader`

### 2.1 Shader Declaration and Render Mode
```gdshader
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;
```
- **`shader_type spatial`**: Evaluated in 3D world space within the forward/clustered spatial rendering pipeline.
- **`render_mode blend_mix`**: Standard alpha blending.
- **`depth_draw_never`**: Does not write to depth buffer (critical for transparent refraction effects to prevent depth fighting and self-occlusion).
- **`cull_back`**: Culls back faces; only front hemisphere/shell facing camera renders.
- **`unshaded`**: Ignores scene light calculations; samples `screen_texture` directly.

### 2.2 Uniforms and Hints
| Uniform | Scope | Type | Default | Description |
|---|---|---|---|---|
| `screen_texture` | Global | `sampler2D` | `hint_screen_texture, repeat_disable, filter_linear_mipmap` | Godot 4 screen-reading sampler |
| `explosion_progress` | `instance` | `float` | `0.0` (range 0.0 to 1.0) | Normalized progress driving shockwave fade |
| `distortion_strength` | `instance` | `float` | `0.045` (range 0.0 to 0.15) | Max screen UV displacement amplitude |
| `aberration_amount` | Uniform | `float` | `0.008` (range 0.0 to 0.03) | Chromatic channel separation offset |

Notice the use of **`instance uniform`** on `explosion_progress` and `distortion_strength`. This enables multiple explosion instances to share a single cached `ShaderMaterial` while mutating parameters independently per instance via `set_instance_shader_parameter(StringName, Variant)` without Vulkan pipeline stall material duplications (`.duplicate()`), strictly following BellaSDK `MaterialCache` rules.

### 2.3 Refraction Algorithm and SCREEN_TEXTURE Sampling
In `fragment()`:
```gdshader
float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
float ring_mask = smoothstep(0.25, 0.78, fresnel) * smoothstep(1.0, 0.82, fresnel);
float fade = pow(1.0 - clamp(explosion_progress, 0.0, 1.0), 1.6);

float shimmer = wave_noise(UV * 18.0 + vec2(TIME * 4.0)) * 2.0 - 1.0;
vec2 offset = normalize(NORMAL.xy + vec2(0.0001)) * ring_mask * distortion_strength * fade;
offset += vec2(shimmer * 0.003 * fade);

float r = texture(screen_texture, SCREEN_UV + offset * (1.0 + aberration_amount)).r;
float g = texture(screen_texture, SCREEN_UV + offset).g;
float b = texture(screen_texture, SCREEN_UV + offset * (1.0 - aberration_amount)).b;

ALBEDO = vec3(r, g, b);
ALPHA = clamp(ring_mask * fade * 2.2, 0.0, 1.0);
```

Mechanisms:
1. **Fresnel Ring Mask**: Isolates a toroidal band along the grazing edge where `dot(NORMAL, VIEW)` is near 0.25 to 0.82.
2. **Directional Normal Displacement**: Projects 3D normal XY into screen UV space: `normalize(NORMAL.xy + vec2(0.0001))`.
3. **Chromatic Aberration**: Samples Red, Green, and Blue channels at scaled offsets: `offset * (1.0 + aberration_amount)` vs `offset * (1.0 - aberration_amount)`.
4. **Temporal Shimmer**: Procedural pseudo-random hash (`wave_noise`) modulated by `TIME` adds micro-turbulent heat distortion.

### 2.4 Mesh Geometry Requirement
- **Why a flat QuadMesh fails**: On a billboard QuadMesh perpendicular to the camera, `NORMAL` is constant `(0, 0, 1)`. Therefore `dot(NORMAL, VIEW) ≈ 1.0` everywhere across the quad face. As a result, `fresnel = 1.0 - 1.0 = 0.0`, resulting in `ring_mask = 0.0`. A flat quad renders 100% transparent with ZERO refraction!
- **Required Geometry**: A **3D curved surface** (`SphereMesh`, radius = 1.0, height = 2.0, radial_segments = 32, rings = 16), as proven in `ControlExplosion` (`res://vfx/effects/control_explosion.gd`: lines 340-349) and `SmokeExplosionVfx` (`res://vfx/smoke_explosion.tscn`: lines 163-169).
- **Scale Control**: In `explosion_shockwave.gdshader`, unlike `shockwave_refract.gdshader`, vertex displacement is not coded in the shader. Expansion is driven by animating the `scale` property of the `MeshInstance3D` via a `Tween`, while feeding normalized progress to `explosion_progress`.
- **Render Layer**: Must be placed on Render Layer 10 (`CollisionLayers.RENDER_MASK_VOLUMETRICS` or `1 << 9`) or Layer 1 (`CollisionLayers.RENDER_MASK_ENVIRONMENT`), with `cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`.

---

## 3. Inspection of `res://test/unit/test_smoke_explosion_vfx.gd`

### 3.1 Test Construction & Anatomy
- **Inheritance**: `extends GutTest`
- **Class naming**: `class_name TestSmokeExplosionVfx`
- **Constants**: Static typed scene path string: `const SMOKE_SCENE_PATH: String = "res://vfx/smoke_explosion.tscn"`
- **Pattern**:
  1. Load scene: `var packed_scene: PackedScene = load(SMOKE_SCENE_PATH) as PackedScene`
  2. Verify resource load: `assert_not_null(packed_scene, "Smoke scene must load successfully.")`
  3. Instantiate node: `var instance: SmokeExplosionVfx = packed_scene.instantiate() as SmokeExplosionVfx`
  4. Verify class cast: `assert_not_null(instance, "Instance must be SmokeExplosionVfx type.")`
  5. Automatic tree management: `add_child_autofree(instance)` (GUT method guaranteeing node registration into the scene tree and automated cleanup upon test completion).
  6. Invariant assertions: `assert_true()`, `assert_false()`, `assert_eq()`.

### 3.2 GUT Invocation Pattern
In BellaSDK, headless GUT tests are executed via:
```bash
godot --headless -s addons/gut/gut_cmdln.gd -gselect=<test_script_name> -gexit
```
Verification on `res://test/unit/test_collision_layers.gd` passed with 3/3 tests in 0.406s, exit code 0.

### 3.3 Discovered Anomaly & Static Type Warning Trap
When running `test_smoke_explosion_vfx.gd` directly:
```
SCRIPT ERROR: Parse Error: The property "preview_active" is not present on the inferred type "SmokeExplosionVfx" (but may be present on a subtype). (Warning treated as error.)
at: GDScript::reload (res://test/unit/test_smoke_explosion_vfx.gd:35)
```
**Root Cause**: `test_smoke_explosion_vfx.gd` asserts on properties (`loop`, `loop_interval`, `preview_active`) that were copied from `ControlExplosion` but were never declared on `SmokeExplosionVfx`. Under Godot 4.7 with `warning/gdscript/untyped_declaration=2` and `warning/gdscript/unsafe_property_access=2`, accessing undeclared properties on a statically typed class is a fatal compiler Parse Error!

**Key Mandate for `test_explosion_crysis.gd`**:
1. Every property tested on `ExplosionCrysis` must exist on `res://scenes/vfx/explosion_crysis.gd` with explicit static typing.
2. In `test_explosion_crysis.gd`, test:
   - Successful loading of `res://scenes/vfx/explosion_crysis.tscn`.
   - Node hierarchy validation:
     - `CoreFireball` is `GPUParticles3D`
     - `LingeringSmoke` is `GPUParticles3D`
     - `SparksAndDebris` is `GPUParticles3D`
     - `DetonationFlash` is `OmniLight3D`
     - `HeatDistortion` is `MeshInstance3D`
   - Initial state validation:
     - All particles are `one_shot == true` and `emitting == false` (or auto-play triggers correctly).
     - `DetonationFlash` energy and range invariants.
     - `HeatDistortion` mesh is `SphereMesh` with `explosion_shockwave.gdshader`.
     - Controller script exports (e.g. `total_duration`, `flash_duration`).

---

## 4. Survey of Existing VFX Scenes & Particle Materials

### 4.1 Node Hierarchy Comparison
Examining `res://vfx/smoke_explosion.tscn` vs `res://vfx/effects/control_explosion.gd`:

| Node Name | Node Type | Purpose | Reference Scene |
|---|---|---|---|
| Root | `Node3D` | Controller script lifecycle & coordinates | `smoke_explosion.tscn` / `control_explosion.tscn` |
| `CoreFireball` | `GPUParticles3D` | High-energy flipbook fireball burst | `vfx_smoke_flipbook.tscn` |
| `LingeringSmoke` | `GPUParticles3D` | Low-velocity rising smoke volume | `smoke_explosion.tscn` (`SmokeBillowPlume`) |
| `SparksAndDebris` | `GPUParticles3D` | Ballistic sparks with bounce/collision | `smoke_explosion.tscn` (`FlyingDebrisSparks`) |
| `DetonationFlash` | `OmniLight3D` | High-intensity fast-decay light | `smoke_explosion.tscn` (`FlashLight`) |
| `HeatDistortion` | `MeshInstance3D` | Refractive sphere shell with shockwave shader | `smoke_explosion.tscn` (`ShockwaveSphere`) |
| `ScreenNotifier` | `VisibleOnScreenNotifier3D` | LOD & rendering gating when off-screen | `smoke_explosion.tscn` |

### 4.2 Flipbook Sprite Configuration (`res://vfx/vfx_smoke_flipbook.tscn`)
Inspection of `vfx_smoke_flipbook.tscn` reveals the exact Godot 4 flipbook setup:
```
[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_flipbook"]
transparency = 1
vertex_color_use_as_albedo = true
vertex_color_is_srgb = true
albedo_texture = ExtResource("explosion_core_8x8.png")
billboard_mode = 3
billboard_keep_scale = true
particles_anim_h_frames = 8
particles_anim_v_frames = 8
particles_anim_loop = false
proximity_fade_enabled = true
```
And in `ParticleProcessMaterial`:
```
anim_speed_min = 1.0
anim_speed_max = 1.0
```
- `billboard_mode = 3` is `BaseMaterial3D.BILLBOARD_PARTICLES`. This mode instructs Godot's particle vertex shader to extract the flipbook frame index from particle lifetime (`COLOR.a` or particle custom data) and calculate UV frame offsets based on `particles_anim_h_frames` and `particles_anim_v_frames`.
- `particles_anim_loop = false`: The 64 frames play exactly once over the particle's lifetime (1.1s).
- Draw pass: `QuadMesh` with `size = Vector2(5.0, 5.0)`.

### 4.3 Sparks and Debris Alignment
In Godot 4:
- Elongated particles (streaks) use `QuadMesh` with unequal dimensions, e.g. `size = Vector2(0.08, 0.4)`.
- In `ParticleProcessMaterial`: `particle_flag_align_y = true` (or in GDScript: `particle.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY`). This rotates the Quad's local Y axis along the particle's velocity vector.
- Material: `StandardMaterial3D` with `shading_mode = 0` (unshaded), `albedo_color = Color(5.0, 2.2, 0.4, 1.0)` (HDR emissive bloom), `vertex_color_use_as_albedo = true`.
- Physics collision: `collision_mode = ParticleProcessMaterial.COLLISION_RIGID` with `collision_bounce = 0.45` and `collision_friction = 0.25`.

---

## 5. BellaSDK Project Engineering Rules

### 5.1 Strict Typing Rules (Zero Tolerance)
From `GEMINI.md`:
- `untyped_declaration = 2` (Error): Static typing required on ALL declarations:
  - Variables: `var flash_energy: float = 16.0`
  - Constants: `const PARAM_PROGRESS: StringName = &"explosion_progress"`
  - Arrays: `Array[GPUParticles3D]`
  - Method parameters & return types: `func detonate(at_position: Vector3) -> void:`
  - Loop iterators: `for emitter: GPUParticles3D in _emitters:`
- `inferred_declaration = 1` (Warning): **Never use `:=`**. Always write explicit static types (`var x: float = 1.0`, not `var x := 1.0`).
- `unsafe_property_access = 2` & `unsafe_method_access = 2` (Error): No accessing properties or calling methods on untyped objects or `Variant`.
- `unsafe_cast = 1` & `unsafe_call_argument = 1`:
  - `as Type` is ONLY permitted when downcasting `Object` subclasses (`node as GPUParticles3D`).
  - NEVER cast `Variant` to primitives via `as` (`val as float` is invalid). Use type guards or constructors (`if val is float:`).
  - Ternary branches must have identical types.
  - Zero `@warning_ignore` comments (except `@warning_ignore("unused_signal")` above signal definitions).

### 5.2 Formatting & GDLint Rules (`.gdlintrc`)
- **Indentation**: Strict tabs (1 tab per level, NO spaces for indent).
- **Line length**: Maximum 100 characters per line (code, comments, docstrings).
- **No trailing whitespace**: Strip all trailing whitespace.
- **Local variable naming**: Must match `[a-z][a-z0-9]*(_[a-z0-9]+)*`. **NEVER begin a local variable with a leading underscore `_`** (underscores are strictly reserved for private class members and unused function parameters).
- **Class definition order**:
  1. `@tool` (if applicable)
  2. `class_name`
  3. `extends`
  4. `##` docstrings & signals
  5. `enums`
  6. `constants`
  7. `@export` variables
  8. public variables
  9. `_private` variables
  10. `@onready` variables
  11. lifecycle methods (`_ready`, `_process`, `_exit_tree`)
  12. public methods
  13. `_private` methods

### 5.3 Event Architecture & 60 FPS Performance
- **Disable per-frame processing**: In `_ready()`, invoke:
  ```gdscript
  set_process(false)
  set_physics_process(false)
  ```
- **Zero Allocations per Frame**: Pre-allocate `StringName` constants:
  ```gdscript
  const PARAM_PROGRESS: StringName = &"explosion_progress"
  const PARAM_DISTORTION: StringName = &"distortion_strength"
  ```
- **Tween Lifecycle Management**:
  - Always clean up tweens using `Utilities.reset_tween(self, _active_tween)` or check `Utilities.safe_kill_tween(_active_tween)`.
  - In `_exit_tree()`, kill active tweens.
- **Signal Connections**:
  - Use `Utilities.safe_connect(sig, callable)` or typed Callables.
- **Node Caching & Assertions**:
  - Cache node references using `@onready` typed variables.
  - In `_ready()`, validate node presence with single-line `assert()`:
    ```gdscript
    assert(_core_fireball != null, "ExplosionCrysis: missing CoreFireball node.")
    ```
- **Action Logging**:
  - Include concise print on discrete trigger:
    ```gdscript
    print("ExplosionCrysis: Detonating at ", global_position)
    ```
  - Never place print statements in process loops.

### 5.4 BBCode Docstring Standard
Every declaration (class, signal, enum, const, @export, var, func) must have a `##` BBCode docstring directly above it wrapped at <= 100 chars:
```gdscript
## Coordinates one-shot emission triggers, handles the [OmniLight3D] flash tween,
## and manages lifecycle cleanup after all particle emitters complete.
class_name ExplosionCrysis
extends Node3D
```

---

## 6. Implementation Blueprint for Composite Explosion

Based on the survey, the following precise structure is recommended for `res://scenes/vfx/explosion_crysis.tscn` and `res://scenes/vfx/explosion_crysis.gd`:

### Scene Node Tree
```
ExplosionCrysis (Node3D) [res://scenes/vfx/explosion_crysis.gd]
├── CoreFireball (GPUParticles3D)
├── LingeringSmoke (GPUParticles3D)
├── SparksAndDebris (GPUParticles3D)
├── DetonationFlash (OmniLight3D)
├── HeatDistortion (MeshInstance3D)
└── ScreenNotifier (VisibleOnScreenNotifier3D)
```

### Component Details
1. **CoreFireball**:
   - `amount = 1`, `lifetime = 1.1`, `one_shot = true`, `explosiveness = 1.0`, `fixed_fps = 60`.
   - `draw_pass_1 = QuadMesh` (5.0m x 5.0m).
   - `material_override`: `StandardMaterial3D` (unshaded, `billboard_mode = 3`, `particles_anim_h_frames = 8`, `particles_anim_v_frames = 8`, `particles_anim_loop = false`, albedo texture = `res://assets/vfx/explosion/explosion_core_8x8.png`).
   - `process_material`: `ParticleProcessMaterial` (`anim_speed_min = 1.0`, `anim_speed_max = 1.0`, scale curve rapid scale-up 1.0 -> 3.2, color ramp alpha fade-out during final 20%).
2. **LingeringSmoke**:
   - `amount = 12`, `lifetime = 3.5`, `one_shot = true`, `explosiveness = 0.85`, `fixed_fps = 60`.
   - `draw_pass_1 = QuadMesh` (3.0m x 3.0m).
   - `material_override`: `StandardMaterial3D` with soft particle blend (`proximity_fade_enabled = true`, distance = 0.5m), billboard mode = 3.
   - `process_material`: Initial radial velocity = 3.0 m/s, linear damp = 4.0, gravity = Vector3(0, 0.8, 0).
3. **SparksAndDebris**:
   - `amount = 60`, `lifetime = 1.8`, `one_shot = true`, `explosiveness = 0.98`, `fixed_fps = 60`.
   - `draw_pass_1 = QuadMesh` (0.08m x 0.4m).
   - `material_override`: `StandardMaterial3D` unshaded, `albedo_color = Color(5.0, 2.2, 0.4, 1.0)`, `vertex_color_use_as_albedo = true`.
   - `process_material`: `particle_flag_align_y = true`, spread with +Z bias, initial velocity = 22.0 m/s, gravity = Vector3(0, -18.0, 0), `collision_mode = COLLISION_RIGID`.
4. **DetonationFlash**:
   - `OmniLight3D`, `light_color = Color(1.0, 0.6, 0.2)`, initial `light_energy = 16.0`, `omni_range = 25.0`.
   - Collapses energy to 0.0 in 0.15s via Tween (`TRANS_EXPO`, `EASE_OUT`).
5. **HeatDistortion**:
   - `MeshInstance3D` with `SphereMesh` (radius 1.0, height 2.0).
   - `material_override`: `ShaderMaterial` with `res://vfx/explosion_shockwave.gdshader`.
   - `cast_shadow = SHADOW_CASTING_SETTING_OFF`.
   - Tween expands scale (0.2 -> 12.0m) over 0.4s while updating `explosion_progress` (0.0 -> 1.0).

---

## 7. Verification Checklist for Downstream Implementers

- [ ] `explosion_shockwave.gdshader` is bound to a `SphereMesh`, not a QuadMesh.
- [ ] `explosion_crysis.gd` has NO `:=` inferred declarations, NO untyped declarations, and NO leading underscores on function local variables.
- [ ] All docstrings are `##` BBCode formatted and wrapped at <= 100 characters.
- [ ] `Utilities.reset_tween()` is used for tween management.
- [ ] `test_explosion_crysis.gd` verifies scene instantiation and property invariants, and runs clean with `godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_explosion_crysis -gexit`.
