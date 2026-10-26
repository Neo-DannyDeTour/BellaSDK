@tool
## High-performance 3D water volume handling multi-scale waves, buoyancy, and underwater VFX.
class_name WaterBody
extends MeshInstance3D

## Emitted when a physical body enters or exits the water volume at high vertical speed.
signal splashed(global_pos: Vector3, velocity: float)

## Emitted when a water level transition begins.
signal water_level_transition_started(is_lowered: bool)

## Emitted when a water level transition completes.
signal water_level_transition_finished(is_lowered: bool)

## Operational modes governing how water level responds to power triggers.
enum WaterLevelMode {
	TOGGLE = 0,
	ONE_SHOT = 1,
}

## Group identifier required by [StateSwim] for point-intersection submersion queries.
const GROUP_WATER_AREA: StringName = &"water_area"

## Audio bus identifier used for 3D splash sound effects.
const BUS_SFX: StringName = &"SFX"

## Method identifier invoked on actors entering the water volume.
const METHOD_ENTER_WATER: StringName = &"enter_water"

## Method identifier invoked on actors exiting the water volume.
const METHOD_EXIT_WATER: StringName = &"exit_water"

## Property identifier for actor environment subcomponents.
const PROP_ENV_COMPONENT: StringName = &"environment_component"

## Property identifier for tracking active water node on pickable rigid bodies.
const PROP_CURRENT_WATER_NODE: StringName = &"current_water_node"

## Property identifier for tracking water overlap state on pickable rigid bodies.
const PROP_IS_IN_WATER: StringName = &"is_in_water"

## Property identifier for multi-probe array on [PickableObject] instances.
const PROP_PROBES: StringName = &"_probes"

## Legacy property alias for water volume size used in older scenes.
const PROP_LEGACY_SIZE: StringName = &"size"

## Legacy property alias for material override used in older scenes.
const PROP_LEGACY_MATERIAL: StringName = &"material"

## Shader uniform identifier for elapsed water simulation time.
const PARAM_WATER_TIME: StringName = &"water_time"

## Shader uniform identifier for 3D water box dimensions.
const PARAM_WATER_SIZE: StringName = &"water_size"

## Shader uniform identifier toggling exterior box side wall rendering.
const PARAM_SHOW_SIDE_WALLS: StringName = &"show_side_walls"

## Shader uniform identifier for shallow water scatter color.
const PARAM_SHALLOW_COLOR: StringName = &"shallow_color"

## Shader uniform identifier for deep water scatter color.
const PARAM_DEEP_COLOR: StringName = &"deep_color"

## Shader uniform identifier for underwater ceiling tint color.
const PARAM_UNDERWATER_CEILING_COLOR: StringName = &"underwater_ceiling_color"

## Shader uniform identifier for RGB Beer-Lambert absorption rates.
const PARAM_ABSORPTION_COEFFS: StringName = &"absorption_coefficients"

## Shader uniform identifier for optical depth normalization distance.
const PARAM_DEPTH_DISTANCE: StringName = &"depth_distance"

## Shader uniform identifier for Beer-Lambert exponential multiplier.
const PARAM_BEERS_LAW: StringName = &"beers_law"

## Shader uniform identifier for primary wave amplitude.
const PARAM_WAVE_AMPLITUDE: StringName = &"wave_amplitude"

## Shader uniform identifier for primary wave length.
const PARAM_WAVE_LENGTH: StringName = &"wave_length"

## Shader uniform identifier for wave phase speed.
const PARAM_WAVE_SPEED: StringName = &"wave_speed"

## Shader uniform identifier for trochoidal wave crest steepness.
const PARAM_WAVE_STEEPNESS: StringName = &"wave_steepness"

## Shader uniform identifier for the 16-slot interactive ripple buffer.
const PARAM_RIPPLES: StringName = &"ripples"

## Shader uniform identifier for interactive ripple displacement height.
const PARAM_RIPPLE_MESH_HEIGHT: StringName = &"ripple_mesh_height"

## Shader uniform identifier for normal map UV tiling scale.
const PARAM_UV_SCALE: StringName = &"uv_scale"

## Shader uniform identifier for micro-normal perturbation strength.
const PARAM_NORMAL_BUMP_STRENGTH: StringName = &"normal_bump_strength"

## Shader uniform identifier for primary normal layer panning velocity.
const PARAM_PAN_SPEED_1: StringName = &"pan_speed_1"

## Shader uniform identifier for secondary normal layer panning velocity.
const PARAM_PAN_SPEED_2: StringName = &"pan_speed_2"

## Shader uniform identifier toggling screen-space reflections.
const PARAM_ENABLE_SSR: StringName = &"enable_ssr"

## Shader uniform identifier for maximum SSR raymarch distance.
const PARAM_SSR_MAX_DISTANCE: StringName = &"ssr_max_distance"

## Shader uniform identifier for screen-space refraction distortion strength.
const PARAM_REFRACTION_STRENGTH: StringName = &"refraction_strength"

## Shader uniform identifier for fallback sky reflection tint.
const PARAM_SKY_REFLECTION_TINT: StringName = &"sky_reflection_tint"

## Shader uniform identifier for base Schlick Fresnel reflectivity.
const PARAM_FRESNEL_BASE: StringName = &"fresnel_base"

## Shader uniform identifier for Schlick Fresnel exponent power.
const PARAM_FRESNEL_POWER: StringName = &"fresnel_power"

## Shader uniform identifier for water surface roughness.
const PARAM_ROUGHNESS: StringName = &"roughness"

## Shader uniform identifier for water specular intensity.
const PARAM_SPECULAR_STRENGTH: StringName = &"specular_strength"

## Shader uniform identifier for water metallic parameter.
const PARAM_METALLIC: StringName = &"metallic"

## Shader uniform identifier for shoreline and crest foam noise texture.
const PARAM_FOAM_NOISE: StringName = &"foam_noise"

## Shader uniform identifier for surface foam albedo color.
const PARAM_FOAM_COLOR: StringName = &"foam_color"

## Shader uniform identifier for shoreline intersection foam width.
const PARAM_FOAM_DISTANCE: StringName = &"foam_distance"

## Shader uniform identifier for wave crest foam height threshold.
const PARAM_CREST_FOAM_THRESHOLD: StringName = &"crest_foam_threshold"

## Fixed capacity of the GPU ripple ring buffer.
const MAX_RIPPLES: int = 16

## Minimum horizontal speed in m/s required for submerged bodies to emit movement ripples.
const MIN_WAKE_SPEED_SQ: float = 0.49

## Minimum time interval in seconds between movement ripples from the same body.
const WAKE_COOLDOWN_SEC: float = 0.16

## Minimum squared horizontal distance in meters before a moving body spawns a new ripple.
const WAKE_MIN_DIST_SQ: float = 0.09

## Normalized propagation direction for wave octave 0 (synced with water_body.gdshader).
const WAVE_DIR_0: Vector2 = Vector2(0.924678, 0.380749)

## Normalized propagation direction for wave octave 1 (synced with water_body.gdshader).
const WAVE_DIR_1: Vector2 = Vector2(-0.451481, 0.892281)

## Normalized propagation direction for wave octave 2 (synced with water_body.gdshader).
const WAVE_DIR_2: Vector2 = Vector2(0.319222, -0.947680)

