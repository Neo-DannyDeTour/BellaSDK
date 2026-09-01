## Extends the base Camera3D to manage active audio listening,
## screenshake, and visual assist shaders.
class_name ExtendedCamera3D
extends Camera3D

@export_category("Camera Role")
## If enabled, registers and activates spatial audio listeners and makes current on startup.
@export var is_player_camera: bool = true

@export_category("Screenshake Settings")
## Speed of the noise generator driving screenshake calculations.
@export var noise_speed: float = 50.0
## Maximum horizontal pixel offset applied during screenshake.
@export var max_offset_x: float = 0.5
## Maximum vertical pixel offset applied during screenshake.
@export var max_offset_y: float = 0.5
## Maximum rotational roll in degrees applied during screenshake.
@export var max_roll_z: float = 2.0

## Tracks the current decay envelope of the active screen shake.
var _trauma: float = 0.0
## Tracks the peak amplitude assigned to the current shake event.
var _amplitude: float = 0.0
## The speed at which trauma returns to zero over time.
var _decay_rate: float = 1.0
## Time accumulation variable passed into the FastNoiseLite generator.
var _time_passed: float = 0.0
## Noise algorithm instance used for smooth procedural shake offsets.
var _noise: FastNoiseLite = FastNoiseLite.new()

## Reference to the full-screen quad mesh used for accessibility rendering.
var vision_assist_mesh: MeshInstance3D = null

## Dedicated spatial listener node to calculate 3D audio panning and attenuation.
var _spatial_listener: AudioListener3D = AudioListener3D.new()

## Cached unique shader material to update background colors efficiently.
var _vision_shader_material: ShaderMaterial


## Lifecycle method initializing the camera, spatial listener, and signal connections.
func _ready() -> void:
	_resolve_vision_mesh()
	_cache_vision_material()

	if is_player_camera:
		make_current()
		print("Camera3D: Player camera set as active listener.")
		_setup_audio_listener()
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("player_camera_registered"):
				print("Camera3D: Registering active camera to Events bus.")
				events.emit_signal("player_camera_registered", self)

	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("screenshake_requested") and is_player_camera:
			events.screenshake_requested.connect(_on_screenshake_requested)
		if events.has_signal("vision_assist_toggled") and is_player_camera:
			events.vision_assist_toggled.connect(_on_vision_assist_toggled)
		if events.has_signal("vision_assist_mode_changed"):
			events.vision_assist_mode_changed.connect(set_vision_assist_mode)


## Locates the vision assist MeshInstance3D child node regardless of name suffix.
func _resolve_vision_mesh() -> void:
	if is_instance_valid(vision_assist_mesh):
		return
	vision_assist_mesh = get_node_or_null("VisionAssistMesh")
	if not is_instance_valid(vision_assist_mesh):
		for child: Node in get_children():
			if child is MeshInstance3D and child.name.begins_with("VisionAssistMesh"):
				vision_assist_mesh = child as MeshInstance3D
				break


## Duplicates and isolates the ShaderMaterial for this camera instance.
func _cache_vision_material() -> void:
	_resolve_vision_mesh()
	if is_instance_valid(vision_assist_mesh):
		var active_mat: Material = vision_assist_mesh.get_active_material(0)
		if active_mat is ShaderMaterial:
			_vision_shader_material = active_mat.duplicate() as ShaderMaterial
			_vision_shader_material.render_priority = 10
			vision_assist_mesh.set_surface_override_material(0, _vision_shader_material)
			print("Camera3D: [", name, "] Material duplicated and cached.")


## Creates and activates the AudioListener3D directly attached to the camera head.
func _setup_audio_listener() -> void:
	add_child(_spatial_listener)
	_spatial_listener.make_current()


## Process loop driving procedural trauma reduction and camera offset decay.
## [param delta] Elapsed frame time in seconds.
func _process(delta: float) -> void:
	if not is_player_camera:
		return

	if _trauma > 0.0:
		_trauma = maxf(_trauma - (_decay_rate * delta), 0.0)
		_apply_shake(delta)
	elif h_offset != 0.0 or v_offset != 0.0:
		h_offset = 0.0
		v_offset = 0.0
		rotation_degrees.z = 0.0
		_amplitude = 0.0


## Evaluates noise coordinates and offsets camera position and roll.
## [param delta] Elapsed frame time in seconds.
func _apply_shake(delta: float) -> void:
	_time_passed += delta * noise_speed
	var shake_power: float = (_trauma * _trauma) * _amplitude

	h_offset = max_offset_x * shake_power * _noise.get_noise_2d(_time_passed, 0.0)
	v_offset = max_offset_y * shake_power * _noise.get_noise_2d(_time_passed, 100.0)
	rotation_degrees.z = max_roll_z * shake_power * _noise.get_noise_2d(_time_passed, 200.0)


## Triggers an impulse of screenshake trauma from global event bus requests.
## [param intensity] The peak magnitude of the screenshake displacement.
## [param duration] How long in seconds the shake takes to settle back to zero.
func _on_screenshake_requested(intensity: float, duration: float) -> void:
	print("Camera3D: [", name, "] Received screenshake request. Intensity: ", intensity)
	_amplitude = maxf(_amplitude, clampf(intensity, 0.0, 16.0))
	_trauma = 1.0
	_decay_rate = 1.0 / duration if duration > 0.0 else 1.0


## Updates visibility of the accessibility high-contrast shader quad.
## [param is_active] True if vision assist should be rendered.
func _on_vision_assist_toggled(is_active: bool) -> void:
	_resolve_vision_mesh()
	print("Camera3D: [", name, "] Setting vision mesh visibility: ", is_active)
	if is_instance_valid(vision_assist_mesh):
		vision_assist_mesh.visible = is_active


## Changes the shader mode integer parameter.
## [param mode_name] Key identifier matching preset.
func set_vision_assist_mode(mode_name: String) -> void:
	if not is_instance_valid(_vision_shader_material):
		_cache_vision_material()

	if not is_instance_valid(_vision_shader_material):
		return

	print("Camera3D: [", name, "] Applying vision mode: ", mode_name)
	match mode_name:
		"black_and_white":
			_vision_shader_material.set_shader_parameter("mode", 0)
		"blue":
			_vision_shader_material.set_shader_parameter("mode", 1)
			_vision_shader_material.set_shader_parameter("blue_base", Color(0.05, 0.1, 0.45, 1.0))
			_vision_shader_material.set_shader_parameter("blue_outline", Color(0.3, 0.5, 0.9, 1.0))
		"pure_black":
			_vision_shader_material.set_shader_parameter("mode", 2)
		"grey":
			_vision_shader_material.set_shader_parameter("mode", 3)
			_vision_shader_material.set_shader_parameter("grey_base", Color(0.25, 0.25, 0.25, 1.0))
			_vision_shader_material.set_shader_parameter(
				"grey_outline", Color(0.85, 0.85, 0.85, 1.0)
			)
		"desaturated":
			_vision_shader_material.set_shader_parameter("mode", 4)
