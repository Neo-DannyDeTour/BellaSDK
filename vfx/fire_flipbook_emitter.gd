@tool
class_name FireFlipbookEmitter
extends Node3D
## Drives a layered combat fire pit with inner/outer tongues, sparks, smoke, and heat distortion.
##
## Runs in the editor via [code]@tool[/code] and gates runtime [OmniLight3D] flicker via
## [VisibleOnScreenNotifier3D]. Assigns Render Layer 10 to all volumetric emitters.

## Fire visual archetypes controlling HDR intensity, smoke soot, scale, and light profile.
enum FirePreset { CAMPFIRE, BONFIRE, OIL_FIRE, TORCH }

## Minimum allowed [member fire_scale] multiplier.
const MIN_FIRE_SCALE: float = 0.25
## Maximum allowed [member fire_scale] multiplier.
const MAX_FIRE_SCALE: float = 3.0
## Base elevation in meters for rising smoke and heat distortion above the flame core.
const UPPER_LAYER_OFFSET_Y: float = 0.95
## Base elevation in meters for [member _light] above the hearth center.
const LIGHT_BASE_OFFSET_Y: float = 0.5
## Base scale factor applied to [member _smoke] before [member fire_scale].
const SMOKE_BASE_SCALE: float = 0.8

## Shader instance parameter key for HDR emission multiplier.
const PARAM_HDR_INTENSITY: StringName = &"hdr_intensity"
## Shader instance parameter key for flame turbulence scroll speed.
const PARAM_FLICKER_SPEED: StringName = &"flicker_speed"
## Shader instance parameter key for flame color tint shift.
const PARAM_TINT_SHIFT: StringName = &"tint_shift"
## Smoke shader instance parameter key for soot albedo tint.
const PARAM_SMOKE_TINT: StringName = &"tint_color"
## Smoke shader instance parameter key for opacity density multiplier.
const PARAM_DENSITY_SCALE: StringName = &"density_scale"

## Preset parameter lookup table keyed by [enum FirePreset].
const PRESET_CONFIGS: Dictionary = {
	FirePreset.CAMPFIRE:
	{
		"scale_mult": 1.0,
		"hdr_inner": 2.4,
		"hdr_outer": 1.3,
		"flicker_speed": 2.4,
		"inner_tint": Vector3(1.0, 1.0, 1.0),
		"outer_tint": Vector3(1.0, 0.65, 0.42),
		"smoke_tint": Color(0.24, 0.21, 0.19, 1.0),
		"smoke_density": 0.65,
		"light_color": Color(1.0, 0.572549, 0.2, 1.0),
		"base_energy": 2.2,
		"omni_range": 7.5,
		"ember_ratio": 0.75,
	},
	FirePreset.BONFIRE:
	{
		"scale_mult": 1.45,
		"hdr_inner": 3.2,
		"hdr_outer": 1.8,
		"flicker_speed": 3.2,
		"inner_tint": Vector3(1.0, 0.96, 0.88),
		"outer_tint": Vector3(1.0, 0.55, 0.30),
		"smoke_tint": Color(0.18, 0.16, 0.15, 1.0),
		"smoke_density": 0.95,
		"light_color": Color(1.0, 0.55, 0.16, 1.0),
		"base_energy": 3.6,
		"omni_range": 10.5,
		"ember_ratio": 1.0,
	},
	FirePreset.OIL_FIRE:
	{
		"scale_mult": 1.25,
		"hdr_inner": 2.8,
		"hdr_outer": 1.6,
		"flicker_speed": 3.6,
		"inner_tint": Vector3(1.0, 0.88, 0.72),
		"outer_tint": Vector3(0.95, 0.40, 0.18),
		"smoke_tint": Color(0.08, 0.07, 0.07, 1.0),
		"smoke_density": 1.35,
		"light_color": Color(1.0, 0.45, 0.12, 1.0),
		"base_energy": 2.8,
		"omni_range": 8.5,
		"ember_ratio": 0.55,
	},
	FirePreset.TORCH:
	{
		"scale_mult": 0.55,
		"hdr_inner": 2.1,
		"hdr_outer": 1.1,
		"flicker_speed": 2.9,
		"inner_tint": Vector3(1.0, 1.0, 0.92),
		"outer_tint": Vector3(1.0, 0.68, 0.38),
		"smoke_tint": Color(0.32, 0.29, 0.26, 1.0),
		"smoke_density": 0.35,
		"light_color": Color(1.0, 0.64, 0.28, 1.0),
		"base_energy": 1.8,
		"omni_range": 5.5,
		"ember_ratio": 0.45,
	},
}

