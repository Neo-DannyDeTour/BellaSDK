## Solves procedural weapon sway, movement bobbing, sprint transitions, and inspection sequences.
class_name WeaponProceduralAnimator
extends Node3D

## Emitted when an inspection animation sequence completes.
@warning_ignore("unused_signal")
signal inspect_completed

## Emitted when an inspection animation is cancelled early by player action.
@warning_ignore("unused_signal")
signal inspect_cancelled

enum AnimationState {
	IDLE,
	WALKING,
	SPRINTING,
	INSPECTING,
	RELOADING,
}

## Baseline resting transform position relative to camera eye socket.
const DEFAULT_REST_POSITION: Vector3 = Vector3(0.22, -0.22, -0.45)

## Baseline resting transform rotation in radians relative to camera eye socket.
const DEFAULT_REST_ROTATION: Vector3 = Vector3.ZERO

## Maximum permissible angular sway displacement in radians.
const MAX_SWAY_ROTATION: float = 0.12

## Maximum permissible translational sway displacement in meters.
const MAX_SWAY_POSITION: float = 0.025

## Smoothing speed constant for spring damping interpolation.
const SWAY_SMOOTH_SPEED: float = 14.0

## Target local position for weapon rest pose.
@export var rest_position: Vector3 = DEFAULT_REST_POSITION

## Target local rotation in radians for weapon rest pose.
@export var rest_rotation: Vector3 = DEFAULT_REST_ROTATION

## Mouse horizontal rotation sway sensitivity multiplier.
@export_range(0.0001, 0.01, 0.0005) var sway_yaw_amount: float = 0.0018

## Mouse vertical rotation sway sensitivity multiplier.
@export_range(0.0001, 0.01, 0.0005) var sway_pitch_amount: float = 0.0018

## Mouse roll sway sensitivity multiplier applied during horizontal look.
@export_range(0.0001, 0.01, 0.0005) var sway_roll_amount: float = 0.0012

## Mouse translational displacement sensitivity multiplier.
@export_range(0.0001, 0.005, 0.0002) var sway_pos_amount: float = 0.0006

## Walking bobbing frequency rate.
@export var walk_bob_frequency: float = 10.0

## Walking horizontal bobbing displacement amplitude.
@export var walk_bob_amplitude_x: float = 0.008

## Walking vertical bobbing displacement amplitude.
@export var walk_bob_amplitude_y: float = 0.006

## Walking roll tilt amplitude in radians.
@export var walk_bob_roll_amplitude: float = 0.015

## Sprint bobbing frequency rate.
@export var sprint_bob_frequency: float = 15.0

## Sprint horizontal bobbing displacement amplitude.
@export var sprint_bob_amplitude_x: float = 0.018

## Sprint vertical bobbing displacement amplitude.
@export var sprint_bob_amplitude_y: float = 0.014

## Sprint roll tilt amplitude in radians.
@export var sprint_bob_roll_amplitude: float = 0.035

## Target position offset applied during tactical sprint stance.
@export var sprint_pose_position: Vector3 = Vector3(-0.05, 0.0, 0.16)

## Target rotation offset in radians applied during tactical sprint stance.
@export var sprint_pose_rotation: Vector3 = Vector3(0.0, 1.65806, -0.17453)

## Procedural reload position dip offset.
@export var reload_pose_position: Vector3 = Vector3(-0.02, -0.10, 0.05)

## Procedural reload rotation tilt in radians.
@export var reload_pose_rotation: Vector3 = Vector3(-0.25, 0.15, -0.20)

## Master toggle governing procedural updates.
var is_active: bool = true

## Active animation state of the viewmodel.
var state: AnimationState = AnimationState.IDLE

## Current accumulated mouse motion delta for the active frame.
var _mouse_delta: Vector2 = Vector2.ZERO

## Target angular sway rotation vector.
var _target_sway_rot: Vector3 = Vector3.ZERO

## Current smoothed angular sway rotation vector.
var _current_sway_rot: Vector3 = Vector3.ZERO

## Target translational sway offset vector.
var _target_sway_pos: Vector3 = Vector3.ZERO

## Current smoothed translational sway offset vector.
var _current_sway_pos: Vector3 = Vector3.ZERO

## Target locomotion bobbing position vector.
var _target_bob_pos: Vector3 = Vector3.ZERO

## Current smoothed locomotion bobbing position vector.
var _current_bob_pos: Vector3 = Vector3.ZERO