## Collision mask scanning Layer 2 (Player) and Layer 3 (Interactive).
const SWIM_COLLISION_MASK: int = 6

@export_category("Volume & Geometry")
## Dimensions of the water volume box in meters.
@export var water_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		water_size = Vector3(maxf(value.x, 0.1), maxf(value.y, 0.1), maxf(value.z, 0.1))
		if is_inside_tree():
			_sync_volume_geometry()
			_set_shader_param(PARAM_WATER_SIZE, water_size)

## Subdivision density per meter used to cap reusable unit mesh subdivisions.
@export_range(0.5, 16.0, 0.5) var vertex_density: float = 4.0:
	set(value):
		vertex_density = clampf(value, 0.5, 16.0)
		if is_inside_tree():
			_sync_mesh_subdivisions()

## Renders vertical side walls and bottom of the water box when enabled.
@export var show_side_walls: bool = false:
	set(value):
		show_side_walls = value
		if is_inside_tree():
			_set_shader_param(PARAM_SHOW_SIDE_WALLS, show_side_walls)

## Controls update mode applied to any child [ReflectionProbe] (0=Once, 1=Always).
@export_enum("Once:0", "Always:1") var probe_update_mode: int = 0:
	set(value):
		probe_update_mode = value
		if is_inside_tree():
			_sync_reflection_probe()

@export_category("Wave Simulation")
## Vertical amplitude of primary surface waves in meters.
@export_range(0.0, 5.0, 0.01) var wave_amplitude: float = 0.1:
	set(value):
		wave_amplitude = maxf(value, 0.0)
		if is_inside_tree():
			_set_shader_param(PARAM_WAVE_AMPLITUDE, wave_amplitude)
			_update_culling_bounds()

## Wavelength of primary surface waves in meters.
@export_range(0.25, 100.0, 0.05) var wave_length: float = 4.5:
	set(value):
		wave_length = maxf(value, 0.25)
		if is_inside_tree():
			_set_shader_param(PARAM_WAVE_LENGTH, wave_length)

## Phase propagation speed of primary waves.
@export_range(0.0, 20.0, 0.05) var wave_speed: float = 1.4:
	set(value):
		wave_speed = maxf(value, 0.0)
		if is_inside_tree():
			_set_shader_param(PARAM_WAVE_SPEED, wave_speed)

## Trochoidal crest sharpness factor across the 3-octave wave cascade.
@export_range(0.0, 2.0, 0.01) var wave_steepness: float = 0.35:
	set(value):
		wave_steepness = clampf(value, 0.0, 2.0)
		if is_inside_tree():
			_set_shader_param(PARAM_WAVE_STEEPNESS, wave_steepness)

## Vertical displacement multiplier for dynamic interactive ring ripples.
@export_range(0.0, 2.0, 0.01) var ripple_mesh_height: float = 0.22:
	set(value):
		ripple_mesh_height = maxf(value, 0.0)
		if is_inside_tree():
			_set_shader_param(PARAM_RIPPLE_MESH_HEIGHT, ripple_mesh_height)
			_update_culling_bounds()

@export_category("Optics & Absorption")
## Scatter tint of shallow water regions.
@export var shallow_color: Color = Color(0.22, 0.65, 0.78, 1.0):
	set(value):
		shallow_color = value
		if is_inside_tree():
			_set_shader_param(PARAM_SHALLOW_COLOR, shallow_color)

## Scatter tint of deep murky water regions.
@export var deep_color: Color = Color(0.01, 0.05, 0.16, 1.0):
	set(value):
		deep_color = value
		if is_inside_tree():
			_set_shader_param(PARAM_DEEP_COLOR, deep_color)

## Tint applied to the underwater surface ceiling outside Snell's window.
@export var underwater_ceiling_color: Color = Color(0.0, 0.1, 0.2, 1.0):
	set(value):
		underwater_ceiling_color = value
		if is_inside_tree():
			_set_shader_param(PARAM_UNDERWATER_CEILING_COLOR, underwater_ceiling_color)

## Per-channel RGB Beer-Lambert light absorption coefficients.
@export var absorption_coefficients: Vector3 = Vector3(1.4, 0.42, 0.08):
	set(value):
		absorption_coefficients = value
		if is_inside_tree():
			_set_shader_param(PARAM_ABSORPTION_COEFFS, absorption_coefficients)

## Optical depth normalization distance in meters.
@export_range(0.1, 100.0, 0.1) var depth_distance: float = 4.5:
	set(value):
		depth_distance = maxf(value, 0.1)
		if is_inside_tree():
			_set_shader_param(PARAM_DEPTH_DISTANCE, depth_distance)

## Exponential Beer-Lambert absorption and turbidity multiplier.
@export_range(0.1, 20.0, 0.1) var beers_law: float = 2.2:
	set(value):
		beers_law = maxf(value, 0.1)
		if is_inside_tree():
			_set_shader_param(PARAM_BEERS_LAW, beers_law)

## Non-volumetric underwater depth fog density used when Volumetric Fog is disabled.
@export_range(0.01, 0.5, 0.005) var fallback_fog_density: float = 0.11

@export_category("Reflections & Surface Detail")
## Enables raymarched screen-space reflections on the water surface.
@export var enable_ssr: bool = true:
	set(value):
		enable_ssr = value
		if is_inside_tree():
			_set_shader_param(PARAM_ENABLE_SSR, enable_ssr)

## Maximum view-space raymarch distance for screen-space reflections.
@export_range(0.5, 50.0, 0.1) var ssr_max_distance: float = 4.5:
	set(value):
		ssr_max_distance = maxf(value, 0.5)
		if is_inside_tree():
			_set_shader_param(PARAM_SSR_MAX_DISTANCE, ssr_max_distance)

## Screen-space refraction UV distortion strength.
@export_range(0.0, 0.2, 0.001) var refraction_strength: float = 0.02:
	set(value):
		refraction_strength = clampf(value, 0.0, 0.2)
		if is_inside_tree():
			_set_shader_param(PARAM_REFRACTION_STRENGTH, refraction_strength)

## Sky reflection tint blended via Fresnel reflectivity.
@export var sky_reflection_tint: Color = Color(0.65, 0.82, 1.0, 1.0):
	set(value):
		sky_reflection_tint = value
		if is_inside_tree():
			_set_shader_param(PARAM_SKY_REFLECTION_TINT, sky_reflection_tint)

## Base reflectivity at normal incidence for Schlick Fresnel.
@export_range(0.0, 1.0, 0.01) var fresnel_base: float = 0.12:
	set(value):
		fresnel_base = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_set_shader_param(PARAM_FRESNEL_BASE, fresnel_base)

## Exponential falloff power for Schlick Fresnel reflectivity.
@export_range(0.5, 10.0, 0.1) var fresnel_power: float = 3.5:
	set(value):
		fresnel_power = maxf(value, 0.5)
		if is_inside_tree():
			_set_shader_param(PARAM_FRESNEL_POWER, fresnel_power)

## Micro-surface roughness of the water.
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.03:
	set(value):
		roughness = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_set_shader_param(PARAM_ROUGHNESS, roughness)