## Enables or disables fire, embers, smoke, heat distortion, and light emission.
@export var is_active: bool = true:
	set(value):
		is_active = value
		print("FireFlipbookEmitter: is_active -> ", is_active)
		if is_inside_tree():
			_apply_active_state()
## Visual preset controlling flame HDR, smoke soot tint, and light behavior.
@export var fire_preset: FirePreset = FirePreset.CAMPFIRE:
	set(value):
		fire_preset = value
		print("FireFlipbookEmitter: fire_preset -> ", fire_preset)
		if is_inside_tree():
			_apply_preset(true)
## Uniform scale multiplier applied across all fire, ember, smoke, and heat layers.
@export_range(0.25, 3.0, 0.05) var fire_scale: float = 1.0:
	set(value):
		fire_scale = clampf(value, MIN_FIRE_SCALE, MAX_FIRE_SCALE)
		if is_inside_tree():
			_apply_scale()
## Base light energy when idle.
@export var base_energy: float = 2.2
## Maximum random energy offset applied per flicker step.
@export var flicker_amplitude: float = 0.45
## Average duration in seconds between flicker targets.
@export var flicker_interval: float = 0.08
## Base color of the [OmniLight3D].
@export var light_color: Color = Color(1.0, 0.572549, 0.2, 1.0)

var _flicker_tween: Tween = null
var _is_visible_on_screen: bool = true
var _heat_base_basis: Basis = Basis.IDENTITY

@onready var _light: OmniLight3D = $FireLight
@onready var _particles: GPUParticles3D = $FlameParticles
@onready var _outer_particles: GPUParticles3D = $FlameOuterParticles
@onready var _embers: GPUParticles3D = $EmberParticles
@onready var _smoke: GPUParticles3D = $SmokeParticles
@onready var _heat_distortion: GasLeakEmitter = $HeatDistortion
@onready var _visibility_notifier: VisibleOnScreenNotifier3D = $VisibilityNotifier


## Initializes emitters, render layers, preset parameters, and visibility gating.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_light), "FireFlipbookEmitter requires FireLight child.")
	assert(is_instance_valid(_particles), "FireFlipbookEmitter requires FlameParticles child.")
	assert(
		is_instance_valid(_outer_particles),
		"FireFlipbookEmitter requires FlameOuterParticles child."
	)
	assert(is_instance_valid(_embers), "FireFlipbookEmitter requires EmberParticles child.")
	assert(is_instance_valid(_smoke), "FireFlipbookEmitter requires SmokeParticles child.")
	assert(
		is_instance_valid(_heat_distortion), "FireFlipbookEmitter requires HeatDistortion child."
	)
	assert(
		is_instance_valid(_visibility_notifier),
		"FireFlipbookEmitter requires VisibilityNotifier child."
	)
	assert(base_energy >= 0.0, "base_energy must be non-negative.")
	assert(
		fire_scale >= MIN_FIRE_SCALE and fire_scale <= MAX_FIRE_SCALE,
		"fire_scale must remain within [0.25, 3.0]."
	)

	_heat_base_basis = _heat_distortion.transform.basis.orthonormalized()

	_particles.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_outer_particles.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_embers.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_smoke.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_heat_distortion.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS

	if not Engine.is_editor_hint():
		Utilities.safe_connect(_visibility_notifier.screen_entered, _on_screen_entered)
		Utilities.safe_connect(_visibility_notifier.screen_exited, _on_screen_exited)
		_is_visible_on_screen = _visibility_notifier.is_on_screen()
	else:
		_is_visible_on_screen = true

	_apply_preset(fire_preset != FirePreset.CAMPFIRE)
	_apply_active_state()


