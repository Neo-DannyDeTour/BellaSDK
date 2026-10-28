@tool
## 3D emissive wall projecting an animated liquid ribbon spatial shader and dynamic shadow light.
class_name RibbonWall
extends Node3D

## Emitted when ribbon gradient colors are updated.
signal colors_changed(color_a: Color, color_b: Color)

## Shader uniform name for background base color.
const PARAM_BASE_COLOR: StringName = &"base_color"
## Shader uniform name for primary gradient color.
const PARAM_COLOR_A: StringName = &"ribbon_color_a"
## Shader uniform name for secondary gradient color.
const PARAM_COLOR_B: StringName = &"ribbon_color_b"
## Shader uniform name for emission intensity multiplier.
const PARAM_EMISSION: StringName = &"emission_energy"
## Shader uniform name for stripe density zoom.
const PARAM_ZOOM: StringName = &"zoom"
## Shader uniform name for vertical wave cropping.
const PARAM_WAVE_CROP: StringName = &"wave_crop"
## Shader uniform name for wave brightness.
const PARAM_BRIGHTNESS: StringName = &"brightness"
## Shader uniform name for animation flow speed.
const PARAM_SPEED: StringName = &"speed"
## Shader uniform name for domain-warping iteration count.
const PARAM_ITERATIONS: StringName = &"iterations"
## Shader uniform name for initial wave frequency.
const PARAM_FRQ_START: StringName = &"frq_start"
## Shader uniform name for per-iteration frequency multiplier.
const PARAM_FRQ_COEF: StringName = &"frq_coef"
## Shader uniform name for alpha cutout threshold.
const PARAM_ALPHA_THRESHOLD: StringName = &"alpha_threshold"
## Shader uniform name for mesh width-to-height aspect ratio.
const PARAM_ASPECT_RATIO: StringName = &"aspect_ratio"

@export_group("Wall Dimensions")

## Dimensions of the wall mesh and collision box in meters.
@export var wall_size: Vector2 = Vector2(6.0, 3.0):
	set(value):
		wall_size = Vector2(maxf(value.x, 0.1), maxf(value.y, 0.1))
		_update_geometry_and_light_rig()

## Thickness depth of the wall collision box in meters.
@export var wall_depth: float = 0.2:
	set(value):
		wall_depth = maxf(value, 0.05)
		_update_geometry_and_light_rig()

@export_group("Lighting & Emission")

## Emissive energy multiplier driving shader glow and dynamic OmniLight3D intensity.
@export_range(0.0, 16.0, 0.1) var emission_energy: float = 3.0:
	set(value):
		emission_energy = value
		_set_shader_param(PARAM_EMISSION, emission_energy)
		_update_light_static_params()

@export_group("Ribbon Palette")

## Background tone underlying the liquid ribbon effect.
@export var base_color: Color = Color(0.05, 0.05, 0.05, 1.0):
	set(value):
		base_color = value
		_set_shader_param(PARAM_BASE_COLOR, base_color)

## First gradient stop color for the flowing ribbon.
@export var ribbon_color_a: Color = Color(0.2, 0.6, 1.0, 1.0):
	set(value):
		ribbon_color_a = value
		_set_shader_param(PARAM_COLOR_A, ribbon_color_a)
		colors_changed.emit(ribbon_color_a, ribbon_color_b)

## Second gradient stop color for the flowing ribbon.
@export var ribbon_color_b: Color = Color(1.0, 0.3, 0.6, 1.0):
	set(value):
		ribbon_color_b = value
		_set_shader_param(PARAM_COLOR_B, ribbon_color_b)
		colors_changed.emit(ribbon_color_a, ribbon_color_b)

@export_group("Shader Dynamics")

## Density factor of internal ribbon stripes.
@export_range(1.0, 200.0, 0.1) var zoom: float = 20.0:
	set(value):
		zoom = value
		_set_shader_param(PARAM_ZOOM, zoom)

## Vertical cropping limit defining ribbon band thickness.
@export_range(0.1, 1.0, 0.01) var wave_crop: float = 0.8:
	set(value):
		wave_crop = maxf(value, 0.1)
		_set_shader_param(PARAM_WAVE_CROP, wave_crop)

## Global brightness applied to ribbon soft limits.
@export_range(0.1, 3.0, 0.01) var brightness: float = 1.0:
	set(value):
		brightness = value
		_set_shader_param(PARAM_BRIGHTNESS, brightness)

## Flow rate multiplier of the ribbon distortion over time.
@export_range(0.0, 10.0, 0.01) var speed: float = 1.0:
	set(value):
		speed = value
		if _is_simulating:
			_set_shader_param(PARAM_SPEED, speed)

## Iteration depth for domain-warping waves.
@export_range(1, 30) var iterations: int = 5:
	set(value):
		iterations = value
		_set_shader_param(PARAM_ITERATIONS, iterations)

