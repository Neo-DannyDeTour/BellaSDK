## Centralized camera screenshake and impulse manager supporting accessibility scaling.
class_name CameraShakeManager
extends Node

## Emitted when camera shake offset and rotation update. Passes offset and roll angle.
signal shake_updated(offset: Vector2, roll_rad: float)

## Emitted when all camera shake and rumble impulses have fully decayed to zero.
signal shake_finished

## Global intensity multiplier tied to user accessibility and comfort settings.
@export_range(0.0, 2.0, 0.05) var global_intensity: float = 1.0

## Maximum translational pixel displacement offset allowed for camera shake.
@export var max_offset_px: Vector2 = Vector2(32.0, 32.0)

## Maximum rotational roll angle in radians allowed for camera shake.
@export var max_roll_rad: float = 0.08

## Frequency scalar driving continuous Simplex noise sampling over time.
@export var noise_frequency: float = 24.0

## Decay rate exponent controlling non-linear trauma falloff speed.
@export var trauma_decay_rate: float = 1.2

## Current trauma level clamped between 0.0 and 1.0.
var trauma: float = 0.0

## Internal fast OpenSimplexNoise generator used for organic directional shake.
var _noise: FastNoiseLite = FastNoiseLite.new()

## Internal noise sample counter advancing continuously with frame delta time.
var _noise_sample_time: float = 0.0

## Current active camera target listener receiving direct transform manipulation.
var _active_camera: Camera3D = null

## Base local transform of the active camera captured before shake offsets apply.
var _camera_base_transform: Transform3D = Transform3D.IDENTITY

## Active sustained rumble intensity factor decaying separately from trauma.
var _sustained_rumble_intensity: float = 0.0

## Remaining duration in seconds for currently active sustained rumble effect.
var _sustained_rumble_timer: float = 0.0


## Initializes noise parameters and connects global event bus listeners.
func _ready() -> void:
	print("CameraShakeManager: Initializing camera shake manager.")
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.5

	Events.screenshake_requested.connect(_on_screenshake_requested)
	Events.player_camera_registered.connect(register_camera)


## Steps trauma decay, samples organic noise, and updates listener camera offsets.
func _process(delta: float) -> void:
	if trauma <= 0.0 and _sustained_rumble_timer <= 0.0:
		return

	if trauma > 0.0:
		trauma = maxf(0.0, trauma - (trauma_decay_rate * delta))

	if _sustained_rumble_timer > 0.0:
		_sustained_rumble_timer -= delta
		if _sustained_rumble_timer <= 0.0:
			_sustained_rumble_intensity = 0.0

	_noise_sample_time += delta * noise_frequency

	var effective_intensity: float = _calculate_effective_shake()
	if effective_intensity <= 0.001:
		_reset_camera()
		shake_finished.emit()
		return

	_apply_shake_to_camera(effective_intensity)


## Computes combined squared trauma and sustained rumble scaled by accessibility.
func _calculate_effective_shake() -> float:
	var total_intensity: float = maxf(trauma * trauma, _sustained_rumble_intensity)
	return total_intensity * global_intensity


## Samples noise values and applies translational and roll offsets to active camera.
func _apply_shake_to_camera(intensity: float) -> void:
	var offset_x: float = max_offset_px.x * intensity * _noise.get_noise_2d(_noise_sample_time, 0.0)
	var offset_y: float = max_offset_px.y * intensity * _noise.get_noise_2d(0.0, _noise_sample_time)
	var roll: float = (
		max_roll_rad * intensity * _noise.get_noise_2d(_noise_sample_time, _noise_sample_time)
	)

	shake_updated.emit(Vector2(offset_x, offset_y), roll)

	if not is_instance_valid(_active_camera):
		return

	# Convert 2D pixel offset scale into subtle 3D camera translational displacement
	var displacement_3d: Vector3 = Vector3(offset_x * 0.01, offset_y * 0.01, 0.0)
	var target_basis: Basis = _camera_base_transform.basis.rotated(Vector3.FORWARD, roll)

	_active_camera.transform.basis = target_basis
	_active_camera.transform.origin = _camera_base_transform.origin + displacement_3d


## Restores original camera transform and zero offsets upon shake completion.
func _reset_camera() -> void:
	print("CameraShakeManager: Resetting camera transform.")
	if is_instance_valid(_active_camera):
		_active_camera.transform = _camera_base_transform
	shake_updated.emit(Vector2.ZERO, 0.0)


## Registers an active [Camera3D] node as recipient of shake transform updates.
func register_camera(camera: Camera3D) -> void:
	print("CameraShakeManager: Registering active camera: ", camera.name if camera else "null")
	if is_instance_valid(_active_camera) and _active_camera != camera:
		_reset_camera()

	_active_camera = camera
	if is_instance_valid(_active_camera):
		_camera_base_transform = _active_camera.transform


## Adds instant impulse trauma from explosions, impacts, or weapon recoils.
func add_trauma(amount: float) -> void:
	print("CameraShakeManager: Adding impulse trauma: ", amount)
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Starts sustained rumble effect with constant intensity and defined duration.
func start_rumble(intensity: float, duration: float) -> void:
	print(
		"CameraShakeManager: Starting sustained rumble. Intensity: ",
		intensity,
		" Duration: ",
		duration
	)
	_sustained_rumble_intensity = clampf(intensity, 0.0, 1.0)
	_sustained_rumble_timer = maxf(0.0, duration)


## Stops all active trauma and sustained rumble effects immediately.
func stop_all() -> void:
	print("CameraShakeManager: Halting all active camera shake.")
	trauma = 0.0
	_sustained_rumble_intensity = 0.0
	_sustained_rumble_timer = 0.0
	_reset_camera()
	shake_finished.emit()


## Callback responding to global [signal Events.screenshake_requested] bus requests.
func _on_screenshake_requested(intensity: float, duration: float) -> void:
	print(
		"CameraShakeManager: Received screenshake request. Intensity: ",
		intensity,
		" Duration: ",
		duration
	)
	if duration <= 0.15:
		add_trauma(intensity)
	else:
		start_rumble(intensity, duration)


## Updates global accessibility shake multiplier from gameplay settings.
func set_accessibility_scale(scale_factor: float) -> void:
	print("CameraShakeManager: Accessibility shake scale updated to: ", scale_factor)
	global_intensity = clampf(scale_factor, 0.0, 2.0)
