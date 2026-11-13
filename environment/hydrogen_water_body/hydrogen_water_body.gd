## Volumetric and buoyant water body with synchronized 8-wave aperiodic Gerstner cascade,
## 16-slot interactive ripples, HL2 depth fog, underwater acoustics, and level tweening.
@tool
class_name HydrogenWaterBody
extends MeshInstance3D

## Emitted when a body or camera crosses the surface above [member min_splash_velocity].
signal splashed(global_pos: Vector3, velocity: float)

## Emitted when [method change_water_level] begins animating.
signal water_level_transition_started(is_lowered: bool)

## Emitted when [method change_water_level] finishes animating.
signal water_level_transition_finished(is_lowered: bool)

## Controls whether power/trigger calls toggle water level or fire once.
enum WaterLevelMode {
	TOGGLE = 0,
	ONE_SHOT = 1,
}

## Probe update mode mirror for child [ReflectionProbe] nodes.
enum ProbeUpdateMode {
	ONCE = 0,
	ALWAYS = 1,
}

const MACRO_DIRS: Array[Vector2] = [
	Vector2(0.848, 0.530),
	Vector2(-0.422, 0.906),
	Vector2(0.259, -0.966),
	Vector2(-0.934, -0.358),
	Vector2(0.616, -0.788),
	Vector2(-0.174, 0.985),
	Vector2(0.978, -0.208),
	Vector2(-0.743, 0.669),
]
const MACRO_AMP_SCALES: Array[float] = [0.36, 0.25, 0.17, 0.12, 0.08, 0.055, 0.038, 0.025]
const MACRO_LEN_SCALES: Array[float] = [1.00, 0.73, 0.51, 0.37, 0.26, 0.19, 0.13, 0.09]
const MACRO_SPD_SCALES: Array[float] = [1.00, 1.17, 1.38, 1.61, 1.89, 2.18, 2.53, 2.94]
const MACRO_PHASES: Array[float] = [
	0.00, 2.39996, 4.79992, 0.91670, 3.31666, 5.71662, 1.83340, 4.23336
]

const MAX_RIPPLES: int = 16
const RIPPLE_LIFETIME: float = 4.5
const WAKE_MIN_SPEED_SQ: float = 0.49
const WAKE_COOLDOWN: float = 0.16
const WAKE_MIN_DIST_SQ: float = 0.09

const PARAM_WATER_SIZE: StringName = &"water_size"
const PARAM_SHOW_SIDE_WALLS: StringName = &"show_side_walls"
const PARAM_WATER_TIME: StringName = &"water_time"
const PARAM_WAVE_AMPLITUDE: StringName = &"wave_amplitude"
const PARAM_WAVE_LENGTH: StringName = &"wave_length"
const PARAM_WAVE_SPEED: StringName = &"wave_speed"
const PARAM_WAVE_STEEPNESS: StringName = &"wave_steepness"
const PARAM_GERSTNER_SCALE: StringName = &"gerstner_horizontal_scale"
const PARAM_RIPPLE_HEIGHT: StringName = &"ripple_mesh_height"
const PARAM_RIPPLE_SIZE: StringName = &"ripple_size"
const PARAM_RIPPLES: StringName = &"ripples"
const PARAM_SHALLOW_COLOR: StringName = &"shallow_color"
const PARAM_DEEP_COLOR: StringName = &"deep_color"
const PARAM_CEILING_COLOR: StringName = &"underwater_ceiling_color"
const PARAM_FOG_BEGIN: StringName = &"underwater_fog_begin"
const PARAM_FOG_END: StringName = &"underwater_fog_end"
const PARAM_ABSORPTION: StringName = &"absorption_coefficients"
const PARAM_DEPTH_CONSUMPTION: StringName = &"depth_color_consumption"
const PARAM_DEPTH_DISTANCE: StringName = &"depth_distance"
const PARAM_BEERS_LAW: StringName = &"beers_law"
const PARAM_CREST_COLOR: StringName = &"crest_color"
const PARAM_CREST_GLOW: StringName = &"crest_glow_intensity"
const PARAM_FOAM_GLOW: StringName = &"aerated_foam_glow"
const PARAM_CAUSTICS_INTENSITY: StringName = &"caustics_intensity"
const PARAM_CAUSTICS_SCALE: StringName = &"caustics_scale"
const PARAM_ENABLE_SSR: StringName = &"enable_ssr"
const PARAM_SSR_MAX_DIST: StringName = &"ssr_max_distance"
const PARAM_REFRACTION: StringName = &"refraction_strength"
const PARAM_CHROMATIC: StringName = &"chromatic_aberration"
const PARAM_SKY_TINT: StringName = &"sky_reflection_tint"
const PARAM_FRESNEL_BASE: StringName = &"fresnel_base"
const PARAM_FRESNEL_POWER: StringName = &"fresnel_power"
const PARAM_ROUGHNESS: StringName = &"roughness"
const PARAM_SPECULAR: StringName = &"specular_strength"
const PARAM_METALLIC: StringName = &"metallic"
const PARAM_UV_SCALE: StringName = &"uv_scale"
const PARAM_NORMAL_BUMP: StringName = &"normal_bump_strength"
const PARAM_PAN_1: StringName = &"pan_speed_1"
const PARAM_PAN_2: StringName = &"pan_speed_2"
const PARAM_FOAM_NOISE: StringName = &"foam_noise"
const PARAM_FOAM_COLOR: StringName = &"foam_color"
const PARAM_FOAM_DISTANCE: StringName = &"foam_distance"
const PARAM_CREST_FOAM: StringName = &"crest_foam_threshold"
const GLOBAL_WETNESS_Y: StringName = &"hydrogen_water_surface_y"

@export_category("Volume & Geometry")
## Physical bounding dimensions (meters) of the water volume.
@export var water_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		water_size = Vector3(maxf(value.x, 0.1), maxf(value.y, 0.1), maxf(value.z, 0.1))
		_sync_volume_geometry()

## Subdivisions per meter on XZ faces (clamped 8-64 per axis).
@export_range(0.5, 16.0, 0.5) var vertex_density: float = 4.0:
	set(value):
		vertex_density = value
		_sync_mesh_subdivisions()

## Renders box side walls & bottom face and disables top-face shoreline feathering.
@export var show_side_walls: bool = false:
	set(value):
		show_side_walls = value
		_push_shader_param(PARAM_SHOW_SIDE_WALLS, show_side_walls)

## Sets update mode on any child [ReflectionProbe] nodes.
@export var probe_update_mode: ProbeUpdateMode = ProbeUpdateMode.ONCE:
	set(value):
		probe_update_mode = value
		_sync_reflection_probes()

@export_category("Wave Simulation")
## Primary octave vertical wave amplitude (meters).
@export_range(0.0, 5.0, 0.01) var wave_amplitude: float = 0.1:
	set(value):
		wave_amplitude = value
		_push_shader_param(PARAM_WAVE_AMPLITUDE, wave_amplitude)
		_update_custom_aabb()

## Primary octave wavelength (meters).
@export_range(0.25, 100.0, 0.05) var wave_length: float = 4.5:
	set(value):
		wave_length = value
		_push_shader_param(PARAM_WAVE_LENGTH, wave_length)

## Primary octave phase speed multiplier.
@export_range(0.0, 20.0, 0.05) var wave_speed: float = 1.4:
	set(value):
		wave_speed = value
		_push_shader_param(PARAM_WAVE_SPEED, wave_speed)

## Trochoidal second-harmonic crest sharpness across the 8-wave spectrum.
@export_range(0.0, 2.0, 0.01) var wave_steepness: float = 0.35:
	set(value):
		wave_steepness = value
		_push_shader_param(PARAM_WAVE_STEEPNESS, wave_steepness)

## Horizontal Gerstner crest pinching multiplier (0 = pure vertical displacement).
@export_range(0.0, 1.5, 0.01) var gerstner_horizontal_scale: float = 0.45:
	set(value):
		gerstner_horizontal_scale = value
		_push_shader_param(PARAM_GERSTNER_SCALE, gerstner_horizontal_scale)

## Vertical displacement scale for interactive ring ripples.
@export_range(0.0, 2.0, 0.01) var ripple_mesh_height: float = 0.22:
	set(value):
		ripple_mesh_height = value
		_push_shader_param(PARAM_RIPPLE_HEIGHT, ripple_mesh_height)
		_update_custom_aabb()

## Multiplier for ripple expansion speed, ring width, and inverse wavenumber.
@export_range(0.1, 10.0, 0.05) var ripple_size: float = 1.0:
	set(value):
		ripple_size = value
		_push_shader_param(PARAM_RIPPLE_SIZE, ripple_size)

@export_category("Optics, Absorption & HL2 Fog")
## Scatter tint for shallow water.
@export var shallow_color: Color = Color(0.22, 0.65, 0.78, 1.0):
	set(value):
		shallow_color = value
		_push_shader_param(PARAM_SHALLOW_COLOR, shallow_color)

## Scatter tint for deep murky water and underwater fog blend.
@export var deep_color: Color = Color(0.01, 0.05, 0.16, 1.0):
	set(value):
		deep_color = value
		_push_shader_param(PARAM_DEEP_COLOR, deep_color)

## Backface ceiling tint outside Snell's window and HL2 fog blend.
@export var underwater_ceiling_color: Color = Color(0.0, 0.1, 0.2, 1.0):
	set(value):
		underwater_ceiling_color = value
		_push_shader_param(PARAM_CEILING_COLOR, underwater_ceiling_color)

## Forces [constant Environment.FOG_MODE_DEPTH] on camera submersion.
@export var force_non_volumetric_fog: bool = true

## Linear HL2 fog start distance (meters).
@export_range(0.0, 50.0, 0.1) var underwater_fog_begin: float = 0.5:
	set(value):
		underwater_fog_begin = value
		_push_shader_param(PARAM_FOG_BEGIN, underwater_fog_begin)

## Linear HL2 fog full-opacity distance (meters).
@export_range(1.0, 200.0, 0.5) var underwater_fog_end: float = 28.0:
	set(value):
		underwater_fog_end = value
		_push_shader_param(PARAM_FOG_END, underwater_fog_end)

## Per-channel RGB Beer-Lambert absorption rates.
@export var absorption_coefficients: Vector3 = Vector3(1.4, 0.42, 0.08):
	set(value):
		absorption_coefficients = value
		_push_shader_param(PARAM_ABSORPTION, absorption_coefficients)

## Per-channel RGB distances (meters) before wavelengths fade out.
@export var depth_color_consumption: Vector3 = Vector3(22.0, 133.0, 168.0):
	set(value):
		depth_color_consumption = value
		_push_shader_param(PARAM_DEPTH_CONSUMPTION, depth_color_consumption)

## Optical depth normalization divisor (meters).
@export_range(0.1, 100.0, 0.1) var depth_distance: float = 4.5:
	set(value):
		depth_distance = value
		_push_shader_param(PARAM_DEPTH_DISTANCE, depth_distance)

## Exponential Beer-Lambert absorption and turbidity multiplier.
@export_range(0.1, 20.0, 0.1) var beers_law: float = 2.2:
	set(value):
		beers_law = value
		_push_shader_param(PARAM_BEERS_LAW, beers_law)

## Subsurface scattering (SSS) tint on thin wave peaks and aerated foam.
@export var crest_color: Color = Color(0.0, 0.65, 0.85, 1.0):
	set(value):
		crest_color = value
		_push_shader_param(PARAM_CREST_COLOR, crest_color)

## SSS glow intensity on thin turbulent crests and light backscatter.
@export_range(0.0, 2.0, 0.05) var crest_glow_intensity: float = 0.25:
	set(value):
		crest_glow_intensity = value
		_push_shader_param(PARAM_CREST_GLOW, crest_glow_intensity)

## SSS glow multiplier for aerated shoreline and wake foam.
@export_range(0.0, 2.0, 0.05) var aerated_foam_glow: float = 0.45:
	set(value):
		aerated_foam_glow = value
		_push_shader_param(PARAM_FOAM_GLOW, aerated_foam_glow)

## Projected underwater caustics intensity on submerged surfaces.
@export_range(0.0, 2.0, 0.05) var caustics_intensity: float = 0.45:
	set(value):
		caustics_intensity = value
		_push_shader_param(PARAM_CAUSTICS_INTENSITY, caustics_intensity)

## World-space tiling frequency for projected underwater caustics.
@export_range(0.05, 5.0, 0.05) var caustics_scale: float = 0.65:
	set(value):
		caustics_scale = value
		_push_shader_param(PARAM_CAUSTICS_SCALE, caustics_scale)

@export_category("Reflections & Surface Detail")
## Toggles 12-step view-space screen-space reflection raymarch.
@export var enable_ssr: bool = true:
	set(value):
		enable_ssr = value
		_push_shader_param(PARAM_ENABLE_SSR, enable_ssr)

## Max view-space raymarch distance (meters) for SSR.
@export_range(0.5, 50.0, 0.1) var ssr_max_distance: float = 4.5:
	set(value):
		ssr_max_distance = value
		_push_shader_param(PARAM_SSR_MAX_DIST, ssr_max_distance)

