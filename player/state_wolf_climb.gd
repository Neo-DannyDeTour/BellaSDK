## Manages vertical wall climbing and sliding in [StateWolfClimb].
class_name StateWolfClimb
extends PlayerState

## Group tag identifying geometry permissible for wolf wall traversal.
const GROUP_WOLF_CLIMBABLE: StringName = &"wolf_climbable"

## Ascending and lateral climbing movement speed in meters per second.
const CLIMB_SPEED: float = 4.5

## Downward slide speed along wall when holding crouch.
const SLIDE_DOWN_SPEED: float = 7.5

## Normal vector of the climbing wall plane.
var wall_normal: Vector3 = Vector3.ZERO

## Reference to the active surface entity being climbed.
var active_surface: WolfClimbSurface = null

## Grace timer preventing instant ejection when wall contact drops.
var _wall_lost_time: float = 0.0

## Reusable transition payload dictionary to avoid heap allocations.
var _transition_msg: Dictionary = {}


## Clings to wall, zeroes momentum, and caches wall normal.
func enter(msg: Dictionary = {}) -> void:
	print("StateWolfClimb: enter() called. Clinging to climbable wall.")
	var p: Player = _get_player()
	if not is_instance_valid(p):
		return

	_wall_lost_time = 0.0
	wall_normal = msg.get(&"wall_normal", p.get_wall_normal())

	var raw_surface: Variant = msg.get(&"climb_surface", null)
	if raw_surface is WolfClimbSurface:
		@warning_ignore("unsafe_cast")
		active_surface = raw_surface as WolfClimbSurface
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

	if GestureInputManager.is_action_just_triggered(&"jump"):
		_perform_dismount_jump(p)
		return

	var is_crouching: bool = (
		GestureInputManager.is_action_active(ACTION_CROUCH)
		or GestureInputManager.is_action_pressed(ACTION_CROUCH)
	)

	var input_dir: Vector2 = GestureInputManager.get_vector(
		&"left", &"right", &"forward", &"backward"
	)

	var lateral_dir: Vector3 = Vector3.UP.cross(wall_normal).normalized()
	var horizontal_move: Vector3 = lateral_dir * (-input_dir.x * CLIMB_SPEED)
	var vertical_move: float = 0.0

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
