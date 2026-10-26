## Manages wolf wall running mechanics and high-speed dismount kicks.
class_name StateWolfWallRun
extends PlayerState

## Group tag identifying geometry permissible for wolf traversal.
const GROUP_WOLF_CLIMBABLE: StringName = &"wolf_climbable"

## Sustained forward wall run speed magnitude in meters per second.
const WALL_RUN_SPEED: float = 12.0

## Maximum wall run duration in seconds before dropping.
const MAX_WALL_RUN_TIME: float = 2.5

## Lateral impulse applied when jumping off the wall (15m jump).
const WALL_JUMP_KICK_IMPULSE: float = 20.0

## Maximum forward raycast reach in meters for surface-to-surface jump transfers.
const SURFACE_TRANSFER_REACH: float = 18.0

## Launch speed in meters per second when leaping toward another climbable surface.
const SURFACE_TRANSFER_SPEED: float = 22.0

## Camera roll tilt angle in degrees during wall run.
const CAMERA_ROLL_ANGLE: float = 14.0

## Outward surface normal of active wall.
var current_wall_normal: Vector3 = Vector3.ZERO

## Normalized heading vector along wall.
var wall_run_dir: Vector3 = Vector3.ZERO

## Elapsed time on the current wall segment.
var wall_run_timer: float = 0.0

## Wall side sign multiplier (-1 left, 1 right).
var wall_side: float = 1.0

## Reference to active [WolfClimbSurface].
var active_surface: WolfClimbSurface = null

## Grace timer preventing premature ejection before wall contact.
var _wall_lost_time: float = 0.0

## Reusable transition payload dictionary.
var _transition_msg: Dictionary = {}

## Reusable RID array for forward surface transfer raycasts.
var _transfer_exclude_rids: Array[RID] = []


## Cleans up active wall run visual effects when removed from scene tree.
func _exit_tree() -> void:
	Events.wolf_wall_run_vfx_toggled.emit(false)


## Initializes wall run direction, speed, and camera roll.
func enter(msg: Dictionary = {}) -> void:
	print("StateWolfWallRun: enter() called. Initializing wall run.")
	Events.wolf_wall_run_vfx_toggled.emit(true)
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	wall_run_timer = 0.0
	_wall_lost_time = 0.0
	current_wall_normal = msg.get(&"wall_normal", p.get_wall_normal())

	var raw_surface: Variant = msg.get(&"climb_surface", null)
	if raw_surface is WolfClimbSurface:
		active_surface = raw_surface
	else:
		active_surface = null

	_snap_to_wall(p, current_wall_normal)

	var cam_fwd: Vector3 = p.camera_controller.get_camera_look_dir().normalized()
	var tangent: Vector3 = Vector3.UP.cross(current_wall_normal).normalized()

	if tangent.dot(cam_fwd) < 0.0:
		tangent = -tangent

	wall_run_dir = tangent

	var cam_right: Vector3 = p.camera_controller.get_camera_right_dir()
	wall_side = 1.0 if current_wall_normal.dot(cam_right) < 0.0 else -1.0

	p.velocity.y = 1.5


## Solves forward wall run movement, gravity, and dismount.
func physics_update(delta: float) -> void:
	print("StateWolfWallRun: physics_update() processing wall run.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	var is_interact_pressed: bool = (
		GestureInputManager.is_action_just_triggered(ACTION_INTERACT)
		or GestureInputManager.is_action_just_pressed(ACTION_INTERACT)
	)
	if is_interact_pressed:
		print("StateWolfWallRun: Interact pressed. Stopping wall run to hang.")
		_transition_msg.clear()
		_transition_msg[&"wall_normal"] = current_wall_normal
		_transition_msg[&"climb_surface"] = active_surface
		_transition_msg[&"hang_mode"] = true
		state_machine.transition_to(&"WolfClimb", _transition_msg)
		return

	var is_jump_pressed: bool = (
		GestureInputManager.is_action_just_triggered(ACTION_JUMP)
		or GestureInputManager.is_action_just_pressed(ACTION_JUMP)
	)

	if is_jump_pressed:
		if _try_surface_transfer_jump(p):
			return
		_perform_wall_jump(p)
		return

	if is_instance_valid(active_surface) and not active_surface.is_character_on_surface(p):
		print("StateWolfWallRun: Run off surface edge. Falling with coyote grace.")
		if is_instance_valid(active_surface):
			active_surface.set_dismount_cooldown(p, 500)
		_transition_msg.clear()
		_transition_msg[&"wall_coyote"] = true
		_transition_msg[&"wall_normal"] = current_wall_normal
		_transition_msg[&"wall_run_dir"] = wall_run_dir
		state_machine.transition_to(&"Air", _transition_msg)
		return

	wall_run_timer += delta

	p.velocity.y = move_toward(p.velocity.y, -1.5, 3.5 * delta)
	p.velocity.x = wall_run_dir.x * WALL_RUN_SPEED
	p.velocity.z = wall_run_dir.z * WALL_RUN_SPEED
	p.velocity -= current_wall_normal * (2.5 * delta * 60.0)

	p.move_and_slide()

	_apply_camera_roll(p, delta)

	if p.is_on_wall():
		_wall_lost_time = 0.0
	else:
		_wall_lost_time += delta

	if _wall_lost_time > 0.15 or wall_run_timer >= MAX_WALL_RUN_TIME or p.is_on_floor():
		print("StateWolfWallRun: Exiting wall run -> lost wall, ground hit, or timeout.")
		if is_instance_valid(active_surface):
			active_surface.set_dismount_cooldown(p, 500)
		state_machine.transition_to(&"Air")


## Restores camera roll angle to zero on state exit.
func exit() -> void:
	print("StateWolfWallRun: exit() resetting camera roll angle.")
	Events.wolf_wall_run_vfx_toggled.emit(false)
	var p: Player = _get_player()
	if is_instance_valid(p) and is_instance_valid(p.camera_controller):
		p.camera_controller.eyes.rotation.z = 0.0


## Snaps player flush against wall to eliminate air gaps.
func _snap_to_wall(p: Player, norm: Vector3) -> void:
	print("StateWolfWallRun: Snapping player flush to wall surface.")
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


## Smoothly rolls camera eyes into the wall run angle.
func _apply_camera_roll(p: Player, delta: float) -> void:
	if not is_instance_valid(p.camera_controller):
		return
	var target_roll: float = deg_to_rad(CAMERA_ROLL_ANGLE * wall_side)
	p.camera_controller.eyes.rotation.z = lerpf(
		p.camera_controller.eyes.rotation.z, target_roll, delta * 8.0
	)


## Launches player diagonally away from wall into [StateAir].
func _perform_wall_jump(p: Player) -> void:
	print("StateWolfWallRun: Performing wall run 15m dismount jump.")
	if is_instance_valid(active_surface):
		active_surface.set_dismount_cooldown(p, 600)

	p.global_position += current_wall_normal * 0.35

	var kick_dir: Vector3 = (current_wall_normal * 1.5 + wall_run_dir * 0.7).normalized()
	p.velocity = kick_dir * WALL_JUMP_KICK_IMPULSE
	p.velocity.y = 7.5

	_transition_msg.clear()
	_transition_msg[&"jump"] = true
	_transition_msg[&"wall_jump_launch"] = true
	_transition_msg[&"launch_duration"] = 0.85
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

	print("StateWolfWallRun: Surface-to-surface transfer jump to ", col_node.name)
	if is_instance_valid(active_surface):
		active_surface.set_dismount_cooldown(p, 600)

	var hit_pos: Vector3 = hit.get("position", end_pos)
	p.global_position += current_wall_normal * 0.35
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