## Base frequency start value for wave iterations.
@export_range(0.1, 50.0, 0.01) var frq_start: float = 20.0:
	set(value):
		frq_start = value
		_set_shader_param(PARAM_FRQ_START, frq_start)

## Multiplier applied to frequency with every iteration step.
@export_range(0.1, 2.0, 0.01) var frq_coef: float = 1.0:
	set(value):
		frq_coef = value
		_set_shader_param(PARAM_FRQ_COEF, frq_coef)

## Alpha cutoff threshold for dark areas to produce transparency.
@export_range(0.0, 1.0, 0.01) var alpha_threshold: float = 0.0:
	set(value):
		alpha_threshold = value
		_set_shader_param(PARAM_ALPHA_THRESHOLD, alpha_threshold)

## Maximum distance from camera in meters to allow shader animation and dynamic light updates.
@export var max_render_distance: float = 35.0:
	set(value):
		max_render_distance = maxf(value, 1.0)
		_max_render_distance_sq = max_render_distance * max_render_distance
		_update_light_static_params()

## Cached squared maximum render distance avoiding runtime sqrt calls.
var _max_render_distance_sq: float = 1225.0

## Frustum visibility notifier gating updates at runtime.
var _visibility_notifier: VisibleOnScreenNotifier3D = null

## Tracks if ribbon wall is currently inside camera frustum.
var _is_on_screen: bool = true

## Tracks whether shader animation and dynamic light are actively running.
var _is_simulating: bool = true

## Accumulated phase time for deterministic CPU light modulation.
var _light_phase: float = 0.0

## Visual mesh instance used for the wall surface.
@onready var _wall_mesh: MeshInstance3D = $WallMesh

## Collision shape attached to the wall static body.
@onready var _collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D

## Dynamic omni light casting shifting ribbon shadows in dark environments.
@onready var _room_light: OmniLight3D = $RoomLight


## Validates nodes, configures frustum culling, and flushes instance uniforms.
func _ready() -> void:
	print("RibbonWall: Ready -> ", name)
	_ensure_nodes()
	assert(is_instance_valid(_wall_mesh), "RibbonWall requires child WallMesh.")
	assert(is_instance_valid(_collision_shape), "RibbonWall requires CollisionShape3D.")
	assert(is_instance_valid(_room_light), "RibbonWall requires child RoomLight.")

	_max_render_distance_sq = max_render_distance * max_render_distance
	_update_geometry_and_light_rig()
	_sync_all_shader_params()

	if Engine.is_editor_hint():
		_is_on_screen = true
		_set_simulation_active(true)
		set_process(true)
	else:
		_visibility_notifier = VisibleOnScreenNotifier3D.new()
		_visibility_notifier.name = "RibbonVisibilityNotifier"
		add_child(_visibility_notifier)
		_update_notifier_aabb()
		_visibility_notifier.screen_entered.connect(_on_screen_entered)
		_visibility_notifier.screen_exited.connect(_on_screen_exited)
		_is_on_screen = _visibility_notifier.is_on_screen()
		set_process(_is_on_screen)
		_evaluate_distance_gating()


## Modulates dynamic shadow light and checks runtime distance culling.
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		_evaluate_distance_gating()
		if not _is_simulating:
			return

	_update_dynamic_light(delta)


## Dynamically sets both ribbon colors and emits [signal colors_changed].
func set_ribbon_colors(color_a: Color, color_b: Color) -> void:
	print("RibbonWall: Updating colors to ", color_a, " and ", color_b)
	ribbon_color_a = color_a
	ribbon_color_b = color_b


## Enables distance checking and light updates when entering the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	if not Engine.is_editor_hint():
		set_process(true)
		_evaluate_distance_gating()


## Freezes shader animation and hides dynamic light when leaving the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	if not Engine.is_editor_hint():
		set_process(false)
		_set_simulation_active(false)


## Checks squared camera distance to toggle shader movement and shadow light.
func _evaluate_distance_gating() -> void:
	if not _is_on_screen or not is_inside_tree():
		_set_simulation_active(false)
		return

	var cam: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(cam):
		_set_simulation_active(false)
		return

	var dist_sq: float = global_position.distance_squared_to(cam.global_position)
	_set_simulation_active(dist_sq <= _max_render_distance_sq)


## Toggles shader speed instance parameter and RoomLight visibility on state transition.
func _set_simulation_active(active: bool) -> void:
	if _is_simulating == active:
		return
	_is_simulating = active
	print("RibbonWall: Simulation active -> ", _is_simulating, " on ", name)
	_set_shader_param(PARAM_SPEED, speed if _is_simulating else 0.0)
	if is_instance_valid(_room_light):
		_room_light.visible = _is_simulating and emission_energy > 0.01


