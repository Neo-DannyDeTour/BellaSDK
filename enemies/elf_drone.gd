## Autonomous drone supporting navigation, obstacle bashing, flocking, and healing.
@tool
class_name ElfDrone
extends CharacterBody3D

## Emitted on healing pulse, passing [param target] and [param amount] healed.
@warning_ignore("unused_signal")
signal healing_pulsed(target: Node3D, amount: int)

## Emitted when reaching [member target_waypoint] to wait for player entity.
signal reached_waypoint

## Emitted when drone merges into [member flock_controller] swarm.
signal joined_flock

## Behavioral state directing drone actions.
enum TaskState {
	IDLE,
	FOLLOW_SWARM,
	BASH_OBSTACLE,
	FLY_TO_WAYPOINT,
	WAIT_AT_WAYPOINT,
	JOIN_FLOCK,
	EXPLORE,
}

## Maximum linear movement speed in units per second.
@export var move_speed: float = 7.0

## Rate of velocity change towards desired velocity in units/sec^2.
@export var acceleration: float = 18.0

## Distance in units where deceleration begins to prevent overshoot.
@export var arrival_distance: float = 1.5

## Target [Waypoint3D] node drone navigates to along path.
@export var target_waypoint: Waypoint3D

## Swarm controller to merge into upon finishing sequence.
@export var flock_controller: DroneSwarmController

## Maximum wander radius in meters for autonomous area exploration.
@export var explore_radius: float = 30.0

## Interval in seconds between choosing new wander destinations.
@export var explore_interval: float = 4.0

## If true, drone joins flock automatically when player is near waypoint.
@export var auto_join_on_player_proximity: bool = false

## Proximity radius in meters triggering autonomous flock join.
@export var player_waypoint_trigger_distance: float = 3.0

## Oscillation frequency in Hertz when bashing against obstacles.
@export var bash_frequency: float = 5.0

## Peak bounce distance in units drone recoils back from obstacle.
@export var bash_distance: float = 0.8

## Minimum collision normal dot product indicating forward obstacle impact.
@export var obstacle_impact_threshold: float = 0.35

## Current operational task state directing drone actions.
@export var task_state: TaskState = TaskState.EXPLORE

## Maximum distance in units within which healing beam operates.
@export var heal_range: float = 8.0

## Desired spatial coordinate drone moves towards.
var target_position: Vector3 = Vector3.ZERO

## Running elapsed time in seconds used for obstacle bashing math.
var bash_time: float = 0.0

## Anchor coordinate from which obstacle bashing recoils.
var bash_anchor: Vector3 = Vector3.ZERO

## Anchor coordinate around which autonomous exploration wanders.
var explore_anchor: Vector3 = Vector3.ZERO

## Timer tracking elapsed seconds until next wander retargeting.
var explore_timer: float = 0.0

## Surface normal of hit obstacle used to align recoil motion.
var bash_normal: Vector3 = Vector3.BACK

## Cooldown timer preventing instantaneous re-collision checks.
var bash_check_timer: float = 0.0

## Cached reference to obstacle collider being bashed against.
var hit_obstacle_node: Node = null

## Cached player entity found in scene tree.
var cached_player: Node3D = null

## Cached reference to child [MeshInstance3D] for glow materials.
var mesh_instance: MeshInstance3D

## Child [MeshInstance3D] stretched as an illuminated beam to target.
var healing_beam: MeshInstance3D

## Particle emitter producing energy motes when beam is active.
var beam_particles: GPUParticles3D

## Cached reference to child [OmniLight3D] for illumination.
var omni_light: OmniLight3D

## Active target [Node3D] being healed by the drone.
var current_healing_target: Node3D = null