## Screen-space refraction UV offset strength.
@export_range(0.0, 0.2, 0.001) var refraction_strength: float = 0.025:
	set(value):
		refraction_strength = value
		_push_shader_param(PARAM_REFRACTION, refraction_strength)

## R/G/B UV dispersion split on refracted underwater samples.
@export_range(0.0, 0.1, 0.001) var chromatic_aberration: float = 0.015:
	set(value):
		chromatic_aberration = value
		_push_shader_param(PARAM_CHROMATIC, chromatic_aberration)

## Horizon/zenith sky reflection tint when SSR misses or is disabled.
@export var sky_reflection_tint: Color = Color(0.65, 0.82, 1.0, 1.0):
	set(value):
		sky_reflection_tint = value
		_push_shader_param(PARAM_SKY_TINT, sky_reflection_tint)

## Minimum reflectivity at normal incidence for custom Schlick Fresnel.
@export_range(0.0, 1.0, 0.01) var fresnel_base: float = 0.02:
	set(value):
		fresnel_base = value
		_push_shader_param(PARAM_FRESNEL_BASE, fresnel_base)

## Exponent for custom Schlick Fresnel curve.
@export_range(0.5, 10.0, 0.1) var fresnel_power: float = 4.5:
	set(value):
		fresnel_power = value
		_push_shader_param(PARAM_FRESNEL_POWER, fresnel_power)

## Surface micro-roughness driving PBR Fresnel, GGX specular, and backface ceiling.
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.03:
	set(value):
		roughness = value
		_push_shader_param(PARAM_ROUGHNESS, roughness)

## Specular highlight intensity multiplier.
@export_range(0.0, 1.0, 0.01) var specular_strength: float = 0.6:
	set(value):
		specular_strength = value
		_push_shader_param(PARAM_SPECULAR, specular_strength)

## Metallic reflectance factor (keep 0.0 for dielectric water).
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0:
	set(value):
		metallic = value
		_push_shader_param(PARAM_METALLIC, metallic)

## World-space XZ frequency scale for capillary micro-ripples and foam.
@export var uv_scale: Vector2 = Vector2(2.0, 2.0):
	set(value):
		uv_scale = value
		_push_shader_param(PARAM_UV_SCALE, uv_scale)

## Multiplier for isotropic capillary micro-ripple slopes.
@export_range(0.0, 8.0, 0.05) var normal_bump_strength: float = 1.6:
	set(value):
		normal_bump_strength = value
		_push_shader_param(PARAM_NORMAL_BUMP, normal_bump_strength)

## Primary wind direction bias for capillary wavelets.
@export var pan_speed_1: Vector2 = Vector2(0.1, 0.01):
	set(value):
		pan_speed_1 = value
		_push_shader_param(PARAM_PAN_1, pan_speed_1)

## Secondary wind direction bias for capillary wavelets.
@export var pan_speed_2: Vector2 = Vector2(-0.015, 0.025):
	set(value):
		pan_speed_2 = value
		_push_shader_param(PARAM_PAN_2, pan_speed_2)

@export_category("Foam")
## Seamless noise modulating shoreline, crest, and splash foam breakup.
@export var foam_noise: Texture2D = null:
	set(value):
		foam_noise = value
		_push_shader_param(PARAM_FOAM_NOISE, foam_noise)

## Foam albedo RGB and overall foam opacity multiplier (A).
@export var foam_color: Color = Color(0.92, 0.96, 1.0, 1.0):
	set(value):
		foam_color = value
		_push_shader_param(PARAM_FOAM_COLOR, foam_color)

## Water depth threshold (meters) for shoreline intersection foam.
@export_range(0.0, 5.0, 0.01) var foam_distance: float = 0.35:
	set(value):
		foam_distance = value
		_push_shader_param(PARAM_FOAM_DISTANCE, foam_distance)

## Normalized wave crest height threshold for whitecap foam.
@export_range(0.0, 2.0, 0.01) var crest_foam_threshold: float = 0.72:
	set(value):
		crest_foam_threshold = value
		_push_shader_param(PARAM_CREST_FOAM, crest_foam_threshold)

@export_category("Physics, Buoyancy & Audio")
## Upward buoyant acceleration multiplier (9.8 * buoyancy_power * submersion_ratio).
@export_range(0.1, 10.0, 0.05) var buoyancy_power: float = 1.5

## Linear drag opposing 3D velocity of submerged [RigidBody3D] nodes.
@export_range(0.0, 10.0, 0.05) var water_drag: float = 1.2

## Extra vertical damping opposing bobbing.
@export_range(0.0, 10.0, 0.05) var vertical_drag: float = 2.5

## Angular velocity damping factor per physics step.
@export_range(0.0, 10.0, 0.05) var angular_drag: float = 2.0

## Minimum vertical speed (m/s) to trigger splash signal, audio, and strong ripple.
@export_range(0.5, 20.0, 0.1) var min_splash_velocity: float = 4.0

## Sound stream played via [AudioPool] on high-speed splash.
@export var splash_sound: AudioStream = null

## Distance-gating radius (meters) from active camera before [method _process] pauses.
@export_range(10.0, 500.0, 1.0) var max_simulation_distance: float = 95.0

@export_category("Water Level Control")
## Controls whether power/trigger calls toggle water level or execute once.
@export var water_level_mode: WaterLevelMode = WaterLevelMode.TOGGLE

## Vertical size/level offset in meters (negative lowers, positive raises).
@export var target_level_delta: float = -20.0

## Base level transition duration in seconds.
@export_range(0.1, 120.0, 0.1) var level_change_duration: float = 5.0

## Tween curve type for level transitions.
@export var level_transition_type: Tween.TransitionType = Tween.TRANS_SINE

## Tween easing direction for level transitions.
@export var level_ease_type: Tween.EaseType = Tween.EASE_IN_OUT

var _water_time: float = 0.0
var _ripples: Array[Vector4] = []
var _ripple_cursor: int = 0
var _active_ripple_expiry: float = 0.0
var _ripples_cleared: bool = true
var _material_rid: RID = RID()

var _is_camera_submerged: bool = false
var _prev_cam_y: float = 0.0
var _has_prev_cam_y: bool = false

var _cached_env: Environment = null
var _injected_cam_env: bool = false
var _orig_fog_enabled: bool = false
var _orig_fog_mode: Environment.FogMode = Environment.FOG_MODE_EXPONENTIAL
var _orig_fog_light_color: Color = Color.WHITE
var _orig_fog_density: float = 0.0
var _orig_fog_depth_begin: float = 0.0
var _orig_fog_depth_end: float = 100.0
var _orig_fog_sky_affect: float = 1.0