## Specular highlight multiplier.
@export_range(0.0, 1.0, 0.01) var specular_strength: float = 0.5:
	set(value):
		specular_strength = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_set_shader_param(PARAM_SPECULAR_STRENGTH, specular_strength)

## Metallic surface reflectance factor.
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.12:
	set(value):
		metallic = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_set_shader_param(PARAM_METALLIC, metallic)

## World-space UV tiling scale for micro-normal perturbation.
@export var uv_scale: Vector2 = Vector2(2.0, 2.0):
	set(value):
		uv_scale = value
		if is_inside_tree():
			_set_shader_param(PARAM_UV_SCALE, uv_scale)

## Intensity of procedural and texture micro-normal slopes.
@export_range(0.0, 8.0, 0.05) var normal_bump_strength: float = 2.0:
	set(value):
		normal_bump_strength = maxf(value, 0.0)
		if is_inside_tree():
			_set_shader_param(PARAM_NORMAL_BUMP_STRENGTH, normal_bump_strength)

## Primary normal pan velocity vector.
@export var pan_speed_1: Vector2 = Vector2(0.1, 0.01):
	set(value):
		pan_speed_1 = value
		if is_inside_tree():
			_set_shader_param(PARAM_PAN_SPEED_1, pan_speed_1)

## Secondary normal pan velocity vector.
@export var pan_speed_2: Vector2 = Vector2(-0.015, 0.025):
	set(value):
		pan_speed_2 = value
		if is_inside_tree():
			_set_shader_param(PARAM_PAN_SPEED_2, pan_speed_2)

@export_category("Foam")
## Seamless noise texture modulating shoreline and crest foam.
@export var foam_noise: Texture2D = null:
	set(value):
		foam_noise = value
		if is_inside_tree():
			_set_shader_param(PARAM_FOAM_NOISE, foam_noise)

## Albedo color and opacity of surface foam.
@export var foam_color: Color = Color(0.92, 0.96, 1.0, 1.0):
	set(value):
		foam_color = value
		if is_inside_tree():
			_set_shader_param(PARAM_FOAM_COLOR, foam_color)

## Shoreline intersection depth threshold in meters for edge foam.
@export_range(0.0, 5.0, 0.01) var foam_distance: float = 0.35:
	set(value):
		foam_distance = maxf(value, 0.0)
		if is_inside_tree():
			_set_shader_param(PARAM_FOAM_DISTANCE, foam_distance)

## Normalized wave crest height threshold for open-water whitecaps.
@export_range(0.0, 2.0, 0.01) var crest_foam_threshold: float = 0.65:
	set(value):
		crest_foam_threshold = maxf(value, 0.0)
		if is_inside_tree():
			_set_shader_param(PARAM_CREST_FOAM_THRESHOLD, crest_foam_threshold)

@export_category("Physics, Buoyancy & Audio")
## Upward buoyant acceleration multiplier applied to submerged rigid bodies.
@export_range(0.1, 10.0, 0.05) var buoyancy_power: float = 1.5

## Linear drag coefficient opposing submerged rigid body velocity.
@export_range(0.0, 10.0, 0.05) var water_drag: float = 1.2

## Additional vertical damping coefficient opposing bobbing oscillation.
@export_range(0.0, 10.0, 0.05) var vertical_drag: float = 2.5

## Angular velocity damping factor applied to submerged rigid bodies.
@export_range(0.0, 10.0, 0.05) var angular_drag: float = 2.0

## Minimum vertical impact speed in m/s required to emit splash events and audio.
@export_range(0.5, 20.0, 0.1) var min_splash_velocity: float = 4.0

## Audio stream played via [AudioPool] upon high-velocity water entry or exit.
@export var splash_sound: AudioStream = null

## Maximum distance from active camera in meters before wave updates are gated.
@export_range(10.0, 500.0, 1.0) var max_simulation_distance: float = 95.0

@export_category("Water Level Control")
## Determines whether water level toggles back and forth or fires only once.
@export var water_level_mode: WaterLevelMode = WaterLevelMode.TOGGLE

## Vertical water level offset in meters relative to baseline (negative = lower, positive = raise).
@export var target_level_delta: float = -20.0

## Duration of water level transition in seconds.
@export_range(0.1, 120.0, 0.1) var level_change_duration: float = 5.0

## Easing curve applied to water level transition.
@export var level_transition_type: Tween.TransitionType = Tween.TRANS_SINE

## Easing direction applied to water level transition.
@export var level_ease_type: Tween.EaseType = Tween.EASE_IN_OUT

## Baseline local Y position recorded at initialization for floor-anchored transitions.
var _default_position_y: float = 0.0

## Baseline vertical water volume height recorded at initialization.
var _default_water_size_y: float = 1.0

## Active [Tween] animating water surface and position transitions.
var _level_tween: Tween = null

## Tracks whether water level is currently transitioning or settled at lowered target.
var _is_water_lowered: bool = false

## Indicates whether a one-shot water level sequence has already fired.
var _has_fired_one_shot: bool = false

## Accumulated simulation time in seconds synchronized between CPU and GPU.
var _water_time: float = 0.0

## Cached [RID] of the active [ShaderMaterial] for low-overhead uniform updates.
var _material_rid: RID = RID()

## Pre-allocated 16-element ring buffer of active ripples `(x, z, spawn_time, amplitude)`.
var _ripples: Array[Vector4] = []

## Next circular write slot index in [member _ripples].
var _ripple_write_index: int = 0

## Simulation timestamp when the longest-lived active ripple expires.
var _active_ripple_expiry: float = 0.0

## Indicates whether the GPU ripple uniform needs a final zeroed flush after expiry.
var _has_active_ripples: bool = false

## Registered [RigidBody3D] instances currently overlapping the water area.
var _floating_bodies: Array[RigidBody3D] = []

## Registered [CharacterBody3D] instances currently overlapping the water area.
var _submerged_characters: Array[CharacterBody3D] = []

## Maps body instance ID to the last [_water_time] a movement ripple was spawned.
var _body_last_ripple_time: Dictionary[int, float] = {}

## Maps body instance ID to last horizontal XZ position movement ripple was spawned.
var _body_last_ripple_pos: Dictionary[int, Vector2] = {}

## Tracks whether active viewport camera is currently submerged below wave surface.
var _is_camera_submerged: bool = false

## Previous frame's global Y coordinate of active camera for surfacing speed calculation.
var _last_camera_y: float = 0.0

## Indicates whether [member _last_camera_y] holds a valid sample.
var _has_last_camera_y: bool = false

## Cached reference to active viewport [Camera3D].
var _cached_camera: Camera3D = null

## Tracks whether fallback non-volumetric environment depth fog is currently active.
var _fallback_fog_active: bool = false

## Cached [Environment] resource modified during fallback underwater fog.
var _cached_env: Environment = null

## Saved [member Environment.fog_enabled] state prior to camera submersion.
var _orig_fog_enabled: bool = false

## Saved [member Environment.fog_light_color] prior to camera submersion.
var _orig_fog_color: Color = Color.BLACK

## Saved [member Environment.fog_density] prior to camera submersion.
var _orig_fog_density: float = 0.01

## Saved [member Environment.fog_sky_affect] prior to camera submersion.
var _orig_fog_sky_affect: float = 1.0