## Initializes node references, visual elements, and starting task.
func _ready() -> void:
	print("ElfDrone: Initializing drone actor on ", name)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	target_position = global_position
	bash_anchor = global_position
	explore_anchor = global_position

	var m_node: Node = get_node_or_null("MeshInstance3D")
	mesh_instance = m_node if m_node is MeshInstance3D else null
	var h_node: Node = get_node_or_null("HealingBeam")
	healing_beam = h_node if h_node is MeshInstance3D else null
	var b_node: Node = get_node_or_null("BeamParticles")
	beam_particles = b_node if b_node is GPUParticles3D else null
	var o_node: Node = get_node_or_null("OmniLight3D")
	omni_light = o_node if o_node is OmniLight3D else null

	if is_instance_valid(healing_beam):
		healing_beam.top_level = true
		healing_beam.visible = false

	if is_instance_valid(beam_particles):
		beam_particles.emitting = false

	if not Engine.is_editor_hint():
		if task_state == TaskState.EXPLORE:
			_pick_new_explore_target()
		elif task_state == TaskState.FLY_TO_WAYPOINT and target_waypoint != null:
			navigate_to_waypoint(target_waypoint)


## Executes task state routines and updates physics velocity.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	match task_state:
		TaskState.IDLE:
			velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
			move_and_slide()
		TaskState.EXPLORE:
			_process_explore(delta)
			_apply_movement(delta)
		TaskState.BASH_OBSTACLE:
			_process_bash_obstacle(delta)
			_apply_movement(delta)
		TaskState.FLY_TO_WAYPOINT:
			_process_fly_to_waypoint()
			_apply_movement(delta)
		TaskState.WAIT_AT_WAYPOINT:
			_process_wait_at_waypoint()
			_apply_movement(delta)
		TaskState.JOIN_FLOCK:
			_process_join_flock()
			_apply_movement(delta)
		TaskState.FOLLOW_SWARM:
			_apply_movement(delta)

	if is_instance_valid(current_healing_target):
		_update_beam_transform()


## Controls free wandering within [member explore_radius].
func _process_explore(delta: float) -> void:
	explore_timer += delta
	var dist: float = global_position.distance_to(target_position)
	if explore_timer >= explore_interval or dist <= arrival_distance:
		explore_timer = 0.0
		_pick_new_explore_target()


## Picks a randomized target coordinate around [member explore_anchor].
func _pick_new_explore_target() -> void:
	var random_dir: Vector3 = (
		Vector3(randf_range(-1.0, 1.0), randf_range(-0.25, 0.25), randf_range(-1.0, 1.0))
		. normalized()
	)
	var random_dist: float = randf_range(3.0, explore_radius)
	target_position = explore_anchor + (random_dir * random_dist)
	print("ElfDrone: New explore destination picked: ", target_position)


## Steers drone toward [member target_waypoint] and advances chain.
func _process_fly_to_waypoint() -> void:
	if not is_instance_valid(target_waypoint):
		return

	target_position = target_waypoint.global_position
	if target_waypoint.is_reached(global_position):
		print("ElfDrone: Arrived at waypoint: ", target_waypoint.name)
		if target_waypoint.next_waypoint != null:
			target_waypoint = target_waypoint.next_waypoint
			target_position = target_waypoint.global_position
			print("ElfDrone: Advancing along chain to: ", target_waypoint.name)
		else:
			print("ElfDrone: End of chain reached. Waiting for player at ", target_waypoint.name)
			task_state = TaskState.WAIT_AT_WAYPOINT
			reached_waypoint.emit()


## Sweeps forward geometry to detect obstacles blocking waypoint flight.
func _sweep_for_obstacles(move_heading: Vector3) -> bool:
	if move_heading.is_zero_approx():
		return false
	var kin_col: KinematicCollision3D = KinematicCollision3D.new()
	if test_move(global_transform, move_heading * 0.45, kin_col):
		var collider: Object = kin_col.get_collider()
		var col_node: Node = collider as Node
		if col_node != null and not col_node.is_in_group(&"player"):
			var hit_norm: Vector3 = kin_col.get_normal()
			if hit_norm.dot(move_heading) < -obstacle_impact_threshold:
				_start_bashing_from_collision(col_node, hit_norm)
				return true
	return false


## Oscillates drone against hit obstacle and samples if passage has cleared.
func _process_bash_obstacle(delta: float) -> void:
	bash_time += delta
	bash_check_timer += delta

	var cycle: float = absf(sin(bash_time * bash_frequency))
	target_position = bash_anchor + (bash_normal * (cycle * bash_distance))

	if bash_check_timer >= 0.25:
		bash_check_timer = 0.0

		var obstacle_is_open: bool = false
		if is_instance_valid(hit_obstacle_node):
			var open_val: Variant = hit_obstacle_node.get("open")
			if open_val == true:
				obstacle_is_open = true

		var path_is_free: bool = false
		if is_instance_valid(target_waypoint):
			var dir_to_wp: Vector3 = (
				(target_waypoint.global_position - global_position).normalized()
			)
			var test_xf: Transform3D = global_transform.translated(dir_to_wp * 0.4)
			path_is_free = not test_move(test_xf, dir_to_wp * 0.2)

		if obstacle_is_open or path_is_free or not is_instance_valid(hit_obstacle_node):
			print("ElfDrone: Obstacle opened/cleared! Resuming flight to waypoint.")
			hit_obstacle_node = null
			task_state = TaskState.FLY_TO_WAYPOINT


## Waits at waypoint until player enters proximity or sequencer commands.
func _process_wait_at_waypoint() -> void:
	if not is_instance_valid(target_waypoint):
		return

	target_position = target_waypoint.global_position
	if not auto_join_on_player_proximity:
		return

	if not is_instance_valid(cached_player):
		cached_player = _find_player()
		return

	var dist_to_waypoint: float = cached_player.global_position.distance_to(
		target_waypoint.global_position
	)

	if dist_to_waypoint <= player_waypoint_trigger_distance:
		print("ElfDrone: Player reached proximity threshold. Joining flock.")
		join_flock()


## Flies to [member flock_controller] and merges into swarm.
func _process_join_flock() -> void:
	if not is_instance_valid(flock_controller):
		return

	target_position = flock_controller.global_position
	var dist: float = global_position.distance_to(flock_controller.global_position)

	if dist <= 2.5:
		print("ElfDrone: Swarm reached. Adopting into controller.")
		task_state = TaskState.FOLLOW_SWARM
		flock_controller.adopt_drone(self)
		joined_flock.emit()


## Smoothly accelerates velocity toward destination coordinate.
func _apply_movement(delta: float) -> void:
	var displacement: Vector3 = target_position - global_position
	var distance: float = displacement.length()
	var desired_velocity: Vector3 = Vector3.ZERO

	if distance > 0.02:
		var speed_factor: float = clampf(distance / arrival_distance, 0.0, 1.0)
		desired_velocity = (displacement / distance) * (move_speed * speed_factor)

	if task_state == TaskState.FLY_TO_WAYPOINT:
		if _sweep_for_obstacles(desired_velocity.normalized()):
			return

	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	move_and_slide()

	if task_state == TaskState.FLY_TO_WAYPOINT and get_slide_collision_count() > 0:
		for i: int in range(get_slide_collision_count()):
			var collision: KinematicCollision3D = get_slide_collision(i)
			var collider: Object = collision.get_collider()
			var col_node: Node = collider as Node
			if col_node == null or col_node.is_in_group(&"player"):
				continue
			var hit_norm: Vector3 = collision.get_normal()
			var move_heading: Vector3 = desired_velocity.normalized()
			if move_heading.is_zero_approx():
				move_heading = displacement.normalized()

			if hit_norm.dot(move_heading) < -obstacle_impact_threshold:
				_start_bashing_from_collision(col_node, hit_norm)
				break


## Configures obstacle bash state from collision normal.
func _start_bashing_from_collision(collider: Node, normal: Vector3) -> void:
	print("ElfDrone: Obstacle collision registered! Starting bash routine.")
	hit_obstacle_node = _resolve_door_or_obstacle(collider)
	bash_normal = normal
	bash_anchor = global_position
	bash_time = 0.0
	bash_check_timer = 0.0
	task_state = TaskState.BASH_OBSTACLE


## Traverses ancestor hierarchy to locate parent door interact component.
func _resolve_door_or_obstacle(col: Node) -> Node:
	var curr: Node = col
	while curr != null:
		if curr is DoorInteract or curr.has_method("toggle_open") or "open" in curr:
			return curr
		curr = curr.get_parent()
	return col


## Commands drone to navigate to a target waypoint or continue current chain.
func navigate_to_waypoint(waypoint: Variant = null) -> void:
	print("ElfDrone: navigate_to_waypoint() called with: ", waypoint)
	if waypoint is Waypoint3D:
		target_waypoint = waypoint
	elif waypoint is NodePath or waypoint is String:
		var path_str: String = str(waypoint).strip_edges()
		if not path_str.is_empty():
			var resolved_node: Node = get_node_or_null(NodePath(path_str))
			if not is_instance_valid(resolved_node) and is_inside_tree():
				resolved_node = get_tree().get_root().find_child(path_str, true, false)
			if resolved_node is Waypoint3D:
				target_waypoint = resolved_node

	if is_instance_valid(target_waypoint):
		task_state = TaskState.FLY_TO_WAYPOINT
	else:
		print("ElfDrone: No valid Waypoint3D specified or assigned.")


## Commands drone to start bashing an obstacle, either passed or nearest forward.
func start_bashing_obstacle(target_obstacle: Variant = null) -> void:
	print("ElfDrone: start_bashing_obstacle() commanded.")
	if target_obstacle is Node:
		var obs_node: Node = target_obstacle
		hit_obstacle_node = _resolve_door_or_obstacle(obs_node)
	bash_anchor = global_position
	bash_normal = -global_transform.basis.z.normalized()
	bash_time = 0.0
	bash_check_timer = 0.0
	task_state = TaskState.BASH_OBSTACLE


## Commands drone to begin freely roaming within exploration radius.
func start_exploring(_param: Variant = null) -> void:
	print("ElfDrone: start_exploring() commanded.")
	explore_anchor = global_position
	task_state = TaskState.EXPLORE
	_pick_new_explore_target()


## Commands drone to abandon waiting and merge into [member flock_controller].
func join_flock(_param: Variant = null) -> void:
	print("ElfDrone: Command 'join_flock' received.")
	task_state = TaskState.JOIN_FLOCK


## Queries scene tree nodes in group player to locate target entity.
func _find_player() -> Node3D:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not nodes.is_empty() and nodes[0] is Node3D:
		var n0: Node = nodes[0]
		return n0 if n0 is Node3D else null
	return null


## Updates target destination coordinate when managed by swarm.
func set_target_position(new_pos: Vector3) -> void:
	target_position = new_pos


## Sets or clears [member current_healing_target] and visuals.
func set_healing_target(target: Node3D) -> void:
	if current_healing_target == target:
		return

	var label: String = String(target.name) if target != null else "null"
	print("ElfDrone: Healing target set to ", label)
	current_healing_target = target

	if current_healing_target == null:
		if is_instance_valid(healing_beam):
			healing_beam.visible = false
		if is_instance_valid(beam_particles):
			beam_particles.emitting = false
	else:
		if is_instance_valid(beam_particles):
			beam_particles.emitting = true


## Stretches and points [member healing_beam] toward target.
func _update_beam_transform() -> void:
	if not is_instance_valid(healing_beam):
		return

	if not is_instance_valid(current_healing_target):
		set_healing_target(null)
		return

	var start_pt: Vector3 = global_position
	var end_pt: Vector3 = current_healing_target.global_position
	var dist: float = start_pt.distance_to(end_pt)

	if dist <= 0.05 or dist > heal_range:
		healing_beam.visible = false
		return

	healing_beam.visible = true
	healing_beam.global_position = (start_pt + end_pt) * 0.5
	var dir: Vector3 = (end_pt - start_pt).normalized()
	var up_vec: Vector3 = Vector3.RIGHT if absf(dir.y) > 0.98 else Vector3.UP
	healing_beam.look_at(end_pt, up_vec)
	healing_beam.scale = Vector3(1.0, 1.0, dist)


## Applies glow and emission colors to mesh and omni light.
func set_glow_color(color: Color) -> void:
	print("ElfDrone: Applying glow color ", color)
	if is_instance_valid(mesh_instance):
		var raw_mat: Material = mesh_instance.get_active_material(0)
		var mat: StandardMaterial3D = raw_mat if raw_mat is StandardMaterial3D else null
		if mat != null:
			mat.albedo_color = color
			mat.emission = color
	if is_instance_valid(omni_light):
		omni_light.light_color = color