var _submerged_bodies: Array[Node3D] = []
var _wake_timers: Dictionary[int, float] = {}
var _wake_positions: Dictionary[int, Vector2] = {}

var _base_water_size_y: float = 1.0
var _base_position_y: float = 0.0
var _is_lowered: bool = false
var _one_shot_used: bool = false
var _level_tween: Tween = null

@onready var _swimmable_area: Area3D = %SwimmableArea3D
@onready var _collision_shape: CollisionShape3D = %CollisionShape3D
@onready var _camera_cast: ShapeCast3D = %CameraPosShapeCast3D
@onready var _fog_volume: FogVolume = %FogVolume
@onready var _surface_audio: AudioStreamPlayer3D = %SurfaceAudio
@onready var _underwater_audio: AudioStreamPlayer3D = %UnderwaterAudio


## Initializes per-instance collision bounds, shader uniforms, and area signals.
func _ready() -> void:
	process_priority = 999
	layers = 4
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	_ripples.resize(MAX_RIPPLES)
	for i: int in range(MAX_RIPPLES):
		_ripples[i] = Vector4.ZERO

	_base_water_size_y = water_size.y
	_base_position_y = position.y

	if is_instance_valid(_collision_shape) and _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate() as BoxShape3D

	_cache_material_rid()
	_sync_volume_geometry()
	_push_all_uniforms()
	_sync_reflection_probes()

	if Engine.is_editor_hint():
		set_physics_process(false)
		return

	assert(is_instance_valid(_swimmable_area), "HydrogenWaterBody requires %SwimmableArea3D")
	assert(is_instance_valid(_collision_shape), "HydrogenWaterBody requires %CollisionShape3D")
	assert(is_instance_valid(_camera_cast), "HydrogenWaterBody requires %CameraPosShapeCast3D")
	assert(is_instance_valid(_fog_volume), "HydrogenWaterBody requires %FogVolume")

	_swimmable_area.body_entered.connect(_on_swimmable_area_body_entered)
	_swimmable_area.body_exited.connect(_on_swimmable_area_body_exited)
	_swimmable_area.area_entered.connect(_on_swimmable_area_area_entered)
	_swimmable_area.area_exited.connect(_on_swimmable_area_area_exited)

	if is_instance_valid(_underwater_audio):
		_underwater_audio.stop()


## Advances wave clock, evaluates camera submersion, and cleans expired ripples.
func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if not Engine.is_editor_hint() and is_instance_valid(cam):
		var half_extents: Vector3 = (global_transform.basis.get_scale() * water_size) * 0.5
		var max_dist: float = max_simulation_distance + half_extents.length()
		var dist_sq: float = global_position.distance_squared_to(cam.global_position)
		if not _is_camera_submerged and dist_sq > max_dist * max_dist:
			return

	_water_time += delta
	_push_shader_param(PARAM_WATER_TIME, _water_time)

	if not _ripples_cleared and _water_time > _active_ripple_expiry:
		for i: int in range(MAX_RIPPLES):
			_ripples[i] = Vector4.ZERO
		_push_shader_param(PARAM_RIPPLES, _ripples)
		_ripples_cleared = true

	if Engine.is_editor_hint():
		return

	_update_camera_submersion(cam, delta)


## Applies multi-probe buoyancy and spawns movement wakes for submerged bodies.
func _physics_process(delta: float) -> void:
	if _submerged_bodies.is_empty():
		return

	var idx: int = _submerged_bodies.size() - 1
	while idx >= 0:
		var body: Node3D = _submerged_bodies[idx]
		if not is_instance_valid(body):
			_submerged_bodies.remove_at(idx)
			idx -= 1
			continue

		_update_body_wake(body, delta)
		if body is RigidBody3D:
			_apply_rigidbody_buoyancy(body as RigidBody3D, delta)
		idx -= 1


## Restores modified environment fog state on exit.
func _exit_tree() -> void:
	if _is_camera_submerged:
		_restore_environment_fog()
	if is_instance_valid(_level_tween):
		_level_tween.kill()


## Maps legacy property names size -> water_size and material -> material_override.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"size" and value is Vector3:
		water_size = value as Vector3
		return true
	if property == &"material":
		material_override = value as Material
		_cache_material_rid()
		_push_all_uniforms()
		return true
	return false


## Exposes legacy property names size and material for backward compatibility.
func _get(property: StringName) -> Variant:
	if property == &"size":
		return water_size
	if property == &"material":
		return material_override
	return null


## Evaluates exact global surface Y at XZ (base top Y + 8-wave Gerstner cascade + 16 ripples).
func get_wave_height_at_pos(global_pos: Vector3) -> float:
	var local_pos: Vector3 = to_local(global_pos)
	var base_top_local_y: float = water_size.y * 0.5
	var base_top_world: Vector3 = to_global(Vector3(local_pos.x, base_top_local_y, local_pos.z))

	var sample_xz: Vector2 = Vector2(base_top_world.x, base_top_world.z)
	for _iter: int in range(2):
		var g_offset: Vector2 = _evaluate_gerstner_xz(sample_xz)
		sample_xz = Vector2(base_top_world.x, base_top_world.z) - g_offset

	var wave_data: Vector3 = _evaluate_wave_cascade(sample_xz)
	var ripple_data: Vector3 = _evaluate_ripples(sample_xz)
	var total_disp: float = wave_data.x + ripple_data.x
	var displaced_world: Vector3 = base_top_world + global_transform.basis.y * total_disp
	return displaced_world.y


## Returns analytical normalized 3D world surface normal at XZ.
func get_water_surface_normal(global_pos: Vector3) -> Vector3:
	var sample_xz: Vector2 = Vector2(global_pos.x, global_pos.z)
	for _iter: int in range(2):
		var g_offset: Vector2 = _evaluate_gerstner_xz(sample_xz)
		sample_xz = Vector2(global_pos.x, global_pos.z) - g_offset

	var wave_data: Vector3 = _evaluate_wave_cascade(sample_xz)
	var ripple_data: Vector3 = _evaluate_ripples(sample_xz)
	var slope_x: float = wave_data.y + ripple_data.y
	var slope_z: float = wave_data.z + ripple_data.z
	var local_n: Vector3 = Vector3(-slope_x, 1.0, -slope_z).normalized()
	return (global_transform.basis * local_n).normalized()


