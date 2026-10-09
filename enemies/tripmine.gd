## Directional trip mine armed with scanning laser, proximity blast, and trauma impulse.
class_name TripMine
extends Node3D

## Motion trajectory modes governing laser sweep patterns.
enum MotionMode {
	STATIC,
	VERTICAL,
	HORIZONTAL,
	CIRCLE,
	PYRAMID,
	SQUARE,
}

## Emitted when the mine explodes. Passes global detonation position [param position].
signal detonated(position: Vector3)

## Emitted when the laser state changes. Passes active state [param is_active].
signal laser_state_changed(is_active: bool)

## Calibrated damage slope reduction factor calculated across a 3 meter distance.
const DAMAGE_FALLOFF_PER_METER: float = 66.6667

## Current active laser movement pattern managed from inspector.
@export var motion_mode: MotionMode = MotionMode.STATIC

## Angular movement frequency scalar in radians per second.
@export_range(0.1, 10.0, 0.1) var motion_speed: float = 2.0

## Maximum horizontal sweep half-angle in degrees.
@export_range(0.0, 85.0, 0.5) var sweep_horizontal_deg: float = 30.0

## Maximum vertical sweep half-angle in degrees.
@export_range(0.0, 85.0, 0.5) var sweep_vertical_deg: float = 30.0

## Maximum operational reach distance of the laser beam in meters.
@export_range(1.0, 100.0, 1.0) var max_laser_range: float = 25.0

## Distance in meters beyond which all raycasts and sweep logic go to sleep.
@export_range(10.0, 100.0, 1.0) var lod_max_distance: float = 40.0

## Maximum damage dealt at ground zero (zero distance from mine).
@export var max_damage: float = 400.0

## Reference damage dealt when the victim is exactly three meters away.
@export var damage_at_three_meters: float = 200.0

## Maximum blast radius in meters where explosion damage applies.
@export var blast_radius: float = 6.0

## Maximum trauma impulse emitted to screenshake manager upon detonation.
@export_range(0.1, 2.0, 0.05) var peak_screenshake_trauma: float = 1.0

## Swivel node pitching and yawing the laser components.
@onready var swivel_pivot: Node3D = $SwivelPivot

## Raycast detecting beam obstructions and player intrusion.
@onready var laser_ray_cast: RayCast3D = $SwivelPivot/LaserRayCast

## Cylindrical mesh instance rendering the laser shader.
@onready var laser_beam_mesh: MeshInstance3D = $SwivelPivot/LaserBeamMesh

## Small glowing point rendered at the laser impact surface.
@onready var laser_dot_mesh: MeshInstance3D = $SwivelPivot/LaserDotMesh

## Visual base housing of the trip mine device.
@onready var base_mesh: MeshInstance3D = $BaseMesh

## Area node querying damageable targets caught in the blast radius.
@onready var blast_area: Area3D = $BlastArea

## Container holding all explosion particle systems and lights.
@onready var explosion_fx: Node3D = $ExplosionFX

## Fire explosion particle system.
@onready var fire_particles: GPUParticles3D = $ExplosionFX/FireParticles

## Smoke plume particle system.
@onready var smoke_particles: GPUParticles3D = $ExplosionFX/SmokeParticles

## High velocity sparks particle system.
@onready var sparks_particles: GPUParticles3D = $ExplosionFX/SparksParticles

## Shattered debris particle system.
@onready var debris_particles: GPUParticles3D = $ExplosionFX/DebrisParticles

## Dynamic explosion omni light source.
@onready var explosion_light: OmniLight3D = $ExplosionFX/ExplosionLight

## Spatial audio player triggering explosion sound effects.
@onready var explosion_audio: AudioStreamPlayer3D = $ExplosionFX/ExplosionAudio

## Internal accumulated elapsed time for procedural motion generation.
var _motion_timer: float = 0.0

## State flag preventing multiple detonation executions.
var _is_detonated: bool = false

## Local unique duplicate of the laser cylinder mesh resource.
var _unique_cylinder_mesh: CylinderMesh = null

## Distance check interval timer to minimize Vector3 distance calls.
var _distance_check_timer: float = 0.0

