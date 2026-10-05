## Heavy physics box requiring two hands that player pushes on ground.
class_name HeavyPickableBox
extends PickableObject

@export_group("Movement Settings")
## Maximum separation distance before the box automatically drops.
@export var drop_distance: float = 2.5

## Duration in seconds of the player pickup alignment tween.
@export var snap_duration: float = 0.3

@export_group("Box Dimensions")
## Half-width of box used to calculate player standoff distance.
@export var box_half_width: float = 1.0

@export_group("Player Settings")
## Collision radius of the player character to avoid overlap.
@export var player_radius: float = 0.5

## Total height of the player character for clearance raycasts.
@export var player_height: float = 1.8

## Additional standoff padding between player and box while pushing.
@export var hold_padding: float = 0.75

## Physics collision mask defining valid environment obstacles.
@export_flags_3d_physics var environment_collision_mask: int = 1

## Indicates whether the box is currently being pushed by player.
var is_heavy_held: bool = false

## Tracks whether player is currently tweening into pushing stance.
var _is_animating: bool = false

## Caches locked forward heading vector of player during push.
var _locked_player_fwd: Vector3 = Vector3.ZERO

## Tracks accumulated downward gravity velocity while pushing.
var _fall_velocity: float = 0.0

## Cached ray query parameters for zero-allocation ground checks.
var _ground_query: PhysicsRayQueryParameters3D = null

## Cached shape query parameters for zero-allocation stance checks.
var _stand_shape_query: PhysicsShapeQueryParameters3D = null

## Cached capsule shape resource used by stance collision queries.
var _stand_capsule: CapsuleShape3D = null


## Initializes cached query parameters for zero-allocation checks.
func _ready() -> void:
	super._ready()
	print("HeavyPickableBox: _ready() initialized.")
	_ground_query = PhysicsRayQueryParameters3D.new()
	_ground_query.collision_mask = environment_collision_mask

	_stand_capsule = CapsuleShape3D.new()
	_stand_capsule.radius = player_radius * 0.8
	_stand_capsule.height = player_height * 0.8

	_stand_shape_query = PhysicsShapeQueryParameters3D.new()
	_stand_shape_query.shape = _stand_capsule
	_stand_shape_query.collision_mask = environment_collision_mask


## Overrides pickup to initiate heavy ground pushing sequence.
func pick_up(_target: Marker3D, player: Node3D) -> void:
	print("HeavyPickableBox: pick_up() executed.")
	if is_locked or _is_animating:
		return

	if not is_valid_pickup_position(player):
		return

	var p_pos: Vector3 = player.global_position
	var b_pos: Vector3 = global_position

	var to_player: Vector3 = p_pos - b_pos
	var height_diff: float = p_pos.y - b_pos.y
	var flat_dist: float = Vector2(p_pos.x - b_pos.x, p_pos.z - b_pos.z).length()

	if height_diff > 0.3 and flat_dist < (box_half_width + 0.3):
		return

	to_player.y = 0.0
	to_player = to_player.normalized()

	var b_fwd: Vector3 = -global_transform.basis.z.normalized()
	var b_right: Vector3 = global_transform.basis.x.normalized()
	var snap_normal: Vector3

	if abs(to_player.dot(b_fwd)) > abs(to_player.dot(b_right)):
		snap_normal = b_fwd if to_player.dot(b_fwd) > 0.0 else -b_fwd
	else:
		snap_normal = b_right if to_player.dot(b_right) > 0.0 else -b_right

	var hold_distance: float = box_half_width + player_radius + hold_padding
	var target_stand_pos: Vector3 = b_pos + (snap_normal * hold_distance)
	target_stand_pos.y = p_pos.y

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query_y: float = target_stand_pos.y + (player_height / 2.0) + 0.5
	var query_pos: Vector3 = Vector3(target_stand_pos.x, query_y, target_stand_pos.z)

	_stand_shape_query.transform = Transform3D(Basis(), query_pos)
	_stand_shape_query.exclude = [get_rid(), player.get_rid()]

	if not space_state.intersect_shape(_stand_shape_query).is_empty():
		return

	_is_animating = true
	holder = player
	_cached_exclude_rids = [get_rid(), holder.get_rid()]

	add_collision_exception_with(holder)
	notify_holder_stun(holder, true)

	if interact_comp:
		if "monitorable" in interact_comp:
			interact_comp.set_deferred("monitorable", false)
		else:
			interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	var look_basis: Basis = Basis.looking_at(-snap_normal, Vector3.UP)
	var tween: Tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(holder, "global_position", target_stand_pos, snap_duration)
	var rot_quat: Quaternion = look_basis.get_rotation_quaternion()
	tween.tween_property(holder, "quaternion", rot_quat, snap_duration)

	tween.chain().tween_callback(_finish_pickup)


## Completes pickup tween and locks physics axes for pushing.
func _finish_pickup() -> void:
	print("HeavyPickableBox: _finish_pickup() executed.")
	_is_animating = false
	is_heavy_held = true
	_grab_time = Time.get_ticks_msec()
	_fall_velocity = 0.0

	global_rotation.x = 0.0
	global_rotation.z = 0.0

	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

	axis_lock_linear_x = false
	axis_lock_linear_y = false
	axis_lock_linear_z = false

	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true

	var fwd: Vector3 = -holder.global_transform.basis.z
	fwd.y = 0.0
	_locked_player_fwd = fwd.normalized()

	notify_holder_stun(holder, false)
	notify_holder_heavy_carry(holder, true, mass)
	notify_holder_heavy_lifting(holder, true)


## Pushes box along floor geometry without heap allocations.
func _physics_process(delta: float) -> void:
	if is_heavy_held and holder:
		if _is_animating:
			return

		var drop_distance_sq: float = drop_distance * drop_distance
		if global_position.distance_squared_to(holder.global_position) > drop_distance_sq:
			drop()
			return

		if abs(holder.global_position.y - global_position.y) > 0.8:
			drop()
			return

		var player_fwd: Vector3 = _locked_player_fwd
		var hold_dist: float = box_half_width + player_radius + hold_padding
		var target_pos: Vector3 = holder.global_position + (player_fwd * hold_dist)
		target_pos.y = global_position.y

		var motion: Vector3 = target_pos - global_position
		var max_speed: float = 8.0 * delta

		if motion.length() > max_speed:
			motion = motion.normalized() * max_speed

		_fall_velocity -= gravity * delta
		motion.y += _fall_velocity * delta

		var col: KinematicCollision3D = move_and_collide(motion)
		if col:
			if col.get_normal().y > 0.5:
				_fall_velocity = 0.0

			var remainder: Vector3 = motion.slide(col.get_normal())
			remainder.y = min(0.0, remainder.y)
			move_and_collide(remainder)

		var is_supported: bool = false
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var ray_end: Vector3 = global_position + (Vector3.DOWN * (box_half_width + 0.2))
		_ground_query.from = global_position
		_ground_query.to = ray_end
		_ground_query.exclude = _cached_exclude_rids

		var hit: Dictionary = space_state.intersect_ray(_ground_query)
		if not hit.is_empty():
			is_supported = true

		if not is_supported:
			drop()
			return

		var p_pos_2d: Vector2 = Vector2(holder.global_position.x, holder.global_position.z)
		var b_pos_2d: Vector2 = Vector2(global_position.x, global_position.z)
		var dist_flat_sq: float = p_pos_2d.distance_squared_to(b_pos_2d)
		var safe_dist: float = box_half_width + player_radius + 0.15
		var safe_dist_sq: float = safe_dist * safe_dist

		if dist_flat_sq < safe_dist_sq:
			var dist_flat: float = sqrt(dist_flat_sq)
			var overlap: float = safe_dist - dist_flat
			var push_dir: Vector2 = (p_pos_2d - b_pos_2d).normalized()

			if push_dir.length_squared() < 0.001:
				push_dir = Vector2(player_fwd.x, player_fwd.z)

			var push_vec: Vector3 = Vector3(push_dir.x * overlap, 0.0, push_dir.y * overlap)

			if holder.has_method("move_and_collide"):
				holder.call("move_and_collide", push_vec)
			else:
				holder.global_position += push_vec

			var post_p_2d: Vector2 = Vector2(holder.global_position.x, holder.global_position.z)
			var safe_dist_margin: float = safe_dist - 0.05
			var safe_dist_margin_sq: float = safe_dist_margin * safe_dist_margin
			if post_p_2d.distance_squared_to(b_pos_2d) < safe_dist_margin_sq:
				drop()
				return


## Releases the box from the player, restoring physics behaviors.
func drop() -> void:
	print("HeavyPickableBox: drop() executed.")
	if _is_animating:
		return

	_is_animating = true
	is_heavy_held = false

	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false

	axis_lock_linear_x = false
	axis_lock_linear_z = false

	freeze = false

	if is_instance_valid(holder):
		var previous_holder: Node3D = holder
		holder = null
		notify_holder_stun(previous_holder, true)
		if "velocity" in previous_holder:
			previous_holder.set("velocity", Vector3.ZERO)
		_finish_drop(previous_holder)
	else:
		_finish_drop(null)


## Finalizes drop state and restores player locomotion systems.
func _finish_drop(previous_holder: Node3D) -> void:
	print("HeavyPickableBox: _finish_drop() restoring systems.")
	_is_animating = false

	if is_instance_valid(previous_holder):
		notify_holder_stun(previous_holder, false)
		notify_holder_heavy_carry(previous_holder, false, 0.0)
		notify_holder_heavy_lifting(previous_holder, false)
		notify_holder_clear_hands(previous_holder)
		wait_to_enable_collision(previous_holder)

	_cached_exclude_rids = [get_rid()]

	if is_instance_valid(interact_comp):
		if "monitorable" in interact_comp:
			interact_comp.set_deferred("monitorable", true)
		else:
			interact_comp.process_mode = Node.PROCESS_MODE_INHERIT


## Prevents throwing heavy boxes by redirecting to [method drop].
func throw(_impulse: Vector3) -> void:
	print("HeavyPickableBox: throw() executed. Redirecting to drop().")
	drop()


## Returns true if player standoff geometry is clear of obstruction.
func is_valid_pickup_position(player: Node3D) -> bool:
	var p_pos: Vector3 = player.global_position
	var b_pos: Vector3 = global_position
	var height_diff: float = p_pos.y - b_pos.y
	var flat_dist: float = Vector2(p_pos.x - b_pos.x, p_pos.z - b_pos.z).length()

	if height_diff > 0.3 and flat_dist < (box_half_width + 0.3):
		return false

	return true