## Plays splash_sound at surface Y via AudioPool on bus SFX, scaled by impact speed.
func play_splash_sound(impact_pos: Vector3, speed: float) -> void:
	if splash_sound == null:
		return
	var surface_y: float = get_wave_height_at_pos(impact_pos)
	var play_pos: Vector3 = Vector3(impact_pos.x, surface_y, impact_pos.z)
	var norm_speed: float = clampf((speed - min_splash_velocity) / 12.0, 0.0, 1.0)
	var volume_db: float = lerpf(-6.0, 3.0, norm_speed)
	var pitch: float = lerpf(0.88, 1.18, norm_speed)
	var pool: Node = get_node_or_null(^"/root/AudioPool")
	if pool != null and pool.has_method(&"play_sfx_3d"):
		pool.call(&"play_sfx_3d", splash_sound, play_pos, &"SFX", volume_db, pitch)


## Writes (x, z, water_time, clamped_amp) into the 16-slot circular buffer and pushes uniform.
func spawn_ripple(global_pos: Vector3, impact_strength: float) -> void:
	var clamped_amp: float = clampf(impact_strength, 0.05, 2.5)
	_ripples[_ripple_cursor] = Vector4(global_pos.x, global_pos.z, _water_time, clamped_amp)
	_ripple_cursor = (_ripple_cursor + 1) % MAX_RIPPLES
	_active_ripple_expiry = _water_time + RIPPLE_LIFETIME
	_ripples_cleared = false
	_push_shader_param(PARAM_RIPPLES, _ripples)


## Checks XZ bounds, floor Y, optional CameraPosShapeCast3D overlap, and camera Y < wave height.
func should_draw_camera_underwater_effect() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if not is_instance_valid(cam):
		return false

	var cam_pos: Vector3 = cam.global_position
	var local_cam: Vector3 = to_local(cam_pos)
	var half: Vector3 = water_size * 0.5
	if absf(local_cam.x) > half.x or absf(local_cam.z) > half.z:
		return false
	if local_cam.y < -half.y:
		return false

	if is_instance_valid(_camera_cast):
		_camera_cast.global_position = cam_pos
		_camera_cast.force_shapecast_update()
		if _camera_cast.is_colliding():
			var overlaps_self: bool = false
			for i: int in range(_camera_cast.get_collision_count()):
				if _camera_cast.get_collider(i) == _swimmable_area:
					overlaps_self = true
					break
			if not overlaps_self:
				return false

	var surface_y: float = get_wave_height_at_pos(cam_pos)
	return cam_pos.y < surface_y


## Power transmitter entry point: lowers/activates target level delta.
func power_on() -> void:
	if water_level_mode == WaterLevelMode.ONE_SHOT and _one_shot_used:
		return
	_one_shot_used = true
	change_water_level(true)


## Power transmitter entry point: restores baseline level when in TOGGLE mode.
func power_off() -> void:
	if water_level_mode == WaterLevelMode.ONE_SHOT:
		return
	change_water_level(false)


## Trigger entry point toggling between baseline and target water level.
func toggle_water_level() -> void:
	if water_level_mode == WaterLevelMode.ONE_SHOT:
		if _one_shot_used:
			return
		_one_shot_used = true
		change_water_level(true)
		return
	change_water_level(not _is_lowered)


## Tweens position:y and water_size.y simultaneously so the floor remains anchored.
func change_water_level(to_lowered: bool) -> void:
	if is_instance_valid(_level_tween):
		_level_tween.kill()

	_is_lowered = to_lowered
	var target_size_y: float = maxf(
		_base_water_size_y + (target_level_delta if to_lowered else 0.0), 0.1
	)
	var applied_delta: float = target_size_y - _base_water_size_y
	var target_pos_y: float = _base_position_y + applied_delta * 0.5

	var remaining_ratio: float = 1.0
	if absf(applied_delta) > 0.001:
		remaining_ratio = clampf(
			absf(target_size_y - water_size.y) / absf(applied_delta), 0.05, 1.0
		)
	var duration: float = maxf(level_change_duration * remaining_ratio, 0.05)

	water_level_transition_started.emit(to_lowered)
	_level_tween = create_tween()
	_level_tween.set_ignore_time_scale(true)
	_level_tween.set_parallel(true)
	_level_tween.set_trans(level_transition_type)
	_level_tween.set_ease(level_ease_type)
	_level_tween.tween_property(self, ^"water_size:y", target_size_y, duration)
	_level_tween.tween_property(self, ^"position:y", target_pos_y, duration)
	_level_tween.chain().tween_callback(_on_level_tween_finished.bind(to_lowered))


## Returns true when no water level transition tween is actively running.
func is_level_transition_complete() -> bool:
	return not is_instance_valid(_level_tween) or not _level_tween.is_running()


## Rotates a 2D vector by angle (radians), matching GLSL rotate2d.
func _rotate2d(p: Vector2, angle: float) -> Vector2:
	var s: float = sin(angle)
	var c: float = cos(angle)
	return Vector2(c * p.x - s * p.y, s * p.x + c * p.y)


## Evaluates 8-wave golden-angle trochoidal wave height and slopes matching GLSL shader.
func _evaluate_wave_cascade(xz: Vector2) -> Vector3:
	var h: float = 0.0
	var slope_x: float = 0.0
	var slope_z: float = 0.0

	var inv_wl: float = 1.0 / maxf(wave_length, 0.5)
	var env_p1: Vector2 = (
		_rotate2d(xz, 0.52) * (0.42 * inv_wl) + Vector2(_water_time * 0.12, -_water_time * 0.09)
	)
	var env_p2: Vector2 = (
		_rotate2d(xz, 1.94) * (0.67 * inv_wl) + Vector2(-_water_time * 0.08, _water_time * 0.14)
	)
	var group_env: float = (
		0.72 + 0.28 * sin(env_p1.x + cos(env_p1.y)) * cos(env_p2.y - sin(env_p2.x))
	)
	var stp_base: float = clampf(wave_steepness, 0.0, 2.0) * 0.45

	for i: int in range(8):
		var amp: float = wave_amplitude * MACRO_AMP_SCALES[i] * group_env
		var wl: float = maxf(wave_length * MACRO_LEN_SCALES[i], 0.05)
		var k: float = TAU / wl
		var spd: float = wave_speed * MACRO_SPD_SCALES[i]
		var stp: float = stp_base * (1.0 - float(i) * 0.07)
		var d: Vector2 = MACRO_DIRS[i]

		var theta: float = d.dot(xz) * k + _water_time * spd * k + MACRO_PHASES[i]
		var s1: float = sin(theta)
		var c1: float = cos(theta)
		var s2: float = sin(2.0 * theta)
		var c2: float = cos(2.0 * theta)

		h += amp * (s1 + 0.5 * stp * s2)
		var dh: float = amp * k * (c1 + stp * c2)
		slope_x += d.x * dh
		slope_z += d.y * dh

	return Vector3(h, slope_x, slope_z)