## Target locomotion bobbing rotation vector.
var _target_bob_rot: Vector3 = Vector3.ZERO

## Current smoothed locomotion bobbing rotation vector.
var _current_bob_rot: Vector3 = Vector3.ZERO

## Target sprint stance position offset.
var _target_sprint_pos: Vector3 = Vector3.ZERO

## Current smoothed sprint stance position offset.
var _current_sprint_pos: Vector3 = Vector3.ZERO

## Target sprint stance rotation offset.
var _target_sprint_rot: Vector3 = Vector3.ZERO

## Current smoothed sprint stance rotation offset.
var _current_sprint_rot: Vector3 = Vector3.ZERO

## Active procedural inspect translation offset driven by tween.
var _inspect_pos: Vector3 = Vector3.ZERO

## Active procedural inspect rotation offset driven by tween.
var _inspect_rot: Vector3 = Vector3.ZERO

## Active procedural reload translation offset driven by tween.
var _reload_pos: Vector3 = Vector3.ZERO

## Active procedural reload rotation offset driven by tween.
var _reload_rot: Vector3 = Vector3.ZERO

## Locomotion step cycle accumulator.
var _bob_timer: float = 0.0

## Idle breathing cycle accumulator.
var _idle_timer: float = 0.0

## Cached reference to root player entity.
var _player: CharacterBody3D = null

## Cached reference to locomotion component.
var _locomotion: PlayerLocomotionComponent = null

## Active tween driving inspect animation sequence.
var _inspect_tween: Tween = null

## Active tween driving reload animation sequence.
var _reload_tween: Tween = null


## Initializes default positions and locates player locomotion references.
func _ready() -> void:
	print("WeaponProceduralAnimator: Initializing viewmodel animator.")
	position = rest_position
	rotation = rest_rotation
	_resolve_player_references()


## Intercepts mouse motion inputs to accumulate sway delta.
func _unhandled_input(event: InputEvent) -> void:
	if not is_active or not visible:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_mouse_delta.x += motion.relative.x
		_mouse_delta.y += motion.relative.y


