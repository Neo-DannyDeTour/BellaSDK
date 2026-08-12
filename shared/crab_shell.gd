extends AnimatableBody3D
class_name CrabShell

## Distance in meters to move backward along the shell's local Y (Up) axis to find the spawn point.
@export var drop_distance: float = 100.0

## Time in seconds required for the shell to complete its descent.
@export var travel_time: float = 4.0

## Time in seconds to wait after trigger activation before dropping.
@export var drop_delay: float = 0.5

## Peak elevation added to the mid-point of the drop arc (applied along the local Z axis).
@export var arc_height: float = 20.0

## Distance in meters from the landing spot where the smoke trail activates.
@export var smoke_distance_threshold: float = 20.0

## Smoke particle system instance attached to the shell.
@export var smoke_trail: GPUParticles3D

## Elapsed time tracker during the falling sequence.
var _current_time: float = 0.0

## Active state flag indicating whether the shell is falling.
var _is_falling: bool = false

## Safety lock to prevent trigger volumes from firing the drop sequence multiple times.
var _has_triggered: bool = false

## Cached editor transform representing the final landed position and angle.
var _target_transform: Transform3D

## World position where the shell spawns high in the air.
var _start_pos: Vector3

## Mid-point control position for calculating the arc trajectory.
var _control_pos: Vector3


func _ready() -> void:
	print("CrabShell initializing: Caching target transform and awaiting trigger.")
	set_physics_process(false)
	visible = false
	_target_transform = global_transform

	if smoke_trail:
		smoke_trail.emitting = false
		smoke_trail.local_coords = false
		smoke_trail.top_level = true


func trigger_drop() -> void:
	if _has_triggered:
		return

	_has_triggered = true
	print("CrabShell triggered: Starting drop delay of ", drop_delay, " seconds.")

	if drop_delay > 0.0:
		await get_tree().create_timer(drop_delay).timeout
	_start_falling()


func _start_falling() -> void:
	print("CrabShell falling: Spawning and starting trajectory.")
	_current_time = 0.0

	var target_pos: Vector3 = _target_transform.origin
	var clean_basis: Basis = _target_transform.basis.orthonormalized()

	_start_pos = target_pos + (clean_basis.y * drop_distance)

	var mid_point: Vector3 = _start_pos.lerp(target_pos, 0.5)
	_control_pos = mid_point + (clean_basis.z * arc_height)

	# Atomic transform assignment prevents physics snapping on spawn
	global_transform = Transform3D(clean_basis, _start_pos)
	visible = true

	if smoke_trail:
		smoke_trail.global_position = _start_pos
		smoke_trail.visible = true
		smoke_trail.emitting = false

	_is_falling = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _is_falling:
		return

	_current_time += delta

	# clampf protects against math overshoots dropping frames
	var t: float = clampf(_current_time / travel_time, 0.0, 1.0)

	if t >= 1.0:
		print("CrabShell landing: Reached target destination.")
		_is_falling = false
		set_physics_process(false)
		global_transform = _target_transform

		if smoke_trail:
			smoke_trail.global_position = global_transform.origin
		_on_impact()
		return

	var new_pos: Vector3 = _calculate_bezier(t)

	# Atomic transform assignment prevents physics snapping during flight
	global_transform = Transform3D(_target_transform.basis, new_pos)

	if smoke_trail:
		smoke_trail.global_position = new_pos

		if not smoke_trail.emitting:
			var dist: float = new_pos.distance_to(_target_transform.origin)
			if dist <= smoke_distance_threshold:
				print(
					"CrabShell falling: Reached ",
					smoke_distance_threshold,
					"m threshold. Activating smoke."
				)
				smoke_trail.emitting = true


func _calculate_bezier(t: float) -> Vector3:
	var target_pos: Vector3 = _target_transform.origin
	var q0: Vector3 = _start_pos.lerp(_control_pos, t)
	var q1: Vector3 = _control_pos.lerp(target_pos, t)
	return q0.lerp(q1, t)


func _on_impact() -> void:
	print("CrabShell impact: Sequence finished, deactivating smoke trail.")
	if smoke_trail:
		smoke_trail.emitting = false