## Evaluates horizontal Gerstner XZ offset across 8 waves for inverse surface lookup.
func _evaluate_gerstner_xz(xz: Vector2) -> Vector2:
	var offset: Vector2 = Vector2.ZERO
	var inv_wl: float = 1.0 / maxf(wave_length, 0.5)
	var env_p1: Vector2 = (
		_rotate2d(xz, 0.52) * (0.42 * inv_wl) + Vector2(_water_time * 0.12, -_water_time * 0.09)
	)
	var env_p2: Vector2 = (
		_rotate2d(xz, 1.94) * (0.67 * inv_wl) + Vector2(-_water_time * 0.08, _water_time * 0.14)
	)
	var group_env: float = (
		0.72 + 0.28 * sin(env_p1.x + cos(env_p1.y)) * cos(env_p2.y - sin(env_p2.x))
	)
	var stp_base: float = clampf(wave_steepness, 0.0, 2.0) * 0.45

	for i: int in range(8):
		var amp: float = wave_amplitude * MACRO_AMP_SCALES[i] * group_env
		var wl: float = maxf(wave_length * MACRO_LEN_SCALES[i], 0.05)
		var k: float = TAU / wl
		var spd: float = wave_speed * MACRO_SPD_SCALES[i]
		var stp: float = stp_base * (1.0 - float(i) * 0.07)
		var d: Vector2 = MACRO_DIRS[i]
		var theta: float = d.dot(xz) * k + _water_time * spd * k + MACRO_PHASES[i]
		offset -= d * (amp * stp * gerstner_horizontal_scale * cos(theta))

	return offset


## Evaluates 16-slot interactive ripple displacement and slopes matching GLSL shader.
func _evaluate_ripples(xz: Vector2) -> Vector3:
	if _ripples_cleared:
		return Vector3.ZERO

	var total_h: float = 0.0
	var slope_x: float = 0.0
	var slope_z: float = 0.0
	var r_scale: float = maxf(ripple_size, 0.1)
	var speed: float = 3.2 * r_scale
	var sigma: float = 0.45 * r_scale
	var inv_two_sigma_sq: float = 1.0 / (2.0 * sigma * sigma)
	var k: float = 14.0 / r_scale

	for i: int in range(MAX_RIPPLES):
		var r: Vector4 = _ripples[i]
		if r.w <= 0.0001:
			continue
		var age: float = _water_time - r.z
		if age < 0.0 or age > RIPPLE_LIFETIME:
			continue
		var dx: float = xz.x - r.x
		var dz: float = xz.y - r.y
		var dist: float = sqrt(dx * dx + dz * dz)
		var radius: float = age * speed
		var diff: float = dist - radius
		var env: float = exp(-(diff * diff) * inv_two_sigma_sq)
		var decay: float = exp(-age * 1.15) * (1.0 - age / RIPPLE_LIFETIME)
		var amp: float = r.w * ripple_mesh_height * decay
		var phase: float = diff * k
		total_h += amp * env * cos(phase)

		if dist > 0.001:
			var d_env: float = -diff / (sigma * sigma)
			var d_cos: float = -k * sin(phase)
			var dh_dr: float = amp * env * (d_env * cos(phase) + d_cos)
			slope_x += (dx / dist) * dh_dr
			slope_z += (dz / dist) * dh_dr

	return Vector3(total_h, slope_x, slope_z)


## Handles camera submersion state transitions, HL2 fog overrides, audio, and screen VFX.
func _update_camera_submersion(cam: Camera3D, delta: float) -> void:
	if not is_instance_valid(cam):
		return

	var cam_y: float = cam.global_position.y
	var cam_vel_y: float = 0.0
	if _has_prev_cam_y and delta > 0.0001:
		cam_vel_y = (cam_y - _prev_cam_y) / delta
	_prev_cam_y = cam_y
	_has_prev_cam_y = true

	var submerged_now: bool = should_draw_camera_underwater_effect()
	if submerged_now == _is_camera_submerged:
		return

	_is_camera_submerged = submerged_now
	if _is_camera_submerged:
		_apply_hl2_environment_fog(cam)
		if is_instance_valid(_surface_audio):
			_surface_audio.stream_paused = true
		if is_instance_valid(_underwater_audio):
			_underwater_audio.play()
		_emit_events_signal(&"underwater_vfx_toggled", [true])
		_emit_events_signal(&"waterfall_vfx_toggled", [true])
	else:
		_restore_environment_fog()
		if is_instance_valid(_underwater_audio):
			_underwater_audio.stop()
		if is_instance_valid(_surface_audio):
			_surface_audio.stream_paused = false
		_emit_events_signal(&"underwater_vfx_toggled", [false])
		_emit_events_signal(&"waterfall_vfx_toggled", [false])
		_emit_events_signal(&"water_sheet_wipe_requested", [1.2])
		if cam_vel_y >= min_splash_velocity:
			splashed.emit(cam.global_position, cam_vel_y)
			play_splash_sound(cam.global_position, cam_vel_y)
			spawn_ripple(cam.global_position, clampf(cam_vel_y / 8.0, 0.3, 1.5))


## Caches and overrides Camera3D or World3D Environment with HL2 linear depth fog.
func _apply_hl2_environment_fog(cam: Camera3D) -> void:
	var target_env: Environment = cam.environment
	_injected_cam_env = false
	if target_env == null and is_inside_tree() and get_world_3d() != null:
		target_env = get_world_3d().environment
	if target_env == null:
		target_env = Environment.new()
		cam.environment = target_env
		_injected_cam_env = true

	_cached_env = target_env
	_orig_fog_enabled = target_env.fog_enabled
	_orig_fog_mode = target_env.fog_mode
	_orig_fog_light_color = target_env.fog_light_color
	_orig_fog_density = target_env.fog_density
	_orig_fog_depth_begin = target_env.fog_depth_begin
	_orig_fog_depth_end = target_env.fog_depth_end
	_orig_fog_sky_affect = target_env.fog_sky_affect

	target_env.fog_enabled = true
	if force_non_volumetric_fog:
		target_env.fog_mode = Environment.FOG_MODE_DEPTH
	target_env.fog_light_color = deep_color.lerp(underwater_ceiling_color, 0.5)
	target_env.fog_density = 1.0
	target_env.fog_depth_begin = underwater_fog_begin
	target_env.fog_depth_end = underwater_fog_end
	target_env.fog_sky_affect = 1.0


