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


func _ready() -> void:
	make_current()
	print("Player camera has been set as the current active camera.")

	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	Events.screenshake_requested.connect(_on_screenshake_requested)


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
