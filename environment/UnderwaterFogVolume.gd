## Controls volumetric underwater fog density and flashlight visibility fade planes.
class_name UnderwaterFogVolume
extends FogVolume

## Shader uniform identifier for fog density.
const PARAM_DENSITY: StringName = &"density"

## Shader uniform identifier for camera-relative visibility fade plane.
const PARAM_FADE_PLANE: StringName = &"fade_plane"

## Group identifier for resolving the active player node.
const GROUP_PLAYER: StringName = &"player"

## Property identifier for the player's flashlight controller node.
const PROP_FLASHLIGHT_CONTROLLER: StringName = &"flashlight_controller"

## Property identifier for the flashlight [SpotLight3D] node.
const PROP_FLASHLIGHT: StringName = &"flashlight"

## Base volumetric fog density when the flashlight is off.
@export_range(0.0, 1.0, 0.005) var base_density: float = 0.12

## Reduced volumetric fog density when the flashlight is active.
@export_range(0.0, 1.0, 0.005) var flashlight_density: float = 0.04

## Visibility ramp distance in meters when the flashlight is off.
@export_range(0.5, 50.0, 0.5) var base_fade_dist: float = 3.0

## Extended visibility ramp distance in meters when the flashlight is active.
@export_range(0.5, 50.0, 0.5) var flashlight_fade_dist: float = 6.0

## Interpolation rate between baseline and flashlight fog states.
@export_range(0.1, 20.0, 0.1) var transition_speed: float = 2.5

## Maximum distance from active camera in meters before fog uniform updates are gated.
@export_range(10.0, 500.0, 1.0) var max_update_distance: float = 95.0

## Current interpolated volumetric fog density.
var _current_density: float = 0.12

## Current interpolated visibility ramp distance in meters.
var _current_fade_dist: float = 3.0

## Cached reference to the player's flashlight controller node.
var _flashlight_controller: Node3D = null

## Cached reference to the player's flashlight [SpotLight3D].
var _flashlight_light: SpotLight3D = null

## Cached active viewport [Camera3D] reference.
var _cached_camera: Camera3D = null

## Throttling accumulator for player node lookup retries.
var _player_search_timer: float = 0.0


## Initializes baseline fog parameters, resolves flashlight, and configures process loops.
func _ready() -> void:
	assert(base_density >= 0.0, "UnderwaterFogVolume: base_density must be non-negative.")
	assert(
		flashlight_density >= 0.0, "UnderwaterFogVolume: flashlight_density must be non-negative."
	)
	_current_density = base_density
	_current_fade_dist = base_fade_dist
	_resolve_player_flashlight()
	set_physics_process(false)
	set_process(true)


## Updates volumetric fog density and camera-aligned fade plane when within range.
func _process(delta: float) -> void:
	var cam: Camera3D = _get_camera()
	if is_instance_valid(cam):
		var half_diag: float = size.length() * 0.5
		var max_dist: float = max_update_distance + half_diag
		if global_position.distance_squared_to(cam.global_position) > max_dist * max_dist:
			return

	if not is_instance_valid(_flashlight_controller):
		_player_search_timer += delta
		if _player_search_timer >= 0.5:
			_player_search_timer = 0.0
			_resolve_player_flashlight()

	var target_density: float = base_density
	var target_dist: float = base_fade_dist

	if is_instance_valid(_flashlight_light) and _flashlight_light.visible:
		target_density = flashlight_density
		target_dist = flashlight_fade_dist

	_current_density = lerpf(_current_density, target_density, minf(delta * transition_speed, 1.0))
	_current_fade_dist = lerpf(_current_fade_dist, target_dist, minf(delta * transition_speed, 1.0))

	if material is ShaderMaterial:
		var mat: ShaderMaterial = material as ShaderMaterial
		mat.set_shader_parameter(PARAM_DENSITY, _current_density)

		if is_instance_valid(cam):
			var fade_normal: Vector3 = -cam.global_transform.basis.z
			var fade_pos: Vector3 = cam.global_transform.origin + (fade_normal * _current_fade_dist)
			var fade_distance: float = fade_pos.dot(fade_normal)
			var fade_plane: Vector4 = Vector4(
				fade_normal.x, fade_normal.y, fade_normal.z, fade_distance
			)
			mat.set_shader_parameter(PARAM_FADE_PLANE, fade_plane)
	elif material is FogMaterial:
		var fmat: FogMaterial = material as FogMaterial
		fmat.density = _current_density
		fmat.edge_fade = 0.2


## Adjusts edge fade sharpness when camera enters or exits the parent water volume.
func set_submerged(is_submerged: bool) -> void:
	if material is ShaderMaterial:
		var mat: ShaderMaterial = material as ShaderMaterial
		mat.set_shader_parameter(&"edge_fade", 0.05 if is_submerged else 0.15)
	elif material is FogMaterial:
		var fmat: FogMaterial = material as FogMaterial
		fmat.edge_fade = 0.05 if is_submerged else 0.2


## Resolves and caches player and flashlight controller references via [NodeQuery].
func _resolve_player_flashlight() -> void:
	var player: Node = NodeQuery.get_single_node_in_group(get_tree(), GROUP_PLAYER)
	if not is_instance_valid(player):
		return

	if PROP_FLASHLIGHT_CONTROLLER in player:
		var controller_val: Variant = player.get(PROP_FLASHLIGHT_CONTROLLER)
		if controller_val is Node3D:
			_flashlight_controller = controller_val
			var light_val: Variant = _flashlight_controller.get(PROP_FLASHLIGHT)
			if light_val is SpotLight3D:
				_flashlight_light = light_val


## Retrieves the active viewport [Camera3D], refreshing cached reference if invalidated.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera) or not _cached_camera.is_inside_tree():
		var vp: Viewport = get_viewport()
		_cached_camera = vp.get_camera_3d() if is_instance_valid(vp) else null
	return _cached_camera
