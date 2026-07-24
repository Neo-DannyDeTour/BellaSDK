class_name UnderwaterFogVolume
extends FogVolume

@export_category("Fog Settings")
@export var base_density: float = 1.0
@export var flashlight_density: float = 0.15  # Lowers density so you can see further
@export var base_fade_dist: float = 3.0
@export var flashlight_fade_dist: float = 5.0
@export var transition_speed: float = 2.5

var _current_density: float = 1.0
var _current_fade_dist: float = 3.0
var _flashlight_controller: Node3D = null
## Cached Camera3D reference to avoid expensive get_viewport().get_camera_3d() calls every frame.
var _cached_camera: Camera3D = null


func _ready() -> void:
	_current_density = base_density
	_current_fade_dist = base_fade_dist


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
		var mat := self.material as ShaderMaterial
		mat.set_shader_parameter("density", _current_density)

		var cam: Camera3D = _get_camera()
		if cam:
			var fade_normal: Vector3 = cam.global_transform.basis.z * -1.0
			var fade_pos: Vector3 = cam.global_transform.origin + (fade_normal * _current_fade_dist)
			var fade_distance: float = fade_pos.dot(fade_normal)
			var fade_plane := Vector4(fade_normal.x, fade_normal.y, fade_normal.z, fade_distance)
			mat.set_shader_parameter("fade_plane", fade_plane)


func _get_camera() -> Camera3D:
	if not is_instance_valid(_cached_camera):
		_cached_camera = get_viewport().get_camera_3d() if get_viewport() else null
	return _cached_camera
