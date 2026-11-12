## Fullscreen screen-space dizzy/drunk post-process and [Camera3D] sway controller.
## Modulates [ShaderMaterial] intensity via [Tween] and gates [_process] when idle.
# class_name DrunkEffect
extends CanvasLayer

## Emitted when the drunk transition finishes reaching target weight.
@warning_ignore("unused_signal")
signal transition_completed(current_intensity: float)

## Shader uniform parameter for normalized effect weight.
const PARAM_INTENSITY: StringName = &"intensity"

## Primary frequency multiplier for organic dual-wave roll.
const ROLL_FREQ_A: float = 1.7

## Secondary incommensurate frequency multiplier for roll.
const ROLL_FREQ_B: float = 2.3

## Primary frequency multiplier for FOV breathing pulse.
const FOV_FREQ_A: float = 1.3

## Secondary incommensurate frequency multiplier for FOV pulse.
const FOV_FREQ_B: float = 2.1

## Fullscreen [ColorRect] rendering the post-process shader material.
@export var post_rect: ColorRect

## Target [Camera3D] to receive roll sway and FOV breathing pulsations.
@export var target_camera: Camera3D

## Speed multiplier for camera roll sway and FOV pulsation oscillations.
@export_range(0.0, 20.0, 0.1) var sway_speed: float = 2.5

## Maximum camera roll rotation in radians at full intensity.
@export_range(0.0, 0.5, 0.01) var max_roll_rad: float = 0.08

## Maximum field-of-view pulse amplitude in degrees at full intensity.
@export_range(0.0, 30.0, 0.5) var max_fov_pulse: float = 8.0

## Active [Tween] animating normalized intensity transitions.
var _tween: Tween = null

## Cached [ShaderMaterial] instance extracted from [member post_rect].
var _shader_mat: ShaderMaterial = null

## Current normalized drunk distortion intensity in range 0.0 to 1.0.
var _current_intensity: float = 0.0

## Accumulated time parameter driving camera sway wave harmonics.
var _sway_time: float = 0.0

## Baseline field-of-view captured before sway breathing takes control.
var _base_fov: float = 75.0

## Baseline Z-axis roll rotation captured before camera sway takes control.
var _base_roll: float = 0.0

## Tracks whether camera baseline FOV and roll parameters are captured.
var _camera_captured: bool = false


## Validates required nodes, caches [ShaderMaterial], and disables frame loops.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	_resolve_camera()

	assert(post_rect != null, "DrunkEffect: post_rect ColorRect must be assigned.")
	assert(target_camera != null, "DrunkEffect: target_camera Camera3D must be assigned.")
	_shader_mat = post_rect.material as ShaderMaterial
	assert(_shader_mat != null, "DrunkEffect: post_rect requires a ShaderMaterial.")

	layer = 10
	_apply_intensity(0.0)
	Utilities.safe_connect(Events.drunk_intensity_changed, _on_drunk_intensity_changed)


## Drives incommensurate sine-wave Z-roll and FOV offsets while effect is active.
func _process(delta: float) -> void:
	if not is_instance_valid(target_camera):
		set_process(false)
		return

	_sway_time += delta * sway_speed
	var roll_wave: float = (sin(_sway_time * ROLL_FREQ_A) + cos(_sway_time * ROLL_FREQ_B)) * 0.5
	var fov_wave: float = (sin(_sway_time * FOV_FREQ_A) + cos(_sway_time * FOV_FREQ_B)) * 0.5

	target_camera.rotation.z = _base_roll + (roll_wave * max_roll_rad * _current_intensity)
	target_camera.fov = clampf(
		_base_fov + (fov_wave * max_fov_pulse * _current_intensity), 1.0, 179.0
	)


## Cleans up active tweens, disconnects global signals, and restores camera values.
func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if Events.drunk_intensity_changed.is_connected(_on_drunk_intensity_changed):
		Events.drunk_intensity_changed.disconnect(_on_drunk_intensity_changed)
	if _camera_captured and is_instance_valid(target_camera):
		target_camera.fov = _base_fov
		target_camera.rotation.z = _base_roll


## Transitions drunk intensity to [param target] over [param duration] seconds.
func transition_intensity(target: float, duration: float = 0.6) -> void:
	var clamped_target: float = clampf(target, 0.0, 1.0)
	print("DrunkEffect: transitioning intensity -> ", clamped_target)

	if _tween != null and _tween.is_valid():
		_tween.kill()

	if clamped_target > 0.0001 and not _camera_captured and is_instance_valid(target_camera):
		_base_fov = target_camera.fov
		_base_roll = target_camera.rotation.z
		_camera_captured = true

	if duration <= 0.0:
		_apply_intensity(clamped_target)
		transition_completed.emit(_current_intensity)
		return

	visible = true
	post_rect.visible = true
	set_process(true)

	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_apply_intensity, _current_intensity, clamped_target, duration)
	_tween.finished.connect(_on_tween_finished)


## Updates shader uniform and toggles canvas/process states at zero weight.
func _apply_intensity(value: float) -> void:
	_current_intensity = value
	if is_instance_valid(_shader_mat):
		_shader_mat.set_shader_parameter(PARAM_INTENSITY, value)

	var is_active: bool = value > 0.0001
	if is_inside_tree() and is_instance_valid(post_rect):
		post_rect.visible = is_active
		visible = is_active

	set_process(is_active)

	if not is_active and _camera_captured and is_instance_valid(target_camera):
		target_camera.fov = _base_fov
		target_camera.rotation.z = _base_roll
		_camera_captured = false
		_sway_time = 0.0


## Finalizes visibility state and emits [signal transition_completed].
func _on_tween_finished() -> void:
	_apply_intensity(_current_intensity)
	print("DrunkEffect: transition finished at ", _current_intensity)
	transition_completed.emit(_current_intensity)


## Handles global drunk intensity change requests dispatched from [Events].
func _on_drunk_intensity_changed(target_intensity: float, duration: float) -> void:
	transition_intensity(target_intensity, duration)


## Attempts to resolve [member target_camera] from parent hierarchy or active viewport.
func _resolve_camera() -> void:
	if is_instance_valid(target_camera):
		return
	if is_instance_valid(get_parent()):
		var raw_cam: Node = get_parent().find_child("Camera3D", true, false)
		if raw_cam is Camera3D:
			target_camera = raw_cam
			return
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			target_camera = vp.get_camera_3d()
			if is_instance_valid(target_camera):
				return
		var root_cam: Node = get_tree().root.find_child("Camera3D", true, false)
		if root_cam is Camera3D:
			target_camera = root_cam
