## Animatable shell piece that follows a Bezier arc and triggers impact FX.
## Drops into place, deploys flight trails, and creates landing debris.
class_name CrabShell
extends AnimatableBody3D

@export_group("Trajectory")
## Distance in meters along local Y axis to find spawn point.
@export var drop_distance: float = 100.0

## Time in seconds required for shell to complete descent.
@export var travel_time: float = 4.0

## Time in seconds to wait after trigger activation before dropping.
@export var drop_delay: float = 0.5

## Peak elevation added to mid-point along local Z axis.
@export var arc_height: float = 20.0

@export_group("Visual FX Nodes")
## Smoke particle system instance attached to the shell top.
@export var top_smoke: GPUParticles3D

## Camera-facing ribbon [Trail3D] following shell descent.
@export var flight_trail: Trail3D

## Radial dust burst particle emitter triggered on ground impact.
@export var impact_dust: GPUParticles3D

## Flying rock and gravel debris particle emitter triggered on landing.
@export var impact_debris: GPUParticles3D

## Backward-compatible alias for smoke particles.
@export var smoke_trail: GPUParticles3D:
	get:
		return top_smoke
	set(value):
		top_smoke = value

@export_group("Impact Settings")
## Keep top smoke active after landing to simulate hot wreckage.
@export var smoke_after_impact: bool = true

## Peak screenshake trauma intensity requested from camera.
@export_range(0.0, 1.0) var shake_intensity: float = 0.85

## Duration in seconds of camera screenshake decay on landing.
@export var shake_duration: float = 1.2

## Spawns post-process radial distortion shockwave on impact if available.
@export var trigger_shockwave_effect: bool = true

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


## Caches transform, prepositions shell, and resets physics interpolation.
func _ready() -> void:
	print("CrabShell: Initializing crab shell set piece.")
	set_physics_process(false)
	visible = false
	_target_transform = global_transform

	var clean_basis: Basis = _target_transform.basis.orthonormalized()
	_start_pos = _target_transform.origin + (clean_basis.y * drop_distance)
	var mid_point: Vector3 = _start_pos.lerp(_target_transform.origin, 0.5)
	_control_pos = mid_point + (clean_basis.z * arc_height)

	global_transform = Transform3D(clean_basis, _start_pos)
	reset_physics_interpolation()

	if is_instance_valid(top_smoke):
		top_smoke.emitting = false
		top_smoke.local_coords = false

	if is_instance_valid(flight_trail):
		flight_trail.stop_trail()
		flight_trail.clear_trail()

	if is_instance_valid(impact_dust):
		impact_dust.emitting = false
		impact_dust.one_shot = true
		impact_dust.local_coords = false

	if is_instance_valid(impact_debris):
		impact_debris.emitting = false
		impact_debris.one_shot = true
		impact_debris.local_coords = false


## Initiates drop sequence with configured delay before calling [method _start_falling].
func trigger_drop() -> void:
	if _has_triggered:
		return

	_has_triggered = true
	print("CrabShell: Triggered drop sequence with delay: ", drop_delay)
	if drop_delay > 0.0:
		await get_tree().create_timer(drop_delay).timeout
	_start_falling()


## Teleports shell to start, activates trail, and begins physics process.
func _start_falling() -> void:
	print("CrabShell: Spawning and beginning descent.")
	_current_time = 0.0

	var clean_basis: Basis = _target_transform.basis.orthonormalized()
	global_transform = Transform3D(clean_basis, _start_pos)
	reset_physics_interpolation()
	visible = true

	if is_instance_valid(flight_trail):
		flight_trail.clear_trail()
		flight_trail.start_trail()

	if is_instance_valid(top_smoke):
		top_smoke.emitting = false

	_is_falling = true
	set_physics_process(true)


## Interpolates trajectory along Bezier curve and detects ground impact.
func _physics_process(delta: float) -> void:
	if not _is_falling:
		return

	_current_time += delta
	var t: float = clampf(_current_time / travel_time, 0.0, 1.0)

	if t >= 1.0:
		# print("CrabShell: Shell landed at destination.")
		_is_falling = false
		set_physics_process(false)
		global_transform = _target_transform
		reset_physics_interpolation()
		_on_impact()
		return

	var new_pos: Vector3 = MathUtils.quadratic_bezier(
		_start_pos, _control_pos, _target_transform.origin, t
	)
	global_transform = Transform3D(_target_transform.basis, new_pos)


## Triggers impact dust, flying debris particles, and camera screen shake.
func _on_impact() -> void:
	print("CrabShell: Shell impact completed. Triggering effects.")
	if is_instance_valid(flight_trail):
		flight_trail.stop_trail()

	_trigger_impact_particles()
	_trigger_camera_shake()

	if is_instance_valid(top_smoke):
		if smoke_after_impact:
			top_smoke.emitting = true
			print("CrabShell: Wreckage smoke active at impact site.")
		else:
			top_smoke.emitting = false


## Activates one-shot ground dust and stone debris particle emitters.
func _trigger_impact_particles() -> void:
	print("CrabShell: Firing impact dust and physical debris bursts.")
	if is_instance_valid(impact_dust):
		impact_dust.global_position = _target_transform.origin
		impact_dust.restart()
		impact_dust.emitting = true

	if is_instance_valid(impact_debris):
		impact_debris.global_position = _target_transform.origin
		impact_debris.restart()
		impact_debris.emitting = true


## Emits camera shake event to [signal Events.screenshake_requested].
func _trigger_camera_shake() -> void:
	print("CrabShell: Requesting screenshake: ", shake_intensity, " duration: ", shake_duration)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal(&"screenshake_requested"):
			events.emit_signal(&"screenshake_requested", shake_intensity, shake_duration)

		if trigger_shockwave_effect and events.has_signal(&"shockwave_requested"):
			print("CrabShell: Requesting ScreenEffectsCore shockwave distortion.")
			events.emit_signal(&"shockwave_requested", _target_transform.origin, 6.0, 3.0)
