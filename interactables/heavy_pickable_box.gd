class_name HeavyPickableBox
extends PickableObject

@export_group("Movement Settings")
## Drop distance.
@export var drop_distance: float = 2.5
## Snap duration.
@export var snap_duration: float = 0.3

@export_group("Box Dimensions")
## Box half width.
@export var box_half_width: float = 1.0

@export_group("Player Settings")
## Player radius.
@export var player_radius: float = 0.5
## Player height.
@export var player_height: float = 1.8
## Hold padding.
@export var hold_padding: float = 0.75
## Environment collision mask.
@export_flags_3d_physics var environment_collision_mask: int = 1

## Is heavy held.
var is_heavy_held: bool = false
## Is animating.
var _is_animating: bool = false
## Locked player fwd.
var _locked_player_fwd: Vector3 = Vector3.ZERO
## Fall velocity.
var _fall_velocity: float = 0.0


func pick_up(_target: Marker3D, player: Node3D) -> void:
	print("HeavyPickableBox: pick_up() executed. Attempting to lift the box.")
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
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = player_radius * 0.8
	shape.height = player_height * 0.8

	query.shape = shape
	var query_y: float = target_stand_pos.y + (player_height / 2.0) + 0.5
	var query_pos: Vector3 = Vector3(target_stand_pos.x, query_y, target_stand_pos.z)

	query.transform = Transform3D(Basis(), query_pos)
	query.collision_mask = environment_collision_mask
	query.exclude = [self.get_rid(), player.get_rid()]

	if not space_state.intersect_shape(query).is_empty():
		return

	_is_animating = true
	holder = player

	add_collision_exception_with(holder)

	if "is_stunned" in holder:
		holder.is_stunned = true

	if interact_comp:
		if "monitorable" in interact_comp:
			interact_comp.set_deferred("monitorable", false)
		else:
			interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	var look_basis: Basis = Basis.looking_at(-snap_normal, Vector3.UP)
	var tween: Tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(holder, "global_position", target_stand_pos, snap_duration)
	tween.tween_property(holder, "quaternion", look_basis.get_rotation_quaternion(), snap_duration)

	tween.chain().tween_callback(_finish_pickup)


func _finish_pickup() -> void:
	print("HeavyPickableBox: _finish_pickup() executed. Box is now actively held.")
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

	if "is_stunned" in holder:
		holder.is_stunned = false

	# --- ROUTE THROUGH COMPONENTS ---
	var int_comp: Node = (
		holder.get("interaction_component") if "interaction_component" in holder else null
	)
	if is_instance_valid(int_comp):
		if "is_heavy_lifting" in int_comp:
			int_comp.is_heavy_lifting = true

		var scanner: Node = (
			int_comp.get("interaction_scanner") if "interaction_scanner" in int_comp else null
		)
		if is_instance_valid(scanner):
			if "heavy_lift_yaw_base" in scanner:
				scanner.heavy_lift_yaw_base = holder.global_rotation.y
			if scanner.has_method("set_heavy_lifting"):
				scanner.set_heavy_lifting(true)

	var loco_comp: Node = (
		holder.get("locomotion_component") if "locomotion_component" in holder else holder
	)
	if is_instance_valid(loco_comp):
		if "can_sprint" in loco_comp:
			loco_comp.can_sprint = false
		if "sprint_active" in loco_comp:
			loco_comp.sprint_active = false


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
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_position, ray_end
		)
		query.exclude = [get_rid(), holder.get_rid()]

		var hit: Dictionary = space_state.intersect_ray(query)
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
				holder.move_and_collide(push_vec)
			else:
				holder.global_position += push_vec

			var post_p_2d: Vector2 = Vector2(holder.global_position.x, holder.global_position.z)
			var safe_dist_margin: float = safe_dist - 0.05
			var safe_dist_margin_sq: float = safe_dist_margin * safe_dist_margin
			if post_p_2d.distance_squared_to(b_pos_2d) < safe_dist_margin_sq:
				drop()
				return


func drop() -> void:
	print("HeavyPickableBox: drop() executed. Detaching box from the player.")
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

	if holder:
		var previous_holder: Node3D = holder
		holder = null

		if "is_stunned" in previous_holder:
			previous_holder.is_stunned = true
		if "velocity" in previous_holder:
			previous_holder.velocity = Vector3.ZERO

		_finish_drop(previous_holder)
	else:
		_finish_drop(null)


func _finish_drop(previous_holder: Node3D) -> void:
	print("HeavyPickableBox: _finish_drop() cleaning up drop state and restoring interaction.")
	_is_animating = false

	if previous_holder:
		if "is_stunned" in previous_holder:
			previous_holder.is_stunned = false

		# --- ROUTE THROUGH COMPONENTS ---
		var int_comp: Node = (
			previous_holder.get("interaction_component")
			if "interaction_component" in previous_holder
			else null
		)
		if is_instance_valid(int_comp):
			if "is_heavy_lifting" in int_comp:
				int_comp.is_heavy_lifting = false

			# THIS IS THE FIX: Tell the Master Component to drop it!
			if int_comp.has_method("force_clear_hands"):
				int_comp.force_clear_hands()
				print("HeavyPickableBox: Confirmed detachment via Master Component.")

			var scanner: Node = (
				int_comp.get("interaction_scanner") if "interaction_scanner" in int_comp else null
			)
			if is_instance_valid(scanner):
				if scanner.has_method("set_heavy_lifting"):
					scanner.set_heavy_lifting(false)

		var loco_comp: Node = (
			previous_holder.get("locomotion_component")
			if "locomotion_component" in previous_holder
			else previous_holder
		)
		if is_instance_valid(loco_comp):
			if "can_sprint" in loco_comp:
				loco_comp.can_sprint = true

		if has_method("_wait_to_enable_collision"):
			_wait_to_enable_collision(previous_holder)

	if interact_comp:
		if "monitorable" in interact_comp:
			interact_comp.set_deferred("monitorable", true)
		else:
			interact_comp.process_mode = Node.PROCESS_MODE_INHERIT


func throw(_impulse: Vector3) -> void:
	print("HeavyPickableBox: throw() executed. Redirecting to drop().")
	drop()


func is_valid_pickup_position(player: Node3D) -> bool:
	var p_pos: Vector3 = player.global_position
	var b_pos: Vector3 = global_position

	var height_diff: float = p_pos.y - b_pos.y
	var flat_dist: float = Vector2(p_pos.x - b_pos.x, p_pos.z - b_pos.z).length()

	if height_diff > 0.3 and flat_dist < (box_half_width + 0.3):
		return false

	return true