## Cached flag indicating whether player is currently within active LOD range.
var _is_within_lod_range: bool = true


## Caches node references, initializes unique meshes, and arms the trip mine.
func _ready() -> void:
	print("TripMine: Initializing trip mine at ", global_position)
	_setup_laser_geometry()
	_setup_blast_area()
	laser_state_changed.emit(true)


## Advances laser sweep trajectory and performs collision detection checks.
func _physics_process(delta: float) -> void:
	if _is_detonated:
		return

	_distance_check_timer += delta
	if _distance_check_timer >= 0.25:
		_distance_check_timer = 0.0
		_update_distance_lod()

	if not _is_within_lod_range:
		return

	_update_laser_trajectory(delta)
	_update_beam_geometry()
	_check_laser_trigger()


## Toggles processing state based on player proximity to conserve frame rate.
func _update_distance_lod() -> void:
	var player_dist: float = _resolve_player_distance()
	_is_within_lod_range = player_dist <= lod_max_distance
	laser_ray_cast.enabled = _is_within_lod_range


## Duplicates cylinder mesh to allow independent per-instance height updates.
func _setup_laser_geometry() -> void:
	print("TripMine: Configuring unique laser geometry and materials.")
	if is_instance_valid(laser_beam_mesh) and laser_beam_mesh.mesh is CylinderMesh:
		_unique_cylinder_mesh = laser_beam_mesh.mesh.duplicate() as CylinderMesh
		laser_beam_mesh.mesh = _unique_cylinder_mesh

	laser_ray_cast.target_position = Vector3(0.0, 0.0, -max_laser_range)
	laser_ray_cast.collision_mask = (CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER)


## Configures the blast collision shape radius based on [member blast_radius].
func _setup_blast_area() -> void:
	print("TripMine: Setting up blast radius: ", blast_radius, " meters.")
	var col_shape: CollisionShape3D = blast_area.get_node_or_null("BlastShape") as CollisionShape3D
	if is_instance_valid(col_shape) and col_shape.shape is SphereShape3D:
		var sphere: SphereShape3D = col_shape.shape.duplicate() as SphereShape3D
		sphere.radius = blast_radius
		col_shape.shape = sphere

	blast_area.collision_mask = (CollisionLayers.MASK_PLAYER | CollisionLayers.MASK_ENEMIES)


## Computes angular sweep offsets according to selected [member motion_mode].
func _update_laser_trajectory(delta: float) -> void:
	if motion_mode == MotionMode.STATIC:
		swivel_pivot.rotation = Vector3.ZERO
		return

	_motion_timer += delta * motion_speed
	var angles: Vector2 = _calculate_motion_angles(_motion_timer)
	swivel_pivot.rotation = Vector3(angles.x, angles.y, 0.0)


## Calculates procedural pitch and yaw angles from current motion time step.
func _calculate_motion_angles(time_step: float) -> Vector2:
	var pitch_rad: float = deg_to_rad(sweep_vertical_deg)
	var yaw_rad: float = deg_to_rad(sweep_horizontal_deg)

	match motion_mode:
		MotionMode.VERTICAL:
			return Vector2(sin(time_step) * pitch_rad, 0.0)
		MotionMode.HORIZONTAL:
			return Vector2(0.0, sin(time_step) * yaw_rad)
		MotionMode.CIRCLE:
			return Vector2(sin(time_step) * pitch_rad, cos(time_step) * yaw_rad)
		MotionMode.PYRAMID:
			return _sample_diamond_trajectory(time_step, pitch_rad, yaw_rad)
		MotionMode.SQUARE:
			return _sample_square_trajectory(time_step, pitch_rad, yaw_rad)
		_:
			return Vector2.ZERO


## Samples a 4-vertex diamond perimeter sweep path for pyramid scanning.
func _sample_diamond_trajectory(time_step: float, max_p: float, max_y: float) -> Vector2:
	var phase: float = fmod(time_step, TAU) / TAU * 4.0
	var step_idx: int = int(phase)
	var frac: float = phase - float(step_idx)

	match step_idx:
		0:
			return Vector2(lerpf(max_p, 0.0, frac), lerpf(0.0, max_y, frac))
		1:
			return Vector2(lerpf(0.0, -max_p, frac), lerpf(max_y, 0.0, frac))
		2:
			return Vector2(lerpf(-max_p, 0.0, frac), lerpf(0.0, -max_y, frac))
		3:
			return Vector2(lerpf(0.0, max_p, frac), lerpf(-max_y, 0.0, frac))
		_:
			return Vector2.ZERO