## Drives RoomLight color, energy, and position drift to cast shifting shadows.
func _update_dynamic_light(delta: float) -> void:
	if not is_instance_valid(_room_light) or emission_energy <= 0.01:
		return

	_light_phase += delta * speed
	var wave_x: float = sin(_light_phase * 1.3)
	var wave_y: float = cos(_light_phase * 1.9)
	var color_mix: float = wave_x * 0.5 + 0.5
	var pulse: float = 0.75 + 0.25 * sin(_light_phase * 2.7)

	_room_light.light_color = ribbon_color_a.lerp(ribbon_color_b, color_mix)
	_room_light.light_energy = emission_energy * brightness * wave_crop * pulse * 0.5

	var z_offset: float = wall_depth * 0.5 + 0.4
	_room_light.position = Vector3(
		wave_x * wall_size.x * 0.25, wave_y * wall_size.y * 0.15, z_offset
	)


## Resolves child node references safely during @tool setter calls before _ready.
func _ensure_nodes() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_wall_mesh):
		_wall_mesh = get_node_or_null("WallMesh") as MeshInstance3D
	if not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(_room_light):
		_room_light = get_node_or_null("RoomLight") as OmniLight3D


## Resizes mesh, collision box, visibility AABB, and light attenuation range.
func _update_geometry_and_light_rig() -> void:
	if not is_inside_tree():
		return
	_ensure_nodes()

	if is_instance_valid(_wall_mesh):
		_wall_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_wall_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _wall_mesh.mesh is QuadMesh:
			# Share base material across instances; duplicate mesh only if size differs.
			var quad: QuadMesh = _wall_mesh.mesh as QuadMesh
			if quad.size != wall_size:
				quad.size = wall_size
		elif _wall_mesh.mesh is BoxMesh:
			var box_mesh: BoxMesh = _wall_mesh.mesh as BoxMesh
			box_mesh.size = Vector3(wall_size.x, wall_size.y, wall_depth)

		var aspect: float = wall_size.x / maxf(wall_size.y, 0.01)
		_set_shader_param(PARAM_ASPECT_RATIO, aspect)

	if is_instance_valid(_collision_shape) and _collision_shape.shape is BoxShape3D:
		var box_shape: BoxShape3D = _collision_shape.shape as BoxShape3D
		box_shape.size = Vector3(wall_size.x, wall_size.y, wall_depth)

	_update_notifier_aabb()
	_update_light_static_params()


## Updates the VisibleOnScreenNotifier3D bounding box to match wall dimensions.
func _update_notifier_aabb() -> void:
	if not is_instance_valid(_visibility_notifier):
		return
	var aabb_size: Vector3 = Vector3(wall_size.x, wall_size.y, maxf(wall_depth, 0.5))
	_visibility_notifier.aabb = AABB(-aabb_size * 0.5, aabb_size).grow(0.5)


## Configures RoomLight shadow projection, range, and hardware distance fade.
func _update_light_static_params() -> void:
	if not is_inside_tree():
		return
	_ensure_nodes()
	if not is_instance_valid(_room_light):
		return

	_room_light.visible = _is_simulating and emission_energy > 0.01
	_room_light.shadow_enabled = true
	_room_light.omni_range = maxf(wall_size.x, wall_size.y) * 1.5
	_room_light.distance_fade_enabled = true
	_room_light.distance_fade_begin = max_render_distance * 0.8
	_room_light.distance_fade_shadow = max_render_distance * 0.8
	_room_light.distance_fade_length = maxf(max_render_distance * 0.2, 1.0)


## Sets a per-instance shader uniform directly on the WallMesh GeometryInstance3D.
func _set_shader_param(param_name: StringName, param_val: Variant) -> void:
	if not is_inside_tree():
		return
	_ensure_nodes()
	if not is_instance_valid(_wall_mesh):
		return
	_wall_mesh.set_instance_shader_parameter(param_name, param_val)


## Flushes all exported properties to WallMesh instance shader parameters.
func _sync_all_shader_params() -> void:
	var aspect: float = wall_size.x / maxf(wall_size.y, 0.01)
	_set_shader_param(PARAM_BASE_COLOR, base_color)
	_set_shader_param(PARAM_COLOR_A, ribbon_color_a)
	_set_shader_param(PARAM_COLOR_B, ribbon_color_b)
	_set_shader_param(PARAM_EMISSION, emission_energy)
	_set_shader_param(PARAM_ZOOM, zoom)
	_set_shader_param(PARAM_WAVE_CROP, maxf(wave_crop, 0.1))
	_set_shader_param(PARAM_BRIGHTNESS, brightness)
	_set_shader_param(PARAM_SPEED, speed if _is_simulating else 0.0)
	_set_shader_param(PARAM_ITERATIONS, iterations)
	_set_shader_param(PARAM_FRQ_START, frq_start)
	_set_shader_param(PARAM_FRQ_COEF, frq_coef)
	_set_shader_param(PARAM_ALPHA_THRESHOLD, alpha_threshold)
	_set_shader_param(PARAM_ASPECT_RATIO, aspect)