## Child [Area3D] registered in group `water_area` for swim and buoyancy detection.
@onready var _swimmable_area: Area3D = get_node_or_null("%SwimmableArea3D") as Area3D

## Child [CollisionShape3D] defining physical bounds of [member _swimmable_area].
@onready
var _collision_shape: CollisionShape3D = get_node_or_null("%CollisionShape3D") as CollisionShape3D

## Child [ShapeCast3D] positioned at camera to verify spatial overlap with water areas.
@onready
var _camera_shape_cast: ShapeCast3D = get_node_or_null("%CameraPosShapeCast3D") as ShapeCast3D

## Child [FogVolume] providing volumetric underwater scattering when volumetric fog enabled.
@onready var _fog_volume: FogVolume = get_node_or_null("%FogVolume") as FogVolume

## Child [AudioStreamPlayer3D] playing ambient surface water audio.
@onready
var _surface_audio: AudioStreamPlayer3D = get_node_or_null("%SurfaceAudio") as AudioStreamPlayer3D

## Child [AudioStreamPlayer3D] playing muffled underwater loop audio when submerged.
@onready var _underwater_audio: AudioStreamPlayer3D = (
	get_node_or_null("%UnderwaterAudio") as AudioStreamPlayer3D
)


## Initializes ripple buffers, node invariants, signals, and initial shader state.
func _ready() -> void:
	_init_ripple_buffer()
	_cache_material_rid()
	_sync_volume_geometry()
	_sync_all_shader_parameters()
	_sync_reflection_probe()

	_default_position_y = position.y
	_default_water_size_y = water_size.y

	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(true)
		return

	print("WaterBody: Initializing water volume -> ", name)
	assert(is_instance_valid(_swimmable_area), "WaterBody: Missing %SwimmableArea3D child node.")
	assert(is_instance_valid(_collision_shape), "WaterBody: Missing %CollisionShape3D child node.")
	assert(is_instance_valid(_fog_volume), "WaterBody: Missing %FogVolume child node.")
	assert(is_instance_valid(_surface_audio), "WaterBody: Missing %SurfaceAudio child node.")
	assert(is_instance_valid(_underwater_audio), "WaterBody: Missing %UnderwaterAudio child node.")

	if is_instance_valid(_swimmable_area):
		if not _swimmable_area.is_in_group(GROUP_WATER_AREA):
			_swimmable_area.add_to_group(GROUP_WATER_AREA)
		_swimmable_area.collision_mask = SWIM_COLLISION_MASK
		if not _swimmable_area.body_entered.is_connected(_on_swimmable_area_body_entered):
			_swimmable_area.body_entered.connect(_on_swimmable_area_body_entered)
		if not _swimmable_area.body_exited.is_connected(_on_swimmable_area_body_exited):
			_swimmable_area.body_exited.connect(_on_swimmable_area_body_exited)

	if (
		is_instance_valid(Events)
		and not Events.player_camera_registered.is_connected(_on_camera_registered)
	):
		Events.player_camera_registered.connect(_on_camera_registered)

	set_physics_process(false)
	set_process(true)


## Disconnects signals and restores environment fog on tree exit.
func _exit_tree() -> void:
	if _level_tween and _level_tween.is_valid():
		_level_tween.kill()
		_level_tween = null

	if not Engine.is_editor_hint():
		_restore_fallback_environment_fog()
		if (
			is_instance_valid(Events)
			and Events.player_camera_registered.is_connected(_on_camera_registered)
		):
			Events.player_camera_registered.disconnect(_on_camera_registered)


## Advances wave simulation clock and evaluates distance-gated camera submersion.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_water_time += delta
		_set_shader_param(PARAM_WATER_TIME, _water_time)
		return

	var cam: Camera3D = _get_active_camera()
	if is_instance_valid(cam):
		var half_extents: Vector3 = water_size * 0.5
		var max_dist: float = max_simulation_distance + half_extents.length()
		var dist_sq: float = global_position.distance_squared_to(cam.global_position)
		if dist_sq > max_dist * max_dist and not _is_camera_submerged:
			return

	_water_time += delta
	_set_shader_param(PARAM_WATER_TIME, _water_time)

	if _has_active_ripples and _water_time >= _active_ripple_expiry:
		_clear_expired_ripples()

	if is_instance_valid(cam):
		_evaluate_camera_submersion(cam, delta)


## Applies buoyancy forces, drag damping, and wake ripples to bodies inside volume.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return

	if _floating_bodies.is_empty() and _submerged_characters.is_empty():
		set_physics_process(false)
		return

	_process_rigid_bodies_buoyancy(delta)
	_process_character_wakes()


## Supports legacy scene property overrides (`size` and `material` in testbed.tscn).
func _set(property: StringName, value: Variant) -> bool:
	if property == PROP_LEGACY_SIZE and typeof(value) == TYPE_VECTOR3:
		water_size = value
		return true
	if property == PROP_LEGACY_MATERIAL and value is Material:
		material_override = value
		_cache_material_rid()
		_sync_all_shader_parameters()
		return true
	return false


## Retrieves legacy scene property aliases (`size` and `material`).
func _get(property: StringName) -> Variant:
	if property == PROP_LEGACY_SIZE:
		return water_size
	if property == PROP_LEGACY_MATERIAL:
		return material_override
	return null


## Returns exact global Y height of water surface at [param global_pos].
func get_wave_height_at_pos(global_pos: Vector3) -> float:
	var base_y: float = global_position.y + (water_size.y * 0.5)
	var disp: Vector3 = _evaluate_surface_displacement(
		Vector2(global_pos.x, global_pos.z), _water_time
	)
	return base_y + disp.x


## Returns normalized 3D surface normal vector at [param global_pos].
func get_water_surface_normal(global_pos: Vector3) -> Vector3:
	var disp: Vector3 = _evaluate_surface_displacement(
		Vector2(global_pos.x, global_pos.z), _water_time
	)
	return Vector3(-disp.y, 1.0, -disp.z).normalized()


## Spawns a 3D splash sound effect at the water surface via [AudioPool].
func play_splash_sound(impact_pos: Vector3, speed: float) -> void:
	if not is_instance_valid(splash_sound) or not is_instance_valid(AudioPool):
		return

	var surface_y: float = get_wave_height_at_pos(impact_pos)
	var play_pos: Vector3 = Vector3(impact_pos.x, surface_y, impact_pos.z)
	var player_3d: AudioStreamPlayer3D = AudioPool.play_sfx_3d(splash_sound, play_pos, BUS_SFX)
	if is_instance_valid(player_3d):
		var speed_ratio: float = clampf(speed / maxf(min_splash_velocity * 3.0, 1.0), 0.15, 1.5)
		player_3d.volume_db = linear_to_db(speed_ratio)
		player_3d.pitch_scale = clampf(1.15 - (speed_ratio * 0.25), 0.75, 1.25)
		print("WaterBody: Splash sound played at ", play_pos, " (speed=", speed, ")")