## Samples a 4-edge rectangular perimeter sweep path for box scanning.
func _sample_square_trajectory(time_step: float, max_p: float, max_y: float) -> Vector2:
	var phase: float = fmod(time_step, TAU) / TAU * 4.0
	var step_idx: int = int(phase)
	var frac: float = phase - float(step_idx)

	match step_idx:
		0:
			return Vector2(-max_p, lerpf(-max_y, max_y, frac))
		1:
			return Vector2(lerpf(-max_p, max_p, frac), max_y)
		2:
			return Vector2(max_p, lerpf(max_y, -max_y, frac))
		3:
			return Vector2(lerpf(max_p, -max_p, frac), -max_y)
		_:
			return Vector2.ZERO


## Updates laser cylinder length, position, and shader segment uniform.
func _update_beam_geometry() -> void:
	var current_length: float = max_laser_range
	if laser_ray_cast.is_colliding():
		var hit_pt: Vector3 = laser_ray_cast.get_collision_point()
		current_length = swivel_pivot.global_position.distance_to(hit_pt)
		laser_dot_mesh.visible = true
		laser_dot_mesh.position = Vector3(0.0, 0.0, -current_length)
	else:
		laser_dot_mesh.visible = false

	if is_instance_valid(_unique_cylinder_mesh):
		_unique_cylinder_mesh.height = current_length

	laser_beam_mesh.position = Vector3(0.0, 0.0, -current_length * 0.5)
	laser_beam_mesh.set_instance_shader_parameter(&"segment_length", current_length)


## Queries raycast collider to detect player presence and trigger detonation.
func _check_laser_trigger() -> void:
	if not laser_ray_cast.is_colliding():
		return

	var collider: Object = laser_ray_cast.get_collider()
	if _is_player_target(collider):
		print("TripMine: Laser tripped by player collider: ", collider)
		detonate()


## Verifies whether detected collider belongs to player actor or group.
func _is_player_target(collider: Object) -> bool:
	if not is_instance_valid(collider):
		return false

	var target_node: Node = collider as Node
	if target_node == null:
		return false

	if target_node.is_in_group(&"player"):
		return true

	var parent_node: Node = target_node.get_parent()
	if parent_node != null and parent_node.is_in_group(&"player"):
		return true

	for child: Node in target_node.get_children():
		if child is HealthComponent and (child as HealthComponent).is_player_health:
			return true

	return false


## Triggers explosion, deals radial damage, emits screenshake, and clears mine.
func detonate() -> void:
	if _is_detonated:
		return

	_is_detonated = true
	print("TripMine: Detonating at ", global_position)
	set_physics_process(false)
	detonated.emit(global_position)
	laser_state_changed.emit(false)

	base_mesh.visible = false
	laser_beam_mesh.visible = false
	laser_dot_mesh.visible = false

	var player_distance: float = _resolve_player_distance()
	_apply_blast_damage()
	_dispatch_screenshake(player_distance)
	_trigger_explosion_effects()


## Measures spatial distance from explosion center to the active player.
func _resolve_player_distance() -> float:
	var player_nodes: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not player_nodes.is_empty() and player_nodes[0] is Node3D:
		return global_position.distance_to((player_nodes[0] as Node3D).global_position)

	var active_cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(active_cam):
		return global_position.distance_to(active_cam.global_position)

	return blast_radius


## Deals distance-scaled damage to all valid damageable entities in radius.
func _apply_blast_damage() -> void:
	print("TripMine: Applying blast damage within radius: ", blast_radius)
	var processed_entities: Array[Node] = []

	var bodies: Array[Node3D] = blast_area.get_overlapping_bodies()
	for body: Node3D in bodies:
		_process_damage_receiver(body, processed_entities)

	var areas: Array[Area3D] = blast_area.get_overlapping_areas()
	for area: Area3D in areas:
		_process_damage_receiver(area, processed_entities)


## Delivers scaled damage to entity if line of sight is unblocked by terrain.
func _process_damage_receiver(actor: Node, processed_list: Array[Node]) -> void:
	if actor in processed_list or not (actor is Node3D):
		return

	var target_3d: Node3D = actor as Node3D
	var distance: float = global_position.distance_to(target_3d.global_position)
	if distance > blast_radius:
		return

	if _is_occluded_by_environment(target_3d.global_position):
		print("TripMine: Target ", actor.name, " is protected by terrain line-of-sight.")
		return

	var health_comp: HealthComponent = _find_health_component(actor)
	var damage_val: int = _calculate_damage(distance)

	if is_instance_valid(health_comp):
		print("TripMine: Dealing ", damage_val, " damage to HealthComponent on: ", actor.name)
		health_comp.take_damage(damage_val)
		processed_list.append(actor)
	elif actor.has_method(&"take_damage"):
		print("TripMine: Calling take_damage(", damage_val, ") directly on: ", actor.name)
		actor.call(&"take_damage", damage_val)
		processed_list.append(actor)


## Queries direct space state ray to check environment wall occlusion.
func _is_occluded_by_environment(target_pos: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position, target_pos, CollisionLayers.MASK_ENVIRONMENT
	)
	var result: Dictionary = space_state.intersect_ray(query)
	return not result.is_empty()


## Recursively discovers an attached [HealthComponent] instance on an actor.
func _find_health_component(node: Node) -> HealthComponent:
	if node is HealthComponent:
		return node as HealthComponent

	var direct_child: Node = node.get_node_or_null("HealthComponent")
	if is_instance_valid(direct_child) and direct_child is HealthComponent:
		return direct_child as HealthComponent

	for child: Node in node.get_children():
		if child is HealthComponent:
			return child as HealthComponent

	return null


## Computes scaled integer damage using 0m and 3m calibrated damage slope.
func _calculate_damage(distance: float) -> int:
	if distance >= blast_radius:
		return 0

	var falloff_rate: float = (max_damage - damage_at_three_meters) / 3.0
	var damage_val: float = max_damage - (falloff_rate * distance)
	var rounded_damage: int = roundi(damage_val)
	return clampi(rounded_damage, 0, int(max_damage))


## Emits distance-scaled screenshake and shockwave requests to [Events] bus.
func _dispatch_screenshake(player_dist: float) -> void:
	var shake_factor: float = clampf(1.0 - (player_dist / 14.0), 0.0, 1.0)
	var shake_intensity: float = shake_factor * peak_screenshake_trauma
	var shake_duration: float = lerpf(0.2, 0.55, shake_factor)

	print("TripMine: Dispatching screenshake with intensity: ", shake_intensity)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal(&"screenshake_requested"):
			events.emit_signal(&"screenshake_requested", shake_intensity, shake_duration)
		if events.has_signal(&"shockwave_requested"):
			events.emit_signal(&"shockwave_requested", global_position, blast_radius, 2.5)


## Plays particle bursts, animates omni light flash, and hides mine meshes.
func _trigger_explosion_effects() -> void:
	print("TripMine: Triggering explosion particles and flash.")
	explosion_fx.visible = true

	fire_particles.restart()
	fire_particles.emitting = true

	smoke_particles.restart()
	smoke_particles.emitting = true

	sparks_particles.restart()
	sparks_particles.emitting = true

	debris_particles.restart()
	debris_particles.emitting = true

	if is_instance_valid(explosion_light):
		explosion_light.light_energy = 8.0
		explosion_light.visible = true
		var tween: Tween = create_tween()
		tween.tween_property(explosion_light, "light_energy", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)

	if is_instance_valid(explosion_audio) and explosion_audio.stream != null:
		explosion_audio.play()

	# Free after debris and smoke conclude
	get_tree().create_timer(1.8).timeout.connect(queue_free)


## Updates active laser sweep pattern and resets internal motion timer.
func set_motion_mode(new_mode: MotionMode) -> void:
	print("TripMine: Setting motion mode to: ", new_mode)
	motion_mode = new_mode
	_motion_timer = 0.0
