## A volume that controls underwater fog density and fade distances.
##
## [UnderwaterFogVolume] dynamically adjusts its density and fade distance when the player's
## flashlight is turned on, allowing for better visibility underwater.
class_name UnderwaterFogVolume
extends FogVolume

@export_category("Fog Settings")
## The base density of the fog when the flashlight is off.
@export var base_density: float = 1.0

## The density of the fog when the flashlight is on. Lowers density to increase visibility.
@export var flashlight_density: float = 0.15

## The base fade distance of the fog when the flashlight is off.
@export var base_fade_dist: float = 3.0

## The fade distance of the fog when the flashlight is on.
@export var flashlight_fade_dist: float = 5.0

## The speed at which the fog transitions between base and flashlight settings.
@export var transition_speed: float = 2.5

## The current interpolated density of the fog.
var _current_density: float = 1.0

## The current interpolated fade distance of the fog.
var _current_fade_dist: float = 3.0

## Cached reference to the player's flashlight controller node.
var _flashlight_controller: Node3D = null

## Cached [Camera3D] reference to avoid expensive [method Viewport.get_camera_3d] calls every frame.
var _cached_camera: Camera3D = null


## Called when the node enters the scene tree for the first time.
## Initializes the fog properties to their base values.
func _ready() -> void:
	_current_density = base_density
	_current_fade_dist = base_fade_dist


## Called every frame. Updates the fog density and fade distance based on the flashlight state.
## [param delta] The time elapsed since the previous frame in seconds.
func _process(delta: float) -> void:
	# 1. Dynamically locate the flashlight controller once
	if not is_instance_valid(_flashlight_controller):
		var player: Node = get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and "flashlight_controller" in player:
			_flashlight_controller = player.get("flashlight_controller") as Node3D

	# 2. Determine target values based on flashlight state
	var target_density: float = base_density
	var target_dist: float = base_fade_dist

	if is_instance_valid(_flashlight_controller):
		var light: SpotLight3D = _flashlight_controller.get("flashlight") as SpotLight3D
		if is_instance_valid(light) and light.visible:
			target_density = flashlight_density
			target_dist = flashlight_fade_dist

	# 3. Fluidly interpolate the values
	_current_density = lerpf(_current_density, target_density, delta * transition_speed)
	_current_fade_dist = lerpf(_current_fade_dist, target_dist, delta * transition_speed)

	# 4. Apply to your custom shader
	if self.material is ShaderMaterial:
		var mat: ShaderMaterial = self.material as ShaderMaterial
		mat.set_shader_parameter("density", _current_density)

		var cam: Camera3D = _get_camera()
		if cam:
			var fade_normal: Vector3 = cam.global_transform.basis.z * -1.0
			var fade_pos: Vector3 = cam.global_transform.origin + (fade_normal * _current_fade_dist)
			var fade_distance: float = fade_pos.dot(fade_normal)
			var fade_plane: Vector4 = Vector4(
				fade_normal.x, fade_normal.y, fade_normal.z, fade_distance
			)
			mat.set_shader_parameter("fade_plane", fade_plane)


## Retrieves the active [Camera3D] from the viewport, caching it for future use.
## [return] The active [Camera3D] instance, or [code]null[/code] if none is found.
func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera
