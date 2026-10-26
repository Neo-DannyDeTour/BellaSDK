## Manages vertical wall climbing and sliding in [StateWolfClimb].
class_name StateWolfClimb
extends PlayerState

## Group tag identifying geometry permissible for wolf wall traversal.
const GROUP_WOLF_CLIMBABLE: StringName = &"wolf_climbable"

## Ascending and lateral climbing movement speed in meters per second.
const CLIMB_SPEED: float = 4.5

## Downward slide speed along wall when holding crouch.
const SLIDE_DOWN_SPEED: float = 7.5

## Maximum forward raycast reach in meters for surface-to-surface jump transfers.
const SURFACE_TRANSFER_REACH: float = 18.0

## Launch speed in meters per second when leaping toward another climbable surface.
const SURFACE_TRANSFER_SPEED: float = 22.0

## Normal vector of the climbing wall plane.
var wall_normal: Vector3 = Vector3.ZERO

## Reference to the active surface entity being climbed.
var active_surface: WolfClimbSurface = null

## Whether the player is hanging stationary on the wall.
var is_hanging: bool = false

## Grace timer preventing instant ejection when wall contact drops.
var _wall_lost_time: float = 0.0

## Reusable transition payload dictionary to avoid heap allocations.
var _transition_msg: Dictionary = {}

## Reusable RID array for forward surface transfer raycasts.
var _transfer_exclude_rids: Array[RID] = []


## Clings to wall, zeroes momentum, and caches wall normal.
func enter(msg: Dictionary = {}) -> void:
	print("StateWolfClimb: enter() called. Clinging to climbable wall.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	_wall_lost_time = 0.0
	is_hanging = msg.get(&"hang_mode", false) == true
	wall_normal = msg.get(&"wall_normal", p.get_wall_normal())

	var raw_surface: Variant = msg.get(&"climb_surface", null)
	if raw_surface is WolfClimbSurface:
		active_surface = raw_surface
	else:
		active_surface = null

	_snap_to_wall(p, wall_normal)
	p.velocity = Vector3.ZERO


## Solves vertical climb, crouch slide, and dismount inputs.
func physics_update(delta: float) -> void:
	print("StateWolfClimb: physics_update() processing wall traversal.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	if is_instance_valid(active_surface) and not active_surface.is_character_on_surface(p):
		print("StateWolfClimb: Character moved past surface bounds. Falling to ground.")
		active_surface.set_dismount_cooldown(p, 500)
		state_machine.transition_to(&"Air")
		return

	var is_jump_pressed: bool = (
		GestureInputManager.is_action_just_triggered(ACTION_JUMP)
		or GestureInputManager.is_action_just_pressed(ACTION_JUMP)
	)
	if is_jump_pressed:
		if _try_surface_transfer_jump(p):
			return
		_perform_dismount_jump(p)
		return

	var is_interact_pressed: bool = (
		GestureInputManager.is_action_just_triggered(ACTION_INTERACT)
		or GestureInputManager.is_action_just_pressed(ACTION_INTERACT)
	)
	if is_interact_pressed:
		is_hanging = not is_hanging
		print("StateWolfClimb: Toggled stationary hang mode -> ", is_hanging)

	var is_crouching: bool = (
		GestureInputManager.is_action_active(ACTION_CROUCH)
		or GestureInputManager.is_action_pressed(ACTION_CROUCH)
	)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	var lateral_dir: Vector3 = Vector3.UP.cross(wall_normal).normalized()
	var horizontal_move: Vector3 = Vector3.ZERO
	var vertical_move: float = 0.0

	if not is_hanging:
		horizontal_move = lateral_dir * (-input_dir.x * CLIMB_SPEED)
		if is_crouching:
			vertical_move = -SLIDE_DOWN_SPEED
		else:
			vertical_move = -input_dir.y * CLIMB_SPEED

	p.velocity = horizontal_move
	p.velocity.y = vertical_move
	p.velocity -= wall_normal * 4.0

	p.move_and_slide()

	if p.is_on_floor() and (is_crouching or input_dir.y > 0.0):
		print("StateWolfClimb: Reached floor ground. Exiting to Ground.")
		state_machine.transition_to(&"Ground")
		return

	if p.is_on_wall():
		_wall_lost_time = 0.0
	else:
		_wall_lost_time += delta

	if _wall_lost_time > 0.15:
		print("StateWolfClimb: Lost wall contact beyond grace duration. Falling to Air.")
		if is_instance_valid(active_surface):
			active_surface.set_dismount_cooldown(p, 500)
		state_machine.transition_to(&"Air")


## Snaps player flush against wall to eliminate air gaps.
func _snap_to_wall(p: Player, norm: Vector3) -> void:
	print("StateWolfClimb: Snapping player flush to wall surface.")
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var start_pos: Vector3 = p.global_position + Vector3.UP * 0.5
	var end_pos: Vector3 = start_pos - norm * 1.5
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
	query.exclude = [p.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
		p.global_position.x = hit_pos.x + norm.x * 0.45
		p.global_position.z = hit_pos.z + norm.z * 0.45


## Launches player away from wall into [StateAir].
func _perform_dismount_jump(p: Player) -> void:
	print("StateWolfClimb: Performing wall dismount jump.")
	if is_instance_valid(active_surface):
		active_surface.set_dismount_cooldown(p, 500)

	p.velocity = wall_normal * 6.5 + Vector3.UP * 5.0
	_transition_msg.clear()
	_transition_msg[&"jump"] = true
	state_machine.transition_to(&"Air", _transition_msg)


## Raycasts along camera look vector and leaps toward another climbable surface if found.
func _try_surface_transfer_jump(p: Player) -> bool:
	if not is_instance_valid(p.camera_controller):
		return false

	var cam_ctrl: CameraController = p.camera_controller
	var start_pos: Vector3 = (
		cam_ctrl.camera.global_position
		if is_instance_valid(cam_ctrl.camera)
		else p.global_position + Vector3(0.0, 1.5, 0.0)
	)
	var look_dir: Vector3 = cam_ctrl.get_camera_look_dir().normalized()
	var end_pos: Vector3 = start_pos + (look_dir * SURFACE_TRANSFER_REACH)

	_transfer_exclude_rids.clear()
	_transfer_exclude_rids.append(p.get_rid())
	if is_instance_valid(active_surface):
		_transfer_exclude_rids.append(active_surface.get_rid())

	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var mask: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE
	var hit: Dictionary = NodeQuery.cast_ray(
		space, start_pos, end_pos, mask, _transfer_exclude_rids
	)
	if hit.is_empty():
		return false

	var collider: Object = hit.get("collider")
	var col_node: Node = collider as Node
	if not is_instance_valid(col_node) or not _is_climbable_node(col_node):
		return false

	print("StateWolfClimb: Surface-to-surface transfer jump to ", col_node.name)
	if is_instance_valid(active_surface):
		active_surface.set_dismount_cooldown(p, 600)

	var hit_pos: Vector3 = hit.get("position", end_pos)
	p.global_position += wall_normal * 0.35
	var to_target: Vector3 = hit_pos - p.global_position
	var dist: float = maxf(to_target.length(), 1.0)
	var flight_time: float = clampf(dist / SURFACE_TRANSFER_SPEED, 0.15, 0.85)
	var launch_vel: Vector3 = to_target / flight_time
	launch_vel.y += 0.5 * 9.8 * flight_time
	p.velocity = launch_vel

	_transition_msg.clear()
	_transition_msg[&"jump"] = true
	_transition_msg[&"wall_jump_launch"] = true
	_transition_msg[&"launch_duration"] = flight_time
	state_machine.transition_to(&"Air", _transition_msg)
	return true


## Checks whether [param node] or its ancestors belong to [constant GROUP_WOLF_CLIMBABLE].
func _is_climbable_node(node: Node) -> bool:
	var curr: Node = node
	while is_instance_valid(curr):
		if curr.is_in_group(GROUP_WOLF_CLIMBABLE):
			return true
		curr = curr.get_parent()
	return false
