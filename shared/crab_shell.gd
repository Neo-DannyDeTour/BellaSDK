## Animatable falling shell piece following a quadratic Bezier trajectory.
class_name CrabShell
extends AnimatableBody3D

## Distance in meters along local Y axis to find spawn point.
@export var drop_distance: float = 100.0

## Time in seconds required for shell to complete descent.
@export var travel_time: float = 4.0

## Time in seconds to wait after trigger activation before dropping.
@export var drop_delay: float = 0.5

## Peak elevation added to mid-point along local Z axis.
@export var arc_height: float = 20.0

## Distance from landing spot where smoke trail activates.
@export var smoke_distance_threshold: float = 20.0

## Smoke particle system instance attached to the shell.
@export var smoke_trail: GPUParticles3D

## Elapsed time tracker during falling sequence.
var _current_time: float = 0.0

## Active state flag indicating whether shell is falling.
var _is_falling: bool = false

## Safety lock preventing duplicate drop triggers.
var _has_triggered: bool = false

## Cached editor transform representing final landed position.
var _target_transform: Transform3D

## World position where shell spawns high in air.
var _start_pos: Vector3

## Mid-point control position for calculating arc trajectory.
var _control_pos: Vector3


## Disables physics processing and caches initial landing transform.
func _ready() -> void:
	print("CrabShell: Initializing crab shell set piece.")
	set_physics_process(false)
	visible = false
	_target_transform = global_transform

	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false
		smoke_trail.local_coords = false
		smoke_trail.top_level = true


## Initiates drop sequence, applying configured delay.
func trigger_drop() -> void:
	if _has_triggered:
		return

	_has_triggered = true
	print("CrabShell: Triggered drop sequence with delay: ", drop_delay)
	if drop_delay > 0.0:
		await get_tree().create_timer(drop_delay).timeout
	_start_falling()


## Calculates spawn and control points and starts physics process.
func _start_falling() -> void:
	print("CrabShell: Spawning and beginning descent.")
	_current_time = 0.0

	var target_pos: Vector3 = _target_transform.origin
	var clean_basis: Basis = _target_transform.basis.orthonormalized()

	_start_pos = target_pos + (clean_basis.y * drop_distance)
	var mid_point: Vector3 = _start_pos.lerp(target_pos, 0.5)
	_control_pos = mid_point + (clean_basis.z * arc_height)

	global_transform = Transform3D(clean_basis, _start_pos)
	visible = true

	if is_instance_valid(smoke_trail):
		smoke_trail.global_position = _start_pos
		smoke_trail.visible = true
		smoke_trail.emitting = false

	_is_falling = true
	set_physics_process(true)


## Interpolates shell position along quadratic Bezier curve via [MathUtils].
func _physics_process(delta: float) -> void:
	if not _is_falling:
		return

	_current_time += delta
	var t: float = clampf(_current_time / travel_time, 0.0, 1.0)

	if t >= 1.0:
		print("CrabShell: Shell landed at destination.")
		_is_falling = false
		set_physics_process(false)
		global_transform = _target_transform

		if is_instance_valid(smoke_trail):
			smoke_trail.global_position = global_transform.origin
		_on_impact()
		return

	var new_pos: Vector3 = MathUtils.quadratic_bezier(
		_start_pos, _control_pos, _target_transform.origin, t
	)
	global_transform = Transform3D(_target_transform.basis, new_pos)

	if is_instance_valid(smoke_trail):
		smoke_trail.global_position = new_pos
		if not smoke_trail.emitting:
			var dist_sq: float = new_pos.distance_squared_to(_target_transform.origin)
			if dist_sq <= (smoke_distance_threshold * smoke_distance_threshold):
				print("CrabShell: Within threshold. Activating smoke trail.")
				smoke_trail.emitting = true


## Deactivates particle emitter upon landing impact.
func _on_impact() -> void:
	print("CrabShell: Shell impact completed.")
	if is_instance_valid(smoke_trail):
		smoke_trail.emitting = false