## Cleans up active flicker tween and visibility connections when exiting the tree.
func _exit_tree() -> void:
	if is_instance_valid(_flicker_tween):
		_flicker_tween.kill()
	if is_instance_valid(_visibility_notifier):
		if _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			_visibility_notifier.screen_entered.disconnect(_on_screen_entered)
		if _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			_visibility_notifier.screen_exited.disconnect(_on_screen_exited)


## Applies [member fire_preset] visual, shader, smoke, and light configuration.
func _apply_preset(override_light: bool = true) -> void:
	if not is_inside_tree():
		return
	var cfg: Dictionary = _get_preset_config()
	var hdr_inner: float = _read_float(cfg, "hdr_inner", 2.4)
	var hdr_outer: float = _read_float(cfg, "hdr_outer", 1.3)
	var speed: float = _read_float(cfg, "flicker_speed", 2.4)
	var inner_tint: Vector3 = _read_vec3(cfg, "inner_tint", Vector3.ONE)
	var outer_tint: Vector3 = _read_vec3(cfg, "outer_tint", Vector3(1.0, 0.58, 0.35))
	var smoke_tint: Color = _read_color(cfg, "smoke_tint", Color(0.24, 0.21, 0.19, 1.0))
	var smoke_density: float = _read_float(cfg, "smoke_density", 0.75)
	var ember_ratio: float = _read_float(cfg, "ember_ratio", 0.75)
	var preset_light_color: Color = _read_color(cfg, "light_color", Color(1.0, 0.572549, 0.2, 1.0))
	var preset_energy: float = _read_float(cfg, "base_energy", 2.2)

	if is_instance_valid(_particles):
		_particles.set_instance_shader_parameter(PARAM_HDR_INTENSITY, hdr_inner)
		_particles.set_instance_shader_parameter(PARAM_FLICKER_SPEED, speed)
		_particles.set_instance_shader_parameter(PARAM_TINT_SHIFT, inner_tint)
	if is_instance_valid(_outer_particles):
		_outer_particles.set_instance_shader_parameter(PARAM_HDR_INTENSITY, hdr_outer)
		_outer_particles.set_instance_shader_parameter(PARAM_FLICKER_SPEED, speed * 0.88)
		_outer_particles.set_instance_shader_parameter(PARAM_TINT_SHIFT, outer_tint)
	if is_instance_valid(_smoke):
		_smoke.set_instance_shader_parameter(PARAM_SMOKE_TINT, smoke_tint)
		_smoke.set_instance_shader_parameter(PARAM_DENSITY_SCALE, smoke_density)
	if is_instance_valid(_embers):
		_embers.amount_ratio = ember_ratio

	if override_light:
		light_color = preset_light_color
		base_energy = preset_energy
	if is_instance_valid(_light):
		_light.light_color = light_color
		_light.light_energy = base_energy

	_apply_scale()


