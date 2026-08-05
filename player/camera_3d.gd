extends Camera3D

@export_category("Screenshake Settings")
@export var noise_speed: float = 50.0
@export var max_offset_x: float = 0.5
@export var max_offset_y: float = 0.5
@export var max_roll_z: float = 2.0

var _trauma: float = 0.0
var _amplitude: float = 0.0
var _decay_rate: float = 1.0
var _time_passed: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()

## Reference to the full-screen quad mesh used for accessibility rendering.
@onready var vision_assist_mesh: MeshInstance3D = $VisionAssistMesh

## Cached shader material to update background colors efficiently.
var _vision_shader_material: ShaderMaterial


func _ready() -> void:
	make_current()
	print("Camera3D: Player camera has been set as the current active camera.")

	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	Events.screenshake_requested.connect(_on_screenshake_requested)

	if Events.has_signal("vision_assist_toggled"):
		if not Events.vision_assist_toggled.is_connected(_on_vision_assist_toggled):
			Events.vision_assist_toggled.connect(_on_vision_assist_toggled)

	# Cache the shader material for 60 FPS safe uniform updates
	if is_instance_valid(vision_assist_mesh):
		var active_mat: Material = vision_assist_mesh.get_active_material(0)
		if active_mat is ShaderMaterial:
			_vision_shader_material = active_mat as ShaderMaterial
			print("Camera3D: Vision assist shader cached successfully.")
		else:
			push_error("Camera3D: VisionAssistMesh lacks a valid ShaderMaterial on surface 0.")

	if Events.has_signal("vision_assist_mode_changed"):
		if not Events.vision_assist_mode_changed.is_connected(set_vision_assist_mode):
			Events.vision_assist_mode_changed.connect(set_vision_assist_mode)


func _process(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = maxf(_trauma - (_decay_rate * delta), 0.0)
		_apply_shake(delta)
	elif h_offset != 0.0 or v_offset != 0.0:
		h_offset = 0.0
		v_offset = 0.0
		rotation_degrees.z = 0.0
		_amplitude = 0.0


func _apply_shake(delta: float) -> void:
	_time_passed += delta * noise_speed

	# Square the 0-1 trauma for a smooth dropoff, then multiply by the raw HL2 intensity
	var shake_power: float = (_trauma * _trauma) * _amplitude

	h_offset = max_offset_x * shake_power * _noise.get_noise_2d(_time_passed, 0.0)
	v_offset = max_offset_y * shake_power * _noise.get_noise_2d(_time_passed, 100.0)
	rotation_degrees.z = max_roll_z * shake_power * _noise.get_noise_2d(_time_passed, 200.0)


func _on_screenshake_requested(intensity: float, duration: float) -> void:
	print(
		"Camera3D triggered: Applying screenshake (Intensity: ",
		intensity,
		", Duration: ",
		duration,
		"s)"
	)

	# If overlapping shakes occur, take the strongest one
	_amplitude = maxf(_amplitude, clampf(intensity, 0.0, 16.0))
	_trauma = 1.0  # Reset the timing envelope to 100%

	if duration > 0.0:
		_decay_rate = 1.0 / duration
	else:
		_decay_rate = 1.0


func _on_vision_assist_toggled(is_active: bool) -> void:
	print("Camera3D: Vision assist overlay visibility changed to: ", is_active)
	if is_instance_valid(vision_assist_mesh):
		vision_assist_mesh.visible = is_active


## Changes the shader's base color to swap between Black/White, AAA Blue, and Pure Black modes.
func set_vision_assist_mode(mode_name: String) -> void:
	print("Camera3D: Changing vision assist mode to: ", mode_name)
	if not is_instance_valid(_vision_shader_material):
		return

	match mode_name:
		"black_and_white":
			_vision_shader_material.set_shader_parameter("base_color", Color.WHITE)
			_vision_shader_material.set_shader_parameter("outline_color", Color.BLACK)
		"aaa_blue":
			# Adjust this color to match the exact background blue you want
			_vision_shader_material.set_shader_parameter("base_color", Color(0.1, 0.1, 0.4, 1.0))
			_vision_shader_material.set_shader_parameter("outline_color", Color.BLACK)
		"pure_black":
			_vision_shader_material.set_shader_parameter("base_color", Color.BLACK)
			# Using white outlines for high-contrast wireframe navigation.
			# If you want a complete void where ONLY grouped items are visible, change this to Color.BLACK.
			_vision_shader_material.set_shader_parameter("outline_color", Color.WHITE)