## Injects an expanding circular wave into the 16-slot GPU ripple ring buffer.
func spawn_ripple(global_pos: Vector3, impact_strength: float) -> void:
	var clamped_amp: float = clampf(impact_strength, 0.05, 3.0)
	if _ripples.size() != MAX_RIPPLES:
		_init_ripple_buffer()

	_ripples[_ripple_write_index] = Vector4(global_pos.x, global_pos.z, _water_time, clamped_amp)
	_ripple_write_index = (_ripple_write_index + 1) % MAX_RIPPLES

	var max_age: float = 1.6 + clamped_amp * 0.9
	_active_ripple_expiry = maxf(_active_ripple_expiry, _water_time + max_age + 0.1)
	_has_active_ripples = true
	_set_shader_param(PARAM_RIPPLES, _ripples)


## Returns true if active [Camera3D] is inside water bounds and below wave surface.
func should_draw_camera_underwater_effect() -> bool:
	var cam: Camera3D = _get_active_camera()
	if not is_instance_valid(cam):
		return false

	var cam_pos: Vector3 = cam.global_position
	var local_pos: Vector3 = to_local(cam_pos)
	var half_extents: Vector3 = water_size * 0.5

	if absf(local_pos.x) > half_extents.x or absf(local_pos.z) > half_extents.z:
		return false
	if cam_pos.y < global_position.y - half_extents.y:
		return false

	if is_instance_valid(_camera_shape_cast) and _camera_shape_cast.is_inside_tree():
		_camera_shape_cast.global_position = cam_pos
		_camera_shape_cast.force_shapecast_update()
		if _camera_shape_cast.is_colliding():
			var hit_y: float = get_wave_height_at_pos(cam_pos)
			return cam_pos.y < hit_y

	var surface_y: float = get_wave_height_at_pos(cam_pos)
	return cam_pos.y < surface_y


## Energizes water volume via [OutputTransmitter3D], triggering water level change.
func power_on() -> void:
	if water_level_mode == WaterLevelMode.ONE_SHOT and _has_fired_one_shot:
		return
	if water_level_mode == WaterLevelMode.ONE_SHOT:
		_has_fired_one_shot = true
	change_water_level(true)


## De-energizes water volume via [OutputTransmitter3D], restoring baseline level if in toggle mode.
func power_off() -> void:
	if water_level_mode == WaterLevelMode.ONE_SHOT:
		return
	change_water_level(false)


## Toggles water level between baseline and target offset.
func toggle_water_level() -> void:
	if water_level_mode == WaterLevelMode.ONE_SHOT and _has_fired_one_shot:
		return
	if water_level_mode == WaterLevelMode.ONE_SHOT:
		_has_fired_one_shot = true
	change_water_level(not _is_water_lowered)


## Transitions water volume to either lowered target or baseline size and position.
func change_water_level(to_lowered: bool) -> void:
	if Engine.is_editor_hint():
		return

	if _level_tween and _level_tween.is_valid():
		_level_tween.kill()
		_level_tween = null

	_is_water_lowered = to_lowered
	print("WaterBody: Transitioning water level -> to_lowered=", to_lowered)
	water_level_transition_started.emit(_is_water_lowered)

	var target_size_y: float = _default_water_size_y
	var target_pos_y: float = _default_position_y

	if to_lowered:
		target_size_y = maxf(_default_water_size_y + target_level_delta, 0.1)
		var eff_delta: float = target_size_y - _default_water_size_y
		target_pos_y = _default_position_y + (eff_delta * 0.5)

	var total_span: float = maxf(absf(target_level_delta), 0.1)
	var remaining_dist: float = absf(water_size.y - target_size_y)
	var duration_ratio: float = clampf(remaining_dist / total_span, 0.05, 1.0)
	var active_duration: float = maxf(level_change_duration * duration_ratio, 0.05)

	var target_size: Vector3 = Vector3(water_size.x, target_size_y, water_size.z)

	_level_tween = create_tween()
	_level_tween.set_trans(level_transition_type)
	_level_tween.set_ease(level_ease_type)
	_level_tween.tween_property(self, "position:y", target_pos_y, active_duration)
	_level_tween.parallel().tween_property(self, "water_size", target_size, active_duration)
	_level_tween.finished.connect(_on_level_tween_finished.bind(_is_water_lowered))


## Evaluates a single trochoidal wave octave, returning `Vector3(height, dh_dx, dh_dz)`.
func _evaluate_wave_octave(
	world_xz: Vector2,
	dir: Vector2,
	amp: float,
	length_val: float,
	speed_val: float,
	steepness_val: float,
	t: float
) -> Vector3:
	var safe_len: float = maxf(length_val, 0.25)
	var k: float = TAU / safe_len
	var omega: float = speed_val * k
	var theta: float = dir.dot(world_xz) * k + t * omega
	var s1: float = sin(theta)
	var c1: float = cos(theta)
	var s2: float = sin(2.0 * theta)
	var c2: float = cos(2.0 * theta)

	var h: float = amp * (s1 + 0.5 * steepness_val * s2)
	var dtheta: float = amp * k * (c1 + steepness_val * c2)
	return Vector3(h, dir.x * dtheta, dir.y * dtheta)


## Evaluates 3-octave wave cascade and 16-slot ripple ring buffer on CPU.
func _evaluate_surface_displacement(world_xz: Vector2, t: float) -> Vector3:
	var total_h: float = 0.0
	var slope_x: float = 0.0
	var slope_z: float = 0.0

	if wave_amplitude > 0.0001:
		var w0: Vector3 = _evaluate_wave_octave(
			world_xz, WAVE_DIR_0, wave_amplitude, wave_length, wave_speed, wave_steepness * 0.55, t
		)
		var w1: Vector3 = _evaluate_wave_octave(
			world_xz,
			WAVE_DIR_1,
			wave_amplitude * 0.42,
			wave_length * 0.43,
			wave_speed * 1.28,
			wave_steepness * 0.30,
			t
		)
		var w2: Vector3 = _evaluate_wave_octave(
			world_xz,
			WAVE_DIR_2,
			wave_amplitude * 0.18,
			wave_length * 0.19,
			wave_speed * 1.65,
			wave_steepness * 0.15,
			t
		)
		total_h += w0.x + w1.x + w2.x
		slope_x += w0.y + w1.y + w2.y
		slope_z += w0.z + w1.z + w2.z

	if _has_active_ripples and ripple_mesh_height > 0.0001:
		var count: int = _ripples.size()
		for i: int in range(count):
			var r: Vector4 = _ripples[i]
			var amp: float = r.w
			if amp <= 0.0001:
				continue
			var age: float = t - r.z
			var scale_f: float = clampf(amp, 0.05, 3.0)
			var max_age: float = 1.6 + scale_f * 0.9
			if age <= 0.0 or age >= max_age:
				continue

			var dx: float = world_xz.x - r.x
			var dz: float = world_xz.y - r.y
			var dist: float = sqrt(dx * dx + dz * dz)
			var exp_speed: float = 1.15 + scale_f * 0.65
			var radius: float = age * exp_speed
			var sigma: float = 0.14 + scale_f * 0.28
			var delta_r: float = dist - radius

			if absf(delta_r) > sigma * 3.5:
				continue

			var inv_two_sigma_sq: float = 1.0 / (2.0 * sigma * sigma)
			var env: float = exp(-(delta_r * delta_r) * inv_two_sigma_sq)
			var life_ratio: float = 1.0 - (age / max_age)
			var decay: float = exp(-age * (1.8 / (0.6 + scale_f * 0.4))) * life_ratio
			var k_r: float = 22.0 / (0.35 + scale_f * 0.65)
			var phase: float = delta_r * k_r - age * 4.0

			var eff_amp: float = minf(amp, 2.0) * ripple_mesh_height * env * decay
			var s_p: float = sin(phase)
			var c_p: float = cos(phase)
			total_h += s_p * eff_amp

			if dist > 0.0001:
				var d_dr: float = eff_amp * (k_r * c_p - s_p * delta_r * 2.0 * inv_two_sigma_sq)
				slope_x += (dx / dist) * d_dr
				slope_z += (dz / dist) * d_dr

	return Vector3(total_h, slope_x, slope_z)


