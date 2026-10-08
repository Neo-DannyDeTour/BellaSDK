## Heavy supply canister that glides horizontally, stabilizes via thrusters, and deploys ammo.
class_name SupplyShell
extends AnimatableBody3D

@export_group("Trajectory")
## Distance in meters along approach heading where canister spawns.
@export var approach_distance: float = 70.0

## Altitude elevation in meters maintained during horizontal flight.
@export var drop_height: float = 24.0

## Total travel time in seconds from spawn to touchdown.
@export var travel_time: float = 7.5

## Delay in seconds before descent starts after trigger activation.
@export var drop_delay: float = 0.5

@export_group("Thruster Stabilization")
## Maximum thruster gimbal deflection angle in degrees.
@export var thruster_gimbal_angle: float = 14.0

## Four downward-pointing rocket stabilizer mount nodes.
@export var thrusters: Array[Node3D] = []

## Exhaust flame particle emitters attached to thrusters.
@export var thruster_particles: Array[GPUParticles3D] = []

@export_group("Payload Cargo")
## Packed scene instantiated for ground ammunition pickups.
@export var ammo_box_scene: PackedScene = null

## Fallback path loaded dynamically if no packed scene is assigned in the inspector.
@export_file("*.tscn") var default_ammo_box_path: String = "res://assets/weapons/ammo_box.tscn"

## Total count of ammo crates deployed upon touchdown.
@export var ammo_spawn_count: int = 2

@export_group("Landing Smoke & FX")
## Ground smoke emitter active during vertical touchdown.
@export var landing_smoke: GPUParticles3D

## Duration in seconds landing smoke remains active after touchdown.
@export var landing_smoke_duration: float = 2.5

## Radial dust burst particle emitter triggered on ground impact.
@export var impact_dust: GPUParticles3D

## Flying rock and debris particle emitter triggered on landing.
@export var impact_debris: GPUParticles3D

@export_group("Landing Settings")
## Peak camera screenshake trauma intensity on landing.
@export_range(0.0, 1.0) var shake_intensity: float = 0.75

## Duration in seconds of camera screenshake decay.
@export var shake_duration: float = 1.2

## Spawns post-process radial shockwave on impact if available.
@export var trigger_shockwave_effect: bool = true

## Elapsed flight time tracker during active descent.
var _current_time: float = 0.0

## State flag indicating whether canister is currently airborne.
var _is_flying: bool = false

## Safety latch preventing duplicate activation triggers.
var _has_triggered: bool = false

## Destination transform captured from editor placement.
var _target_transform: Transform3D

## High-altitude trajectory start point.
var _p0: Vector3

## Horizontal glide tangent control point.
var _p1: Vector3

## Vertical flare approach control point.
var _p2: Vector3

## Final ground destination point.
var _p3: Vector3


## Configures resting transforms and prepositions canister.
func _ready() -> void:
	print("SupplyShell: Initializing supply canister set piece.")
	set_physics_process(false)
	visible = false
	_target_transform = global_transform

	var forward_dir: Vector3 = -_target_transform.basis.z.normalized()
	_p3 = _target_transform.origin
	_p0 = _p3 - (forward_dir * approach_distance) + (Vector3.UP * drop_height)
	_p1 = _p0 + (forward_dir * (approach_distance * 0.55))
	_p2 = _p3 + (Vector3.UP * (drop_height * 0.45))

	global_transform = Transform3D(_target_transform.basis, _p0)
	reset_physics_interpolation()

	for emitter: GPUParticles3D in thruster_particles:
		if is_instance_valid(emitter):
			emitter.emitting = false

	if is_instance_valid(landing_smoke):
		landing_smoke.emitting = false
		landing_smoke.local_coords = false

	if is_instance_valid(impact_dust):
		impact_dust.emitting = false
		impact_dust.one_shot = true

	if is_instance_valid(impact_debris):
		impact_debris.emitting = false
		impact_debris.one_shot = true


## Starts drop countdown before invoking [method _start_flight].
func trigger_drop() -> void:
	if _has_triggered:
		return

	_has_triggered = true
	print("SupplyShell: Triggering slow cargo descent with delay: ", drop_delay)
	if drop_delay > 0.0:
		await get_tree().create_timer(drop_delay).timeout
	_start_flight()


## Teleports canister to start vector and ignites thrusters.
func _start_flight() -> void:
	print("SupplyShell: Commencing horizontal approach and firing thrusters.")
	_current_time = 0.0
	global_transform = Transform3D(_target_transform.basis, _p0)
	reset_physics_interpolation()
	visible = true

	for emitter: GPUParticles3D in thruster_particles:
		if is_instance_valid(emitter):
			emitter.emitting = true

	_is_flying = true
	set_physics_process(true)