## Lifecycle per-frame update solving sway, bobbing, and sprint blending.
func _process(delta: float) -> void:
	if not is_active or not visible:
		return

	_resolve_player_references()

	# 1. Evaluate mouse look sway
	_target_sway_rot.y = clampf(
		-_mouse_delta.x * sway_yaw_amount, -MAX_SWAY_ROTATION, MAX_SWAY_ROTATION
	)
	_target_sway_rot.x = clampf(
		_mouse_delta.y * sway_pitch_amount, -MAX_SWAY_ROTATION, MAX_SWAY_ROTATION
	)
	_target_sway_rot.z = clampf(
		-_mouse_delta.x * sway_roll_amount, -MAX_SWAY_ROTATION, MAX_SWAY_ROTATION
	)

	_target_sway_pos.x = clampf(
		-_mouse_delta.x * sway_pos_amount, -MAX_SWAY_POSITION, MAX_SWAY_POSITION
	)
	_target_sway_pos.y = clampf(
		_mouse_delta.y * sway_pos_amount, -MAX_SWAY_POSITION, MAX_SWAY_POSITION
	)
	_target_sway_pos.z = 0.0

	_current_sway_rot = MathUtils.damp_v3(
		_current_sway_rot, _target_sway_rot, SWAY_SMOOTH_SPEED, delta
	)
	_current_sway_pos = MathUtils.damp_v3(
		_current_sway_pos, _target_sway_pos, SWAY_SMOOTH_SPEED, delta
	)

	_mouse_delta = Vector2.ZERO

	# 2. Evaluate sprint & locomotion bob
	var is_sprinting: bool = false
	var horiz_speed: float = 0.0
	var is_on_floor: bool = true

	if is_instance_valid(_player):
		horiz_speed = Vector2(_player.velocity.x, _player.velocity.z).length()
		is_on_floor = _player.is_on_floor()

	if is_instance_valid(_locomotion):
		is_sprinting = _locomotion.sprint_active and horiz_speed > 1.5

	# Auto-cancel inspect / reload if player begins sprinting
	if is_sprinting:
		if state == AnimationState.INSPECTING:
			cancel_inspect()
		elif state == AnimationState.RELOADING:
			cancel_reload()

	# Sprint pose blending
	if is_sprinting and state != AnimationState.INSPECTING and state != AnimationState.RELOADING:
		state = AnimationState.SPRINTING
		_target_sprint_pos = sprint_pose_position
		_target_sprint_rot = sprint_pose_rotation
	else:
		if state == AnimationState.SPRINTING:
			state = AnimationState.IDLE
		_target_sprint_pos = Vector3.ZERO
		_target_sprint_rot = Vector3.ZERO

	_current_sprint_pos = MathUtils.damp_v3(_current_sprint_pos, _target_sprint_pos, 8.0, delta)
	_current_sprint_rot = MathUtils.damp_v3(_current_sprint_rot, _target_sprint_rot, 8.0, delta)

	# Locomotion bobbing
	if is_on_floor and horiz_speed > 0.1:
		if (
			state != AnimationState.SPRINTING
			and state != AnimationState.INSPECTING
			and state != AnimationState.RELOADING
		):
			state = AnimationState.WALKING
		var freq: float = sprint_bob_frequency if is_sprinting else walk_bob_frequency
		var amp_x: float = sprint_bob_amplitude_x if is_sprinting else walk_bob_amplitude_x
		var amp_y: float = sprint_bob_amplitude_y if is_sprinting else walk_bob_amplitude_y
		var roll_amp: float = sprint_bob_roll_amplitude if is_sprinting else walk_bob_roll_amplitude

		_bob_timer += delta * freq
		_target_bob_pos.x = sin(_bob_timer) * amp_x
		_target_bob_pos.y = absf(cos(_bob_timer)) * amp_y
		_target_bob_pos.z = 0.0

		_target_bob_rot.z = -sin(_bob_timer) * roll_amp
		_target_bob_rot.x = absf(cos(_bob_timer)) * (roll_amp * 0.5)
		_target_bob_rot.y = 0.0
	else:
		if state == AnimationState.WALKING:
			state = AnimationState.IDLE
		_idle_timer += delta * 2.0
		_target_bob_pos.x = sin(_idle_timer * 0.5) * 0.0015
		_target_bob_pos.y = sin(_idle_timer) * 0.0025
		_target_bob_pos.z = 0.0
		_target_bob_rot = Vector3.ZERO

	_current_bob_pos = MathUtils.damp_v3(_current_bob_pos, _target_bob_pos, 10.0, delta)
	_current_bob_rot = MathUtils.damp_v3(_current_bob_rot, _target_bob_rot, 10.0, delta)

	# 3. Apply final synthesized transform
	position = (
		rest_position
		+ _current_sway_pos
		+ _current_bob_pos
		+ _current_sprint_pos
		+ _inspect_pos
		+ _reload_pos
	)
	rotation = (
		rest_rotation
		+ _current_sway_rot
		+ _current_bob_rot
		+ _current_sprint_rot
		+ _inspect_rot
		+ _reload_rot
	)