## Restores exact pre-submersion Environment fog parameters.
func _restore_environment_fog() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if _injected_cam_env and is_instance_valid(cam):
		cam.environment = null
	elif is_instance_valid(_cached_env):
		_cached_env.fog_enabled = _orig_fog_enabled
		_cached_env.fog_mode = _orig_fog_mode
		_cached_env.fog_light_color = _orig_fog_light_color
		_cached_env.fog_density = _orig_fog_density
		_cached_env.fog_depth_begin = _orig_fog_depth_begin
		_cached_env.fog_depth_end = _orig_fog_depth_end
		_cached_env.fog_sky_affect = _orig_fog_sky_affect
	_cached_env = null
	_injected_cam_env = false


## Applies 4-corner bounding-box multi-probe buoyancy and damping to RigidBody3D.
func _apply_rigidbody_buoyancy(rb: RigidBody3D, delta: float) -> void:
	if rb.get(&"_probes") != null and rb.get(&"is_in_water") != null:
		return

	var half_ext: Vector3 = Vector3(0.35, 0.35, 0.35)
	for child: Node in rb.get_children():
		if child is CollisionShape3D:
			var cs: CollisionShape3D = child as CollisionShape3D
			if cs.shape != null:
				half_ext = cs.shape.get_debug_mesh().get_aabb().size * 0.5
				break

	var local_probes: Array[Vector3] = [
		Vector3(-half_ext.x, -half_ext.y, -half_ext.z),
		Vector3(half_ext.x, -half_ext.y, -half_ext.z),
		Vector3(-half_ext.x, -half_ext.y, half_ext.z),
		Vector3(half_ext.x, -half_ext.y, half_ext.z),
	]

	var probe_count: float = float(local_probes.size())
	var any_submerged: bool = false
	for local_pt: Vector3 in local_probes:
		var world_pt: Vector3 = rb.to_global(local_pt)
		var surface_y: float = get_wave_height_at_pos(world_pt)
		var depth: float = surface_y - world_pt.y
		if depth <= 0.0:
			continue
		any_submerged = true
		var submersion_ratio: float = clampf(depth / 1.2, 0.0, 1.5)
		var up_accel: float = (9.8 * buoyancy_power * submersion_ratio) / probe_count
		var force: Vector3 = Vector3.UP * (rb.mass * up_accel)
		rb.apply_force(force, world_pt - rb.global_position)

	if not any_submerged:
		return

	rb.linear_velocity *= maxf(1.0 - water_drag * delta, 0.0)
	rb.linear_velocity.y *= maxf(1.0 - vertical_drag * delta, 0.0)
	rb.angular_velocity *= maxf(1.0 - angular_drag * delta, 0.0)


## Spawns periodic movement ripples when submerged bodies travel horizontally.
func _update_body_wake(body: Node3D, delta: float) -> void:
	var id: int = body.get_instance_id()
	var elapsed: float = _wake_timers.get(id, WAKE_COOLDOWN) + delta
	_wake_timers[id] = elapsed
	if elapsed < WAKE_COOLDOWN:
		return

	var pos_xz: Vector2 = Vector2(body.global_position.x, body.global_position.z)
	var prev_xz: Vector2 = _wake_positions.get(id, pos_xz)
	var dist_sq: float = pos_xz.distance_squared_to(prev_xz)
	if dist_sq < WAKE_MIN_DIST_SQ:
		return

	var vel_sq: float = dist_sq / maxf(elapsed * elapsed, 0.0001)
	if vel_sq < WAKE_MIN_SPEED_SQ:
		return

	_wake_timers[id] = 0.0
	_wake_positions[id] = pos_xz
	var speed: float = sqrt(vel_sq)
	spawn_ripple(body.global_position, clampf(speed * 0.14, 0.15, 0.75))


## Handles body entry: triggers splash audio/ripples, tracks buoyancy, and calls swim hooks.
func _on_swimmable_area_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	if not _submerged_bodies.has(body):
		_submerged_bodies.append(body)

	var vel_y: float = 0.0
	if body is RigidBody3D:
		vel_y = absf((body as RigidBody3D).linear_velocity.y)
	elif body is CharacterBody3D:
		vel_y = absf((body as CharacterBody3D).velocity.y)

	if vel_y >= min_splash_velocity:
		splashed.emit(body.global_position, vel_y)
		play_splash_sound(body.global_position, vel_y)
		spawn_ripple(body.global_position, clampf(vel_y / 7.5, 0.4, 2.0))
	else:
		spawn_ripple(body.global_position, 0.25)

	_notify_swim_state(body, true)


## Handles body exit: removes buoyancy tracking and notifies swim hooks.
func _on_swimmable_area_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	_submerged_bodies.erase(body)
	var id: int = body.get_instance_id()
	_wake_timers.erase(id)
	_wake_positions.erase(id)
	_notify_swim_state(body, false)


## Handles overlapping Area3D swim/environment components entering the water.
func _on_swimmable_area_area_entered(area: Area3D) -> void:
	if is_instance_valid(area) and area.get_parent() is Node3D:
		_notify_swim_state(area.get_parent() as Node3D, true)


## Handles overlapping Area3D swim/environment components exiting the water.
func _on_swimmable_area_area_exited(area: Area3D) -> void:
	if is_instance_valid(area) and area.get_parent() is Node3D:
		_notify_swim_state(area.get_parent() as Node3D, false)


## Invokes enter_water/exit_water and sets current_water_node/is_in_water on bodies or components.
func _notify_swim_state(target: Node3D, entering: bool) -> void:
	var targets: Array[Node] = [target]
	var env_comp: Node = target.get_node_or_null(^"EnvironmentComponent")
	if env_comp == null:
		env_comp = target.get(&"environment_component") as Node
	if is_instance_valid(env_comp):
		targets.append(env_comp)

	for node: Node in targets:
		if entering:
			if node.has_method(&"enter_water"):
				node.call(&"enter_water", self)
			if &"current_water_node" in node:
				node.set(&"current_water_node", self)
			if &"is_in_water" in node:
				node.set(&"is_in_water", true)
		else:
			if node.has_method(&"exit_water"):
				node.call(&"exit_water", self)
			if &"current_water_node" in node and node.get(&"current_water_node") == self:
				node.set(&"current_water_node", null)
			if &"is_in_water" in node:
				node.set(&"is_in_water", false)