## Pre-allocates the 16-element ripple array with zeroed [Vector4] values.
func _init_ripple_buffer() -> void:
	_ripples.resize(MAX_RIPPLES)
	for i: int in range(MAX_RIPPLES):
		_ripples[i] = Vector4.ZERO
	_ripple_write_index = 0
	_has_active_ripples = false


## Clears expired ripples and uploads a single zeroed array to the shader.
func _clear_expired_ripples() -> void:
	for i: int in range(MAX_RIPPLES):
		_ripples[i] = Vector4.ZERO
	_has_active_ripples = false
	_set_shader_param(PARAM_RIPPLES, _ripples)


## Caches the [RID] of active [ShaderMaterial] on this mesh instance.
func _cache_material_rid() -> void:
	var mat: ShaderMaterial = _get_shader_material()
	_material_rid = mat.get_rid() if is_instance_valid(mat) else RID()


## Resolves active [ShaderMaterial] from `material_override` or surface slot 0.
func _get_shader_material() -> ShaderMaterial:
	if material_override is ShaderMaterial:
		return material_override as ShaderMaterial
	if is_instance_valid(mesh) and mesh.get_surface_count() > 0:
		var surf_mat: Material = get_active_material(0)
		if surf_mat is ShaderMaterial:
			return surf_mat as ShaderMaterial
	return null


## Sets a shader parameter directly through [RenderingServer], converting resources to RIDs.
func _set_shader_param(param: StringName, value: Variant) -> void:
	if not _material_rid.is_valid():
		_cache_material_rid()
	if _material_rid.is_valid():
		var param_val: Variant = value
		if value is Resource:
			var res: Resource = value
			param_val = res.get_rid() if is_instance_valid(res) else RID()
		RenderingServer.material_set_param(_material_rid, param, param_val)


## Pushes all exported optical and wave parameters to the shader once on initialization.
func _sync_all_shader_parameters() -> void:
	_cache_material_rid()
	if not _material_rid.is_valid():
		return
	_set_shader_param(PARAM_WATER_TIME, _water_time)
	_set_shader_param(PARAM_WATER_SIZE, water_size)
	_set_shader_param(PARAM_SHOW_SIDE_WALLS, show_side_walls)
	_set_shader_param(PARAM_SHALLOW_COLOR, shallow_color)
	_set_shader_param(PARAM_DEEP_COLOR, deep_color)
	_set_shader_param(PARAM_UNDERWATER_CEILING_COLOR, underwater_ceiling_color)
	_set_shader_param(PARAM_ABSORPTION_COEFFS, absorption_coefficients)
	_set_shader_param(PARAM_DEPTH_DISTANCE, depth_distance)
	_set_shader_param(PARAM_BEERS_LAW, beers_law)
	_set_shader_param(PARAM_WAVE_AMPLITUDE, wave_amplitude)
	_set_shader_param(PARAM_WAVE_LENGTH, wave_length)
	_set_shader_param(PARAM_WAVE_SPEED, wave_speed)
	_set_shader_param(PARAM_WAVE_STEEPNESS, wave_steepness)
	_set_shader_param(PARAM_RIPPLES, _ripples)
	_set_shader_param(PARAM_RIPPLE_MESH_HEIGHT, ripple_mesh_height)
	_set_shader_param(PARAM_UV_SCALE, uv_scale)
	_set_shader_param(PARAM_NORMAL_BUMP_STRENGTH, normal_bump_strength)
	_set_shader_param(PARAM_PAN_SPEED_1, pan_speed_1)
	_set_shader_param(PARAM_PAN_SPEED_2, pan_speed_2)
	_set_shader_param(PARAM_ENABLE_SSR, enable_ssr)
	_set_shader_param(PARAM_SSR_MAX_DISTANCE, ssr_max_distance)
	_set_shader_param(PARAM_REFRACTION_STRENGTH, refraction_strength)
	_set_shader_param(PARAM_SKY_REFLECTION_TINT, sky_reflection_tint)
	_set_shader_param(PARAM_FRESNEL_BASE, fresnel_base)
	_set_shader_param(PARAM_FRESNEL_POWER, fresnel_power)
	_set_shader_param(PARAM_ROUGHNESS, roughness)
	_set_shader_param(PARAM_SPECULAR_STRENGTH, specular_strength)
	_set_shader_param(PARAM_METALLIC, metallic)
	_set_shader_param(PARAM_FOAM_COLOR, foam_color)
	_set_shader_param(PARAM_FOAM_DISTANCE, foam_distance)
	_set_shader_param(PARAM_CREST_FOAM_THRESHOLD, crest_foam_threshold)
	if is_instance_valid(foam_noise):
		_set_shader_param(PARAM_FOAM_NOISE, foam_noise)


## Synchronizes collision shape, fog volume, unit BoxMesh, and custom AABB with `water_size`.
func _sync_volume_geometry() -> void:
	_sync_mesh_subdivisions()
	_update_culling_bounds()

	var col_node: CollisionShape3D = (
		(
			_collision_shape
			if is_instance_valid(_collision_shape)
			else get_node_or_null("%CollisionShape3D")
		)
		as CollisionShape3D
	)
	if is_instance_valid(col_node) and col_node.shape is BoxShape3D:
		var box_shape: BoxShape3D = col_node.shape as BoxShape3D
		if box_shape.size != water_size:
			box_shape.set_deferred(&"size", water_size)

	var fog_node: FogVolume = (
		_fog_volume if is_instance_valid(_fog_volume) else get_node_or_null("%FogVolume")
		as FogVolume
	)
	if is_instance_valid(fog_node):
		fog_node.size = water_size


## Configures the unit [BoxMesh] with capped subdivisions to avoid 256x256 CPU stalls.
func _sync_mesh_subdivisions() -> void:
	if not (mesh is BoxMesh):
		var new_box: BoxMesh = BoxMesh.new()
		new_box.size = Vector3.ONE
		mesh = new_box

	var box_mesh: BoxMesh = mesh as BoxMesh
	if box_mesh.size != Vector3.ONE:
		box_mesh.size = Vector3.ONE

	var target_sub_w: int = clampi(int(roundf(water_size.x * vertex_density * 0.5)), 8, 64)
	var target_sub_d: int = clampi(int(roundf(water_size.z * vertex_density * 0.5)), 8, 64)

	if box_mesh.subdivide_width != target_sub_w:
		box_mesh.subdivide_width = target_sub_w
	if box_mesh.subdivide_depth != target_sub_d:
		box_mesh.subdivide_depth = target_sub_d
	if box_mesh.subdivide_height != 0:
		box_mesh.subdivide_height = 0