## Begins procedural inspect sequence rotating viewmodel to display weapon details.
func inspect() -> bool:
	if state == AnimationState.INSPECTING:
		return false
	if is_instance_valid(_locomotion) and _locomotion.sprint_active:
		print("WeaponProceduralAnimator: Cannot inspect while sprinting.")
		return false
	if state == AnimationState.RELOADING:
		return false

	state = AnimationState.INSPECTING
	print("WeaponProceduralAnimator: Inspecting weapon.")
	_inspect_tween = Utilities.reset_tween_ext(self, _inspect_tween)
	if not is_instance_valid(_inspect_tween):
		state = AnimationState.IDLE
		return false

	# Stage 1: Rotate to show right receiver and chamber
	(
		_inspect_tween
		. tween_property(self, ^"_inspect_rot", Vector3(0.25, 0.55, -0.35), 0.55)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	_inspect_tween.parallel().tween_property(
		self, ^"_inspect_pos", Vector3(-0.04, 0.03, 0.06), 0.55
	)

	# Stage 2: Tilt up to inspect top rail and barrel
	(
		_inspect_tween
		. tween_property(self, ^"_inspect_rot", Vector3(-0.30, 0.20, 0.25), 0.55)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	_inspect_tween.parallel().tween_property(
		self, ^"_inspect_pos", Vector3(-0.02, 0.04, 0.04), 0.55
	)

	# Stage 3: Tilt to show left receiver markings
	(
		_inspect_tween
		. tween_property(self, ^"_inspect_rot", Vector3(0.15, -0.45, 0.30), 0.55)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	_inspect_tween.parallel().tween_property(self, ^"_inspect_pos", Vector3(0.03, 0.02, 0.05), 0.55)

	# Stage 4: Return smoothly to rest
	(
		_inspect_tween
		. tween_property(self, ^"_inspect_rot", Vector3.ZERO, 0.45)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	_inspect_tween.parallel().tween_property(self, ^"_inspect_pos", Vector3.ZERO, 0.45)
	_inspect_tween.tween_callback(_on_inspect_finished)
	return true


## Aborts an ongoing inspection animation immediately.
func cancel_inspect() -> void:
	if state != AnimationState.INSPECTING:
		return
	print("WeaponProceduralAnimator: Cancelling inspection sequence.")
	Utilities.safe_kill_tween(_inspect_tween)
	_inspect_tween = null
	state = AnimationState.IDLE
	if is_inside_tree():
		var snap_tween: Tween = create_tween()
		snap_tween.tween_property(self, ^"_inspect_rot", Vector3.ZERO, 0.15).set_trans(
			Tween.TRANS_SINE
		)
		snap_tween.parallel().tween_property(self, ^"_inspect_pos", Vector3.ZERO, 0.15)
	else:
		_inspect_pos = Vector3.ZERO
		_inspect_rot = Vector3.ZERO
	inspect_cancelled.emit()


## Plays procedural reload dip and return animation.
func play_reload(duration: float, on_complete: Callable = Callable()) -> bool:
	if is_instance_valid(_locomotion) and _locomotion.sprint_active:
		print("WeaponProceduralAnimator: Cannot reload while sprinting.")
		return false

	cancel_inspect()
	state = AnimationState.RELOADING
	print("WeaponProceduralAnimator: Playing procedural reload motion.")
	_reload_tween = Utilities.reset_tween_ext(self, _reload_tween)
	if not is_instance_valid(_reload_tween):
		state = AnimationState.IDLE
		return false

	var half_dur: float = duration * 0.5
	(
		_reload_tween
		. tween_property(self, ^"_reload_pos", reload_pose_position, half_dur)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	_reload_tween.parallel().tween_property(self, ^"_reload_rot", reload_pose_rotation, half_dur)

	(
		_reload_tween
		. tween_property(self, ^"_reload_pos", Vector3.ZERO, half_dur)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	_reload_tween.parallel().tween_property(self, ^"_reload_rot", Vector3.ZERO, half_dur)
	_reload_tween.tween_callback(
		func() -> void:
			state = AnimationState.IDLE
			if on_complete.is_valid():
				on_complete.call()
	)
	return true


## Cancels active reload animation (e.g. when sprinting interrupts reload).
func cancel_reload() -> void:
	if state != AnimationState.RELOADING:
		return
	print("WeaponProceduralAnimator: Cancelling active reload sequence.")
	Utilities.safe_kill_tween(_reload_tween)
	_reload_tween = null
	state = AnimationState.IDLE
	if is_inside_tree():
		var snap_tween: Tween = create_tween()
		snap_tween.tween_property(self, ^"_reload_pos", Vector3.ZERO, 0.15).set_trans(
			Tween.TRANS_SINE
		)
		snap_tween.parallel().tween_property(self, ^"_reload_rot", Vector3.ZERO, 0.15)
	else:
		_reload_pos = Vector3.ZERO
		_reload_rot = Vector3.ZERO


## Applies instantaneous recoil kick impulse to weapon transform.
func apply_recoil(recoil_pos: Vector3, recoil_rot: Vector3) -> void:
	_current_sway_pos += recoil_pos
	_current_sway_rot += recoil_rot


## Resolves and caches references to the player root and locomotion component.
func _resolve_player_references() -> void:
	if is_instance_valid(_player) and is_instance_valid(_locomotion):
		return

	var p_node: Node = NodeQuery.find_ancestor_in_group(self, &"player")
	if is_instance_valid(p_node) and p_node is CharacterBody3D:
		_player = p_node as CharacterBody3D
		var loc: Variant = _player.get(&"locomotion_component")
		if loc is PlayerLocomotionComponent:
			_locomotion = loc


## Resets inspect state upon tween completion.
func _on_inspect_finished() -> void:
	state = AnimationState.IDLE
	_inspect_pos = Vector3.ZERO
	_inspect_rot = Vector3.ZERO
	inspect_completed.emit()