## Synchronizes BoxMesh subdivisions, custom AABB, CollisionShape3D, FogVolume, and shader size.
func _sync_volume_geometry() -> void:
	_sync_mesh_subdivisions()
	_update_custom_aabb()
	_push_shader_param(PARAM_WATER_SIZE, water_size)

	if is_instance_valid(_collision_shape) and _collision_shape.shape is BoxShape3D:
		(_collision_shape.shape as BoxShape3D).size = water_size
	if is_instance_valid(_fog_volume):
		_fog_volume.size = water_size

	var top_world_y: float = to_global(Vector3(0.0, water_size.y * 0.5, 0.0)).y
	RenderingServer.global_shader_parameter_set(GLOBAL_WETNESS_Y, top_world_y)


## Auto-scales BoxMesh XZ subdivisions by vertex_density (clamped 8-64, height 0).
func _sync_mesh_subdivisions() -> void:
	if mesh is BoxMesh:
		var box: BoxMesh = mesh as BoxMesh
		box.size = Vector3.ONE
		box.subdivide_width = clampi(roundi(water_size.x * vertex_density), 8, 64)
		box.subdivide_depth = clampi(roundi(water_size.z * vertex_density), 8, 64)
		box.subdivide_height = 0


## Pads custom_aabb vertically by max wave + ripple displacement to prevent culling pops.
func _update_custom_aabb() -> void:
	var pad_y: float = 2.0 * wave_amplitude + 2.0 * ripple_mesh_height + 0.5
	var pad_xz: float = wave_amplitude * wave_steepness * gerstner_horizontal_scale * 2.0
	var total_size: Vector3 = Vector3(
		water_size.x + pad_xz * 2.0, water_size.y + pad_y * 2.0, water_size.z + pad_xz * 2.0
	)
	custom_aabb = AABB(-total_size * 0.5, total_size)


## Applies probe_update_mode to any child ReflectionProbe nodes.
func _sync_reflection_probes() -> void:
	for child: Node in get_children():
		if child is ReflectionProbe:
			var probe: ReflectionProbe = child as ReflectionProbe
			probe.update_mode = (
				ReflectionProbe.UPDATE_ALWAYS
				if probe_update_mode == ProbeUpdateMode.ALWAYS
				else ReflectionProbe.UPDATE_ONCE
			)


## Finalizes water level tween and resyncs collision, fog volume, and mesh bounds.
func _on_level_tween_finished(is_lowered: bool) -> void:
	_sync_volume_geometry()
	water_level_transition_finished.emit(is_lowered)


## Caches active ShaderMaterial RID for zero-overhead RenderingServer uniform updates.
func _cache_material_rid() -> void:
	var mat: Material = get_active_material(0)
	if mat is ShaderMaterial:
		_material_rid = (mat as ShaderMaterial).get_rid()
	else:
		_material_rid = RID()


## Pushes a single uniform parameter via cached RenderingServer RID.
func _push_shader_param(param: StringName, value: Variant) -> void:
	if not _material_rid.is_valid():
		_cache_material_rid()
	if _material_rid.is_valid():
		RenderingServer.material_set_param(_material_rid, param, value)


## Pushes all exported shader parameters to the active ShaderMaterial.
func _push_all_uniforms() -> void:
	_push_shader_param(PARAM_WATER_SIZE, water_size)
	_push_shader_param(PARAM_SHOW_SIDE_WALLS, show_side_walls)
	_push_shader_param(PARAM_WATER_TIME, _water_time)
	_push_shader_param(PARAM_WAVE_AMPLITUDE, wave_amplitude)
	_push_shader_param(PARAM_WAVE_LENGTH, wave_length)
	_push_shader_param(PARAM_WAVE_SPEED, wave_speed)
	_push_shader_param(PARAM_WAVE_STEEPNESS, wave_steepness)
	_push_shader_param(PARAM_GERSTNER_SCALE, gerstner_horizontal_scale)
	_push_shader_param(PARAM_RIPPLE_HEIGHT, ripple_mesh_height)
	_push_shader_param(PARAM_RIPPLE_SIZE, ripple_size)
	_push_shader_param(PARAM_RIPPLES, _ripples)
	_push_shader_param(PARAM_SHALLOW_COLOR, shallow_color)
	_push_shader_param(PARAM_DEEP_COLOR, deep_color)
	_push_shader_param(PARAM_CEILING_COLOR, underwater_ceiling_color)
	_push_shader_param(PARAM_FOG_BEGIN, underwater_fog_begin)
	_push_shader_param(PARAM_FOG_END, underwater_fog_end)
	_push_shader_param(PARAM_ABSORPTION, absorption_coefficients)
	_push_shader_param(PARAM_DEPTH_CONSUMPTION, depth_color_consumption)
	_push_shader_param(PARAM_DEPTH_DISTANCE, depth_distance)
	_push_shader_param(PARAM_BEERS_LAW, beers_law)
	_push_shader_param(PARAM_CREST_COLOR, crest_color)
	_push_shader_param(PARAM_CREST_GLOW, crest_glow_intensity)
	_push_shader_param(PARAM_FOAM_GLOW, aerated_foam_glow)
	_push_shader_param(PARAM_CAUSTICS_INTENSITY, caustics_intensity)
	_push_shader_param(PARAM_CAUSTICS_SCALE, caustics_scale)
	_push_shader_param(PARAM_ENABLE_SSR, enable_ssr)
	_push_shader_param(PARAM_SSR_MAX_DIST, ssr_max_distance)
	_push_shader_param(PARAM_REFRACTION, refraction_strength)
	_push_shader_param(PARAM_CHROMATIC, chromatic_aberration)
	_push_shader_param(PARAM_SKY_TINT, sky_reflection_tint)
	_push_shader_param(PARAM_FRESNEL_BASE, fresnel_base)
	_push_shader_param(PARAM_FRESNEL_POWER, fresnel_power)
	_push_shader_param(PARAM_ROUGHNESS, roughness)
	_push_shader_param(PARAM_SPECULAR, specular_strength)
	_push_shader_param(PARAM_METALLIC, metallic)
	_push_shader_param(PARAM_UV_SCALE, uv_scale)
	_push_shader_param(PARAM_NORMAL_BUMP, normal_bump_strength)
	_push_shader_param(PARAM_PAN_1, pan_speed_1)
	_push_shader_param(PARAM_PAN_2, pan_speed_2)
	_push_shader_param(PARAM_FOAM_NOISE, foam_noise)
	_push_shader_param(PARAM_FOAM_COLOR, foam_color)
	_push_shader_param(PARAM_FOAM_DISTANCE, foam_distance)
	_push_shader_param(PARAM_CREST_FOAM, crest_foam_threshold)


## Emits a signal on the global Events autoload if present.
func _emit_events_signal(sig_name: StringName, args: Array) -> void:
	var events: Node = get_node_or_null(^"/root/Events")
	if events != null and events.has_signal(sig_name):
		events.callv(&"emit_signal", [sig_name] + args)