## Updates `custom_aabb` to encompass the scaled `water_size` and maximum wave crest height.
func _update_culling_bounds() -> void:
	var vertical_pad: float = (wave_amplitude * 2.0) + (ripple_mesh_height * 2.0) + 0.5
	var aabb_size: Vector3 = water_size + Vector3(0.5, vertical_pad * 2.0, 0.5)
	custom_aabb = AABB(-aabb_size * 0.5, aabb_size)


## Applies [member probe_update_mode] to any child [ReflectionProbe] attached to the water body.
func _sync_reflection_probe() -> void:
	for child: Node in get_children():
		if child is ReflectionProbe:
			var probe: ReflectionProbe = child as ReflectionProbe
			probe.update_mode = (
				ReflectionProbe.UPDATE_ALWAYS
				if probe_update_mode == 1
				else ReflectionProbe.UPDATE_ONCE
			)


## Handles bodies entering `%SwimmableArea3D`, routing swim hooks and registering buoyancy.
func _on_swimmable_area_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	var vertical_speed: float = _get_body_vertical_speed(body)
	if vertical_speed >= min_splash_velocity:
		splashed.emit(body.global_position, vertical_speed)
		play_splash_sound(body.global_position, vertical_speed)
		spawn_ripple(body.global_position, clampf(vertical_speed * 0.25, 0.4, 2.5))
	else:
		spawn_ripple(body.global_position, 0.35)

	if body is CharacterBody3D:
		var char_body: CharacterBody3D = body as CharacterBody3D
		if not _submerged_characters.has(char_body):
			_submerged_characters.append(char_body)
		_notify_actor_water_transition(char_body, true)
		print("WaterBody: CharacterBody3D entered water -> ", char_body.name)
	elif body is RigidBody3D:
		var rigid_body: RigidBody3D = body as RigidBody3D
		if not _floating_bodies.has(rigid_body):
			_floating_bodies.append(rigid_body)
		if PROP_CURRENT_WATER_NODE in rigid_body:
			rigid_body.set(PROP_CURRENT_WATER_NODE, self)
		if PROP_IS_IN_WATER in rigid_body:
			rigid_body.set(PROP_IS_IN_WATER, true)
		if rigid_body.has_method(METHOD_ENTER_WATER):
			rigid_body.call(METHOD_ENTER_WATER, self)
		print("WaterBody: RigidBody3D entered water -> ", rigid_body.name)

	if not _floating_bodies.is_empty() or not _submerged_characters.is_empty():
		set_physics_process(true)


## Handles bodies exiting `%SwimmableArea3D`, cleaning up state and emitting splash events.
func _on_swimmable_area_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	var instance_id: int = body.get_instance_id()
	_body_last_ripple_time.erase(instance_id)
	_body_last_ripple_pos.erase(instance_id)

	var vertical_speed: float = _get_body_vertical_speed(body)
	if vertical_speed >= min_splash_velocity:
		splashed.emit(body.global_position, vertical_speed)
		play_splash_sound(body.global_position, vertical_speed)
		spawn_ripple(body.global_position, clampf(vertical_speed * 0.2, 0.35, 2.0))

	if body is CharacterBody3D:
		var char_body: CharacterBody3D = body as CharacterBody3D
		_submerged_characters.erase(char_body)
		_notify_actor_water_transition(char_body, false)
		print("WaterBody: CharacterBody3D exited water -> ", char_body.name)
	elif body is RigidBody3D:
		var rigid_body: RigidBody3D = body as RigidBody3D
		_floating_bodies.erase(rigid_body)
		if (
			PROP_CURRENT_WATER_NODE in rigid_body
			and rigid_body.get(PROP_CURRENT_WATER_NODE) == self
		):
			rigid_body.set(PROP_CURRENT_WATER_NODE, null)
		if PROP_IS_IN_WATER in rigid_body:
			rigid_body.set(PROP_IS_IN_WATER, false)
		if rigid_body.has_method(METHOD_EXIT_WATER):
			rigid_body.call(METHOD_EXIT_WATER, self)
		print("WaterBody: RigidBody3D exited water -> ", rigid_body.name)

	if _floating_bodies.is_empty() and _submerged_characters.is_empty():
		set_physics_process(false)


## Invokes `enter_water(self)` or `exit_water(self)` on a character or its environment component.
func _notify_actor_water_transition(actor: CharacterBody3D, is_entering: bool) -> void:
	var method_name: StringName = METHOD_ENTER_WATER if is_entering else METHOD_EXIT_WATER
	if actor.has_method(method_name):
		actor.call(method_name, self)
		return

	if PROP_ENV_COMPONENT in actor:
		var env_val: Variant = actor.get(PROP_ENV_COMPONENT)
		if env_val is Node:
			var env_node: Node = env_val
			if is_instance_valid(env_node) and env_node.has_method(method_name):
				env_node.call(method_name, self)


## Extracts the absolute vertical speed of a [Node3D] (`CharacterBody3D` or `RigidBody3D`).
func _get_body_vertical_speed(body: Node3D) -> float:
	if body is CharacterBody3D:
		return absf((body as CharacterBody3D).velocity.y)
	if body is RigidBody3D:
		return absf((body as RigidBody3D).linear_velocity.y)
	return 0.0


## Applies Spec §4 buoyancy forces and drag to registered [RigidBody3D] instances.
func _process_rigid_bodies_buoyancy(delta: float) -> void:
	var idx: int = _floating_bodies.size() - 1
	while idx >= 0:
		var body: RigidBody3D = _floating_bodies[idx]
		if not is_instance_valid(body) or not body.is_inside_tree():
			_floating_bodies.remove_at(idx)
			idx -= 1
			continue

		var body_pos: Vector3 = body.global_position
		var surface_y: float = get_wave_height_at_pos(body_pos)
		var depth: float = surface_y - body_pos.y

		if depth > 0.0:
			if not _has_custom_multi_probe_buoyancy(body):
				var submersion_ratio: float = clampf(depth / 1.2, 0.0, 1.5)
				var a_up: float = 9.8 * buoyancy_power * submersion_ratio
				var vel: Vector3 = body.linear_velocity
				var f_up: Vector3 = Vector3(0.0, a_up, 0.0)
				var f_drag: Vector3 = -vel * water_drag
				var f_vert: Vector3 = Vector3(0.0, -vel.y * vertical_drag, 0.0)
				var net_force: Vector3 = (f_up + f_drag + f_vert) * body.mass
				body.apply_central_force(net_force)

				var ang_damp: float = 1.0 - clampf(angular_drag * delta, 0.0, 0.9)
				body.angular_velocity *= ang_damp

			_try_emit_movement_ripple(body.get_instance_id(), body_pos, body.linear_velocity)

		idx -= 1


## Checks if a [RigidBody3D] runs its own multi-probe buoyancy (such as [PickableObject]).
func _has_custom_multi_probe_buoyancy(body: RigidBody3D) -> bool:
	if PROP_PROBES in body and PROP_IS_IN_WATER in body:
		var probes_val: Variant = body.get(PROP_PROBES)
		if probes_val is Array:
			var probes_arr: Array = probes_val
			return not probes_arr.is_empty()
	return false


