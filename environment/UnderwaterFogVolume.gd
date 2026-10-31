## A volume that controls underwater fog density and fade distances.
class_name UnderwaterFogVolume
extends FogVolume

## The base density of the fog when the flashlight is off.
@export var base_density: float = 0.12

## The density of the fog when the flashlight is on.
@export var flashlight_density: float = 0.04

## The base fade distance of the fog when the flashlight is off.
@export var base_fade_dist: float = 3.0

## The fade distance of the fog when the flashlight is on.
@export var flashlight_fade_dist: float = 6.0

## The speed at which the fog transitions between base and flashlight settings.
@export var transition_speed: float = 2.5

## The current interpolated density of the fog.
var _current_density: float = 0.12

## The current interpolated fade distance of the fog.
var _current_fade_dist: float = 3.0

## Cached reference to the player's flashlight controller node.
var _flashlight_controller: Node3D = null

## Cached reference to the player's flashlight spotlight.
var _flashlight_light: SpotLight3D = null

## Cached [Camera3D] reference to avoid expensive lookups every frame.
var _cached_camera: Camera3D = null

## Throttling timer for player resolution retries.
var _player_search_timer: float = 0.0


## Initializes default density, fade distances, and attempts player binding.
func _ready() -> void:
	print("UnderwaterFogVolume: Initializing underwater fog parameters.")
	_current_density = base_density
	_current_fade_dist = base_fade_dist
	_resolve_player_flashlight()


## Updates the fog density and fade distance based on the flashlight state.
func _process(delta: float) -> void:
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

	_current_density = lerpf(_current_density, target_density, delta * transition_speed)
	_current_fade_dist = lerpf(_current_fade_dist, target_dist, delta * transition_speed)

	if material is ShaderMaterial:
		var mat: ShaderMaterial = material as ShaderMaterial
		mat.set_shader_parameter(&"density", _current_density)

		var cam: Camera3D = _get_camera()
		if cam:
			var fade_normal: Vector3 = cam.global_transform.basis.z * -1.0
			var fade_pos: Vector3 = cam.global_transform.origin + (fade_normal * _current_fade_dist)
			var fade_distance: float = fade_pos.dot(fade_normal)
			var fade_plane: Vector4 = Vector4(
				fade_normal.x, fade_normal.y, fade_normal.z, fade_distance
			)
			mat.set_shader_parameter(&"fade_plane", fade_plane)
	elif material is FogMaterial:
		var fmat: FogMaterial = material as FogMaterial
		fmat.density = _current_density
		fmat.edge_fade = 0.2


## Resolves and caches player and flashlight controller references via NodeQuery.
func _resolve_player_flashlight() -> void:
	var player: Node = NodeQuery.get_single_node_in_group(get_tree(), &"player")
	if not is_instance_valid(player):
		return

	if "flashlight_controller" in player:
		var controller_val: Variant = player.get("flashlight_controller")
		if controller_val is Node3D:
			_flashlight_controller = controller_val as Node3D
			var light_val: Variant = _flashlight_controller.get("flashlight")
			if light_val is SpotLight3D:
				_flashlight_light = light_val as SpotLight3D


## Retrieves the active [Camera3D] from the viewport.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera
