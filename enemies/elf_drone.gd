## Autonomous fairy drone supporting door bashing, navigation, and flocking.
class_name ElfDrone
extends CharacterBody3D

## Emitted on healing pulse, passing [param target] and [param amount].
signal healing_pulsed(target: Node3D, amount: int)

## Emitted when reaching [member target_waypoint] to wait for player.
signal reached_waypoint

## Emitted when drone joins [member flock_controller].
signal joined_flock

## Behavioral state directing drone between level choreography and flocking.
enum TaskState {
	FOLLOW_SWARM,
	BASH_DOOR,
	FLY_TO_WAYPOINT,
	WAIT_AT_WAYPOINT,
	JOIN_FLOCK,
}

## Maximum linear movement speed in units per second.
@export var move_speed: float = 7.0

## Rate of velocity change towards desired velocity in units/sec^2.
@export var acceleration: float = 18.0

## Distance in units where deceleration begins to prevent overshoot.
@export var arrival_distance: float = 1.5

## Health points restored to target entity during healing pulses.
@export var heal_amount: int = 4

## Cooldown interval in seconds between consecutive healing attempts.
@export var heal_cooldown: float = 0.8

## Maximum distance in units within which healing pulses can land.
@export var heal_range: float = 8.0

## Target [Waypoint3D] node drone navigates to inside the tunnel.
@export var target_waypoint: Waypoint3D

## Door obstacle blocking path that causes bashing behavior.
@export var blocking_door: DoorInteract

## Swarm controller to merge into upon finishing tunnel sequence.
@export var flock_controller: DroneSwarmController

## Distance in units player must be from waypoint to trigger flock join.
@export var player_waypoint_trigger_distance: float = 3.0

## Travel speed in units per second when bashing against door.
@export var bash_frequency: float = 5.0

## Peak bounce distance in units drone recoils back from door.
@export var bash_distance: float = 0.8

## Current operational task state directing drone actions.
@export var task_state: TaskState = TaskState.FOLLOW_SWARM

## Desired spatial coordinate drone moves towards.
var target_position: Vector3 = Vector3.ZERO

## Internal cooldown timer tracking time between healing pulses.
var heal_timer: float = 0.0

## Running elapsed time in seconds used for door bashing math.
var bash_time: float = 0.0

## Anchor coordinate from which door bashing recoils.
var bash_anchor: Vector3 = Vector3.ZERO

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

## Cached player entity found in scene tree.
var cached_player: Node3D = null

## Flag ensuring waypoint arrival is confirmed before player distance check.
var has_settled_at_waypoint: bool = false


## Initializes node references, visual states, and starting task.
func _ready() -> void:
	print("ElfDrone: Initializing drone actor on ", name)
	mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	healing_beam = get_node_or_null("HealingBeam") as MeshInstance3D
	beam_particles = get_node_or_null("BeamParticles") as GPUParticles3D
	omni_light = get_node_or_null("OmniLight3D") as OmniLight3D

	target_position = global_position
	bash_anchor = global_position

	if healing_beam != null:
		healing_beam.top_level = true
		healing_beam.visible = false

	if beam_particles != null:
		beam_particles.emitting = false

	_init_autonomous_task()


## Configures initial task state based on Inspector assignments.
func _init_autonomous_task() -> void:
	if target_waypoint != null:
		if blocking_door != null and not blocking_door.open:
			print("ElfDrone: Door is closed. Starting in BASH_DOOR.")
			task_state = TaskState.BASH_DOOR
		else:
			print("ElfDrone: Path is clear. Navigating to target waypoint.")
			task_state = TaskState.FLY_TO_WAYPOINT
	else:
		task_state = TaskState.FOLLOW_SWARM


## Executes task state routines and updates physics velocity.
func _physics_process(delta: float) -> void:
	match task_state:
		TaskState.BASH_DOOR:
			_process_bash_door(delta)
		TaskState.FLY_TO_WAYPOINT:
			_process_fly_to_waypoint()
		TaskState.WAIT_AT_WAYPOINT:
			_process_wait_at_waypoint()
		TaskState.JOIN_FLOCK:
			_process_join_flock()
		TaskState.FOLLOW_SWARM:
			pass

	_apply_movement(delta)

	if heal_timer > 0.0:
		heal_timer = maxf(0.0, heal_timer - delta)

	if current_healing_target != null:
		_update_beam_transform()


## Oscillates drone position to bash against closed door.
func _process_bash_door(delta: float) -> void:
	if blocking_door != null and blocking_door.open:
		print("ElfDrone: Door opened! Switching to FLY_TO_WAYPOINT.")
		task_state = TaskState.FLY_TO_WAYPOINT
		return

	bash_time += delta
	var door_dir: Vector3 = Vector3.FORWARD
	if blocking_door != null:
		door_dir = (blocking_door.global_position - bash_anchor).normalized()

	var cycle: float = absf(sin(bash_time * bash_frequency))
	target_position = bash_anchor + (door_dir * (cycle * bash_distance))


## Steers drone toward [member target_waypoint] until arrival.
func _process_fly_to_waypoint() -> void:
	if not is_instance_valid(target_waypoint):
		return

	target_position = target_waypoint.global_position
	if target_waypoint.is_reached(global_position):
		print("ElfDrone: Reached waypoint. Switching to WAIT_AT_WAYPOINT.")
		task_state = TaskState.WAIT_AT_WAYPOINT
		has_settled_at_waypoint = true
		reached_waypoint.emit()


## Waits at waypoint until player is within 3 meters of waypoint.
func _process_wait_at_waypoint() -> void:
	if not is_instance_valid(target_waypoint) or not has_settled_at_waypoint:
		return

	target_position = target_waypoint.global_position

	if not is_instance_valid(cached_player):
		cached_player = _find_player()
		return

	var dist_to_waypoint: float = cached_player.global_position.distance_to(
		target_waypoint.global_position
	)

	if dist_to_waypoint <= player_waypoint_trigger_distance:
		print(
			"ElfDrone: Player reached waypoint proximity (", dist_to_waypoint, "m). Joining flock."
		)
		task_state = TaskState.JOIN_FLOCK


## Flies to [member flock_controller] and merges into swarm.
func _process_join_flock() -> void:
	if not is_instance_valid(flock_controller):
		return

	target_position = flock_controller.global_position
	var dist: float = global_position.distance_to(flock_controller.global_position)

	if dist <= 2.5:
		print("ElfDrone: Reached flock. Adopting into swarm.")
		task_state = TaskState.FOLLOW_SWARM
		flock_controller.adopt_drone(self)
		joined_flock.emit()


## Smoothly accelerates velocity toward [member target_position].
func _apply_movement(delta: float) -> void:
	var displacement: Vector3 = target_position - global_position
	var distance: float = displacement.length()
	var desired_velocity: Vector3 = Vector3.ZERO

	if distance > 0.02:
		var speed_factor: float = clampf(distance / arrival_distance, 0.0, 1.0)
		desired_velocity = (displacement / distance) * (move_speed * speed_factor)

	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	move_and_slide()


## Queries scene tree nodes in group player to locate target.
func _find_player() -> Node3D:
	var nodes: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not nodes.is_empty() and nodes[0] is Node3D:
		return nodes[0] as Node3D
	return null


## Updates destination coordinate when managed by swarm.
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
		if healing_beam != null:
			healing_beam.visible = false
		if beam_particles != null:
			beam_particles.emitting = false
	else:
		if beam_particles != null:
			beam_particles.emitting = true


## Delivers health points to [param target] if cooldown permits.
func try_heal_target(target: Node3D, _delta: float) -> void:
	if target == null or heal_timer > 0.0:
		return

	var dist: float = global_position.distance_to(target.global_position)
	if dist > heal_range:
		return

	var health_comp: HealthComponent = _find_health_component(target)
	if health_comp != null:
		print("ElfDrone: Restoring ", heal_amount, " HP to ", target.name)
		health_comp.heal(heal_amount)
		heal_timer = heal_cooldown
		healing_pulsed.emit(target, heal_amount)


## Locates [HealthComponent] on target entity hierarchy.
func _find_health_component(target: Node) -> HealthComponent:
	var direct: Node = target.get_node_or_null("Components/HealthComponent")
	if direct is HealthComponent:
		return direct as HealthComponent
	var root_child: Node = target.get_node_or_null("HealthComponent")
	if root_child is HealthComponent:
		return root_child as HealthComponent
	return null


## Applies glow and emission colors to mesh and omni light.
func set_glow_color(color: Color) -> void:
	print("ElfDrone: Applying glow color ", color)
	if mesh_instance != null:
		var mat: StandardMaterial3D = mesh_instance.get_active_material(0) as StandardMaterial3D
		if mat != null:
			mat.albedo_color = color
			mat.emission = color
	if omni_light != null:
		omni_light.light_color = color


## Stretches and points [member healing_beam] toward target.
func _update_beam_transform() -> void:
	if healing_beam == null:
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


## Commands the drone to stop bashing and fly toward [member target_waypoint].
func fly_to_tunnel(_param: Variant = null) -> void:
	print("ElfDrone: Received input 'fly_to_tunnel'.")
	task_state = TaskState.FLY_TO_WAYPOINT


## Commands the drone to abandon waiting and merge into [member flock_controller].
func join_flock(_param: Variant = null) -> void:
	print("ElfDrone: Received input 'join_flock'.")
	task_state = TaskState.JOIN_FLOCK