## Evaluates submerged [CharacterBody3D] movement and spawns concentric wake ripples.
func _process_character_wakes() -> void:
	var idx: int = _submerged_characters.size() - 1
	while idx >= 0:
		var char_body: CharacterBody3D = _submerged_characters[idx]
		if not is_instance_valid(char_body) or not char_body.is_inside_tree():
			_submerged_characters.remove_at(idx)
			idx -= 1
			continue

		var char_pos: Vector3 = char_body.global_position
		var surface_y: float = get_wave_height_at_pos(char_pos)
		if char_pos.y <= surface_y + 0.5:
			_try_emit_movement_ripple(char_body.get_instance_id(), char_pos, char_body.velocity)

		idx -= 1


## Emits a movement wake ripple if horizontal speed >= 0.7 m/s, cooldown >= 0.16s,
## and delta >= 0.3m.
func _try_emit_movement_ripple(instance_id: int, world_pos: Vector3, velocity: Vector3) -> void:
	var horiz_speed_sq: float = velocity.x * velocity.x + velocity.z * velocity.z
	if horiz_speed_sq < MIN_WAKE_SPEED_SQ:
		return

	var last_time: float = _body_last_ripple_time.get(instance_id, -999.0)
	if (_water_time - last_time) < WAKE_COOLDOWN_SEC:
		return

	var current_xz: Vector2 = Vector2(world_pos.x, world_pos.z)
	if _body_last_ripple_pos.has(instance_id):
		var prev_xz: Vector2 = _body_last_ripple_pos[instance_id]
		if current_xz.distance_squared_to(prev_xz) < WAKE_MIN_DIST_SQ:
			return

	_body_last_ripple_time[instance_id] = _water_time
	_body_last_ripple_pos[instance_id] = current_xz

	var horiz_speed: float = sqrt(horiz_speed_sq)
	var wake_strength: float = clampf(horiz_speed * 0.12, 0.12, 0.65)
	spawn_ripple(world_pos, wake_strength)


## Updates cached camera reference when notified via [signal Events.player_camera_registered].
func _on_camera_registered(camera: Camera3D) -> void:
	_cached_camera = camera


## Retrieves active viewport [Camera3D], refreshing cached reference if invalidated.
func _get_active_camera() -> Camera3D:
	if is_instance_valid(_cached_camera) and _cached_camera.is_inside_tree():
		return _cached_camera
	var vp: Viewport = get_viewport()
	_cached_camera = vp.get_camera_3d() if is_instance_valid(vp) else null
	return _cached_camera


## Evaluates whether active camera crossed water surface and triggers audio/VFX transitions.
func _evaluate_camera_submersion(cam: Camera3D, delta: float) -> void:
	var cam_y: float = cam.global_position.y
	var cam_vert_speed: float = (
		absf(cam_y - _last_camera_y) / maxf(delta, 0.0001) if _has_last_camera_y else 0.0
	)
	_last_camera_y = cam_y
	_has_last_camera_y = true

	var now_submerged: bool = should_draw_camera_underwater_effect()
	if now_submerged == _is_camera_submerged:
		return

	_is_camera_submerged = now_submerged
	if _is_camera_submerged:
		_handle_camera_submerged()
	else:
		_handle_camera_surfaced(cam.global_position, cam_vert_speed)


## Orchestrates audio, fog volume, fallback depth fog, and screen VFX on camera submersion.
func _handle_camera_submerged() -> void:
	print("WaterBody: Camera submerged below surface.")
	if is_instance_valid(Events):
		Events.waterfall_vfx_toggled.emit(false, 0.0, 1.5)
		Events.underwater_vfx_toggled.emit(true, 0.85, 0.0, 0.0)

	if is_instance_valid(_surface_audio):
		_surface_audio.stream_paused = true
	if is_instance_valid(_underwater_audio):
		_underwater_audio.stream_paused = false
		if not _underwater_audio.playing:
			_underwater_audio.play()

	_update_fog_volume_submersion(true)
	_apply_fallback_environment_fog()


## Orchestrates audio, splash audio, and triggers the surfacing water sheet meniscus wipe.
func _handle_camera_surfaced(cam_pos: Vector3, vertical_speed: float) -> void:
	print("WaterBody: Camera surfaced from water (speed=", vertical_speed, ").")
	if is_instance_valid(_underwater_audio):
		_underwater_audio.stream_paused = true
	if is_instance_valid(_surface_audio):
		_surface_audio.stream_paused = false
		if not _surface_audio.playing and is_instance_valid(_surface_audio.stream):
			_surface_audio.play()

	_update_fog_volume_submersion(false)
	_restore_fallback_environment_fog()

	if vertical_speed >= min_splash_velocity:
		play_splash_sound(cam_pos, vertical_speed)
		spawn_ripple(cam_pos, clampf(vertical_speed * 0.2, 0.35, 1.5))

	if is_instance_valid(Events):
		Events.underwater_vfx_toggled.emit(false, 0.0, 0.0, 1.5)
		Events.water_sheet_wipe_requested.emit(1.2)


## Updates `%FogVolume` density and edge fade on camera submersion state changes.
func _update_fog_volume_submersion(is_submerged: bool) -> void:
	if not is_instance_valid(_fog_volume):
		return
	if _fog_volume.material is ShaderMaterial:
		var fog_mat: ShaderMaterial = _fog_volume.material as ShaderMaterial
		fog_mat.set_shader_parameter(&"edge_fade", 0.05 if is_submerged else 0.15)
	elif _fog_volume.material is FogMaterial:
		var fmat: FogMaterial = _fog_volume.material as FogMaterial
		fmat.edge_fade = 0.05 if is_submerged else 0.2


## Enables murky non-volumetric depth fog on the active [Environment] when volumetric fog is off.
func _apply_fallback_environment_fog() -> void:
	var vp: Viewport = get_viewport()
	if not is_instance_valid(vp) or not is_instance_valid(vp.world_3d):
		return
	var env: Environment = vp.world_3d.environment
	if not is_instance_valid(env):
		return

	if not env.volumetric_fog_enabled and not _fallback_fog_active:
		_cached_env = env
		_orig_fog_enabled = env.fog_enabled
		_orig_fog_color = env.fog_light_color
		_orig_fog_density = env.fog_density
		_orig_fog_sky_affect = env.fog_sky_affect

		var murk_col: Color = deep_color.lerp(shallow_color, 0.22)
		env.fog_enabled = true
		env.fog_light_color = Color(murk_col.r, murk_col.g, murk_col.b, 1.0)
		env.fog_density = fallback_fog_density
		env.fog_sky_affect = 1.0
		_fallback_fog_active = true


## Restores original [Environment] depth fog properties when surfacing or exiting tree.
func _restore_fallback_environment_fog() -> void:
	if not _fallback_fog_active:
		return
	if is_instance_valid(_cached_env):
		_cached_env.fog_enabled = _orig_fog_enabled
		_cached_env.fog_light_color = _orig_fog_color
		_cached_env.fog_density = _orig_fog_density
		_cached_env.fog_sky_affect = _orig_fog_sky_affect
	_cached_env = null
	_fallback_fog_active = false


## Emits completion signal and cleans up active tween reference.
func _on_level_tween_finished(is_lowered: bool) -> void:
	_level_tween = null
	water_level_transition_finished.emit(is_lowered)
	print("WaterBody: Water level transition complete -> is_lowered=", is_lowered)