## Advances trajectory interpolation and updates rocket gimbals.
func _physics_process(delta: float) -> void:
	if not _is_flying:
		return

	_current_time += delta
	var t: float = clampf(_current_time / travel_time, 0.0, 1.0)

	if t >= 0.7 and is_instance_valid(landing_smoke) and not landing_smoke.emitting:
		print("SupplyShell: Beginning vertical descent. Igniting landing smoke.")
		landing_smoke.emitting = true

	if t >= 1.0:
		print("SupplyShell: Soft touchdown completed at destination.")
		_is_flying = false
		set_physics_process(false)
		global_transform = _target_transform
		reset_physics_interpolation()
		_on_touchdown()
		return

	var new_pos: Vector3 = _sample_cubic_bezier(_p0, _p1, _p2, _p3, t)
	var pitch_tilt: float = deg_to_rad(lerpf(14.0, 0.0, smoothstep(0.4, 0.95, t)))
	var tilted_basis: Basis = _target_transform.basis.rotated(
		_target_transform.basis.x.normalized(), pitch_tilt
	)
	global_transform = Transform3D(tilted_basis, new_pos)

	_update_thruster_stabilization(delta)


## Samples 3D cubic Bezier trajectory for given unit progress.
func _sample_cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	var tt: float = t * t
	var uu: float = u * u
	var uuu: float = uu * u
	var ttt: float = tt * t
	return (uuu * p0) + (3.0 * uu * t * p1) + (3.0 * u * tt * p2) + (ttt * p3)


## Gimbals rocket thrusters dynamically to simulate stabilization.
func _update_thruster_stabilization(_delta: float) -> void:
	var thruster_count: int = thrusters.size()
	for i: int in range(thruster_count):
		var thruster: Node3D = thrusters[i]
		if not is_instance_valid(thruster):
			continue

		var phase: float = float(i) * 1.57079
		var pitch: float = deg_to_rad(sin((_current_time * 6.5) + phase) * thruster_gimbal_angle)
		var roll: float = deg_to_rad(cos((_current_time * 5.2) + phase) * thruster_gimbal_angle)
		thruster.rotation = Vector3(pitch, 0.0, roll)


## Deactivates rockets, triggers landing FX, and deploys ammo.
func _on_touchdown() -> void:
	print("SupplyShell: Touchdown confirmed. Deploying cargo payload.")
	for emitter: GPUParticles3D in thruster_particles:
		if is_instance_valid(emitter):
			emitter.emitting = false

	for thruster: Node3D in thrusters:
		if is_instance_valid(thruster):
			thruster.rotation = Vector3.ZERO

	_trigger_impact_fx()
	_trigger_screenshake()
	_deploy_ammo_cargo()

	if is_instance_valid(landing_smoke):
		print("SupplyShell: Retaining landing smoke for ", landing_smoke_duration, " seconds.")
		get_tree().create_timer(landing_smoke_duration).timeout.connect(
			func() -> void:
				print("SupplyShell: Shutting off landing ground smoke.")
				if is_instance_valid(landing_smoke):
					landing_smoke.emitting = false
		)


## Instantiates configured [AmmoBox] crates around landing zone.
func _deploy_ammo_cargo() -> void:
	var scene_to_spawn: PackedScene = ammo_box_scene
	if not is_instance_valid(scene_to_spawn) and ResourceLoader.exists(default_ammo_box_path):
		scene_to_spawn = load(default_ammo_box_path) as PackedScene

	if not is_instance_valid(scene_to_spawn):
		print("SupplyShell: ammo_box_scene not assigned or found. Cargo skipped.")
		return

	print("SupplyShell: Spawning ", ammo_spawn_count, " ammunition boxes.")
	var step_angle: float = TAU / float(maxi(1, ammo_spawn_count))
	var spawn_radius: float = 1.35

	for i: int in range(ammo_spawn_count):
		var raw_box: Node = scene_to_spawn.instantiate()
		var ammo_crate: Node3D = raw_box as Node3D
		if not is_instance_valid(ammo_crate):
			raw_box.queue_free()
			continue

		var angle: float = float(i) * step_angle
		var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 0.15, sin(angle) * spawn_radius)
		get_tree().current_scene.add_child(ammo_crate)
		ammo_crate.global_position = _target_transform.origin + offset

		if ammo_crate is AmmoBox:
			var box: AmmoBox = ammo_crate as AmmoBox
			box.ammo_type = (
				AmmoBox.AmmoArchetype.REVOLVER if i % 2 == 0 else AmmoBox.AmmoArchetype.SHOTGUN
			)
			print(
				"SupplyShell: Deployed AmmoBox [",
				box.ammo_type,
				"] at ",
				ammo_crate.global_position
			)


## Activates one-shot ground dust and stone debris particles.
func _trigger_impact_fx() -> void:
	print("SupplyShell: Firing landing impact visual effects.")
	if is_instance_valid(impact_dust):
		impact_dust.global_position = _target_transform.origin
		impact_dust.restart()
		impact_dust.emitting = true

	if is_instance_valid(impact_debris):
		impact_debris.global_position = _target_transform.origin
		impact_debris.restart()
		impact_debris.emitting = true


## Requests camera trauma via [signal Events.screenshake_requested].
func _trigger_screenshake() -> void:
	print("SupplyShell: Requesting landing shake trauma -> ", shake_intensity)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal(&"screenshake_requested"):
			events.emit_signal(&"screenshake_requested", shake_intensity, shake_duration)

		if trigger_shockwave_effect and events.has_signal(&"shockwave_requested"):
			events.emit_signal(&"shockwave_requested", _target_transform.origin, 5.0, 2.5)