## Applies combined [member fire_scale] and preset scale across child emitters and light range.
func _apply_scale() -> void:
	if not is_inside_tree():
		return
	var cfg: Dictionary = _get_preset_config()
	var preset_scale: float = _read_float(cfg, "scale_mult", 1.0)
	var combined: float = fire_scale * preset_scale
	var base_omni_range: float = _read_float(cfg, "omni_range", 7.5)

	if is_instance_valid(_particles):
		_particles.scale = Vector3.ONE * combined
	if is_instance_valid(_outer_particles):
		_outer_particles.scale = Vector3.ONE * combined
	if is_instance_valid(_embers):
		_embers.scale = Vector3.ONE * combined
	if is_instance_valid(_smoke):
		_smoke.scale = Vector3.ONE * (SMOKE_BASE_SCALE * combined)
		_smoke.position = Vector3(0.0, UPPER_LAYER_OFFSET_Y * combined, 0.0)
	if is_instance_valid(_heat_distortion):
		_heat_distortion.transform = Transform3D(
			_heat_base_basis.scaled(Vector3.ONE * combined),
			Vector3(0.0, UPPER_LAYER_OFFSET_Y * combined, 0.0)
		)
	if is_instance_valid(_light):
		_light.position = Vector3(0.0, LIGHT_BASE_OFFSET_Y * combined, 0.0)
		_light.omni_range = base_omni_range * sqrt(combined)


## Applies [member is_active] to all child emitters and light flicker.
func _apply_active_state() -> void:
	if not is_inside_tree():
		return
	if is_instance_valid(_particles):
		_particles.emitting = is_active
	if is_instance_valid(_outer_particles):
		_outer_particles.emitting = is_active
	if is_instance_valid(_embers):
		_embers.emitting = is_active
	if is_instance_valid(_smoke):
		_smoke.emitting = is_active
	if is_instance_valid(_heat_distortion):
		_heat_distortion.is_leaking = is_active
	if is_instance_valid(_light):
		_light.visible = is_active
	if is_active and _is_visible_on_screen:
		_schedule_next_flicker()
	elif is_instance_valid(_flicker_tween):
		_flicker_tween.kill()


## Resumes light flicker when the emitter enters the camera frustum.
func _on_screen_entered() -> void:
	_is_visible_on_screen = true
	if is_active:
		_schedule_next_flicker()


## Pauses light flicker when the emitter exits the camera frustum.
func _on_screen_exited() -> void:
	_is_visible_on_screen = false
	if is_instance_valid(_flicker_tween):
		_flicker_tween.kill()


## Schedules the next randomized [Tween] step for [member _light] energy.
func _schedule_next_flicker() -> void:
	if (
		not is_active
		or not _is_visible_on_screen
		or not is_inside_tree()
		or not is_instance_valid(_light)
	):
		return
	if is_instance_valid(_flicker_tween):
		_flicker_tween.kill()

	var target_energy: float = maxf(
		0.1, base_energy + randf_range(-flicker_amplitude, flicker_amplitude)
	)
	var step_duration: float = flicker_interval * randf_range(0.7, 1.3)

	_flicker_tween = create_tween()
	_flicker_tween.set_trans(Tween.TRANS_SINE)
	_flicker_tween.set_ease(Tween.EASE_IN_OUT)
	_flicker_tween.tween_property(_light, ^"light_energy", target_energy, step_duration)
	_flicker_tween.tween_callback(_schedule_next_flicker)


## Returns the configuration dictionary for the active [member fire_preset].
func _get_preset_config() -> Dictionary:
	var raw: Variant = PRESET_CONFIGS.get(fire_preset, PRESET_CONFIGS[FirePreset.CAMPFIRE])
	if raw is Dictionary:
		return raw
	return {}


## Safely extracts a typed float from [param cfg] with [param fallback].
func _read_float(cfg: Dictionary, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get(key, fallback)
	if raw is float:
		return raw
	if raw is int:
		return float(raw)
	return fallback


## Safely extracts a typed [Vector3] from [param cfg] with [param fallback].
func _read_vec3(cfg: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var raw: Variant = cfg.get(key, fallback)
	if raw is Vector3:
		return raw
	return fallback


## Safely extracts a typed [Color] from [param cfg] with [param fallback].
func _read_color(cfg: Dictionary, key: String, fallback: Color) -> Color:
	var raw: Variant = cfg.get(key, fallback)
	if raw is Color:
		return raw
	return fallback
