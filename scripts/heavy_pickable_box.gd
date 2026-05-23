extends PickableObject
class_name HeavyPickableBox

var is_heavy_held: bool = false
var _is_animating: bool = false

@export_group("Movement Settings")
@export var drop_distance: float = 2.5
@export var snap_duration: float = 0.3

@export_group("Box Dimensions")
@export var box_half_width: float = 1.0

@export_group("Player Settings")
@export var player_radius: float = 0.5
@export var player_height: float = 1.8
@export var hold_padding: float = 0.75
@export_flags_3d_physics var environment_collision_mask: int = 1


func pick_up(_target: Marker3D, player: Node3D) -> void:
	if is_locked or _is_animating:
		return

	# ---------------------------------------------------------
	# 1. FIXED ANTI-STAND LOGIC
	# ---------------------------------------------------------
	if not is_valid_pickup_position(player):
		return

	var to_player := player.global_position - global_position

	var height_diff := player.global_position.y - global_position.y
	var flat_dist := (
		Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	)

	# Lowered the height threshold to 0.3. If your feet are slightly above the center, it rejects the grab.
	if height_diff > 0.3 and flat_dist < (box_half_width + 0.3):
		return

	to_player.y = 0
	to_player = to_player.normalized()

	var b_fwd := -global_transform.basis.z.normalized()
	var b_right := global_transform.basis.x.normalized()

	var snap_normal: Vector3
	if abs(to_player.dot(b_fwd)) > abs(to_player.dot(b_right)):
		snap_normal = b_fwd if to_player.dot(b_fwd) > 0 else -b_fwd
	else:
		snap_normal = b_right if to_player.dot(b_right) > 0 else -b_right

	var hold_distance := box_half_width + player_radius + hold_padding
	var target_stand_pos := global_position + (snap_normal * hold_distance)
	target_stand_pos.y = player.global_position.y

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = player_radius * 0.8
	shape.height = player_height * 0.8
	query.shape = shape
	query.transform = Transform3D(Basis(), target_stand_pos + Vector3(0, (player_height / 2) + 0.5, 0))
	query.collision_mask = environment_collision_mask
	query.exclude = [self.get_rid(), player.get_rid()]

	if not space_state.intersect_shape(query).is_empty():
		return

	_is_animating = true
	holder = player

	# ---------------------------------------------------------
	# 2. THE GHOST PLAYER TRICK
	# ---------------------------------------------------------
	# The box ignores the player so you can walk forward without being blocked.
	add_collision_exception_with(holder)

	if "is_stunned" in holder:
		holder.is_stunned = true
	if interact_comp:
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	var look_at_box_basis := Basis.looking_at(-snap_normal, Vector3.UP)
	var tween := get_tree().create_tween().set_parallel(true)
	tween.tween_property(holder, "global_position", target_stand_pos, snap_duration)
	tween.tween_property(holder, "quaternion", look_at_box_basis.get_rotation_quaternion(), snap_duration)

	tween.chain().tween_callback(_finish_pickup)


func _finish_pickup() -> void:
	_is_animating = false
	is_heavy_held = true
	_grab_time = Time.get_ticks_msec()

	global_rotation.x = 0.0
	global_rotation.z = 0.0

	# Keep rotation locked so it doesn't spin while held
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

	# ---------------------------------------------------------
	# NEW: UNLOCK LINEAR MOVEMENT
	# ---------------------------------------------------------
	# Free the horizontal movement so move_and_collide works again
	axis_lock_linear_x = false
	axis_lock_linear_y = false
	axis_lock_linear_z = false

	# Box becomes a moving kinematic wall
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true

	if "is_stunned" in holder:
		holder.is_stunned = false
	if "is_heavy_lifting" in holder:
		holder.is_heavy_lifting = true


func _physics_process(delta: float) -> void:
	if is_heavy_held and holder:
		if _is_animating:
			return

		# 1. TIGHTEN THE VERTICAL DROP THRESHOLD
		if abs(holder.global_position.y - global_position.y) > 0.8:
			drop()
			return

		var player_fwd := -holder.global_transform.basis.z
		player_fwd.y = 0.0
		player_fwd = player_fwd.normalized()

		var hold_distance := box_half_width + player_radius + hold_padding
		var target_pos := holder.global_position + (player_fwd * hold_distance)
		target_pos.y = global_position.y

		if global_position.distance_to(target_pos) > drop_distance:
			drop()
			return

		var motion := target_pos - global_position

		# ---------------------------------------------------------
		# 2. CAMERA SWING FIX (Move the box FIRST)
		# ---------------------------------------------------------
		var max_speed := 8.0 * delta
		if motion.length() > max_speed:
			motion = motion.normalized() * max_speed

		# Sweep the box forward. If it hits a wall, it stops physically.
		var col := move_and_collide(motion)
		if col:
			var remainder := motion.slide(col.get_normal())
			remainder.y = min(0.0, remainder.y)
			move_and_collide(remainder)

		# ---------------------------------------------------------
		# 3. VIRTUAL COLLISION (The Anti-Noclip Fix!)
		# ---------------------------------------------------------
		var p_pos_2d := Vector2(holder.global_position.x, holder.global_position.z)
		var b_pos_2d := Vector2(global_position.x, global_position.z)
		var dist_flat := p_pos_2d.distance_to(b_pos_2d)

		# ADDED + 0.15 BUFFER HERE:
		var safe_dist := box_half_width + player_radius + 0.15

		if dist_flat < safe_dist:
			var overlap := safe_dist - dist_flat
			var push_dir := (p_pos_2d - b_pos_2d).normalized()

			# Fallback just in case the positions are perfectly identical
			if push_dir.length_squared() < 0.001:
				push_dir = Vector2(player_fwd.x, player_fwd.z)

			var push_vec := Vector3(push_dir.x * overlap, 0.0, push_dir.y * overlap)

			# Shove the player backward!
			# Using move_and_collide prevents pushing the player through a wall behind them.
			if holder.has_method("move_and_collide"):
				holder.move_and_collide(push_vec)
			else:
				holder.global_position += push_vec

			# ---------------------------------------------------------
			# 4. THE SANDWICH CHECK (Squish Check V2)
			# ---------------------------------------------------------
			# If we pushed the player, but they were pinned against a wall behind them,
			# they won't move, and will still be too close to the box.
			# We MUST drop the box to prevent game-breaking physics glitches.
			var post_push_p_2d := Vector2(holder.global_position.x, holder.global_position.z)
			if post_push_p_2d.distance_to(b_pos_2d) < safe_dist - 0.05:
				drop()
				return


func drop() -> void:
	if _is_animating:
		return

	_is_animating = true
	is_heavy_held = false

	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true

	axis_lock_linear_x = true
	axis_lock_linear_z = true

	freeze = false

	if holder:
		var previous_holder := holder
		holder = null

		if "is_stunned" in previous_holder:
			previous_holder.is_stunned = true
		if "velocity" in previous_holder:
			previous_holder.velocity = Vector3.ZERO

		var p_pos_2d := Vector2(previous_holder.global_position.x, previous_holder.global_position.z)
		var b_pos_2d := Vector2(global_position.x, global_position.z)

		var push_dir := (p_pos_2d - b_pos_2d).normalized()

		if push_dir.length_squared() < 0.001:
			push_dir = (
				Vector2(-previous_holder.global_transform.basis.z.x, -previous_holder.global_transform.basis.z.z)
				. normalized()
			)

		var safe_dist := box_half_width + player_radius + 0.2

		var target_pos_2d := b_pos_2d + (push_dir * safe_dist)
		var target_pos := Vector3(target_pos_2d.x, previous_holder.global_position.y, target_pos_2d.y)

		var eject_vec := target_pos - previous_holder.global_position

		# ---------------------------------------------------------
		# THE FIX: PREVENT FALSE COLLISION HITS
		# ---------------------------------------------------------
		# 1. Temporarily turn off the Box so the Player doesn't hit it during the test
		var old_mask := collision_mask
		var old_layer := collision_layer
		collision_mask = 0
		collision_layer = 0

		if previous_holder is CharacterBody3D:
			var wall_hit: KinematicCollision3D = previous_holder.move_and_collide(eject_vec, true)
			if wall_hit != null:
				# 2. Only stop the tween if we hit a vertical WALL, ignore the floor!
				if abs(wall_hit.get_normal().y) < 0.5:
					var allowed_travel := wall_hit.get_travel()
					target_pos = previous_holder.global_position + (allowed_travel * 0.95)

		# 3. Restore the Box collision immediately
		collision_mask = old_mask
		collision_layer = old_layer
		# ---------------------------------------------------------

		var detach_tween := get_tree().create_tween()

		(
			detach_tween
			. tween_property(previous_holder, "global_position", target_pos, 0.5)
			. set_ease(Tween.EASE_OUT)
			. set_trans(Tween.TRANS_QUAD)
		)

		detach_tween.tween_callback(func() -> void: _finish_drop(previous_holder))
	else:
		_finish_drop(null)


func _finish_drop(previous_holder: Node3D) -> void:
	_is_animating = false

	if previous_holder:
		# ---------------------------------------------------------
		# NEW: RELEASE THE PLAYER STUN LOCK
		# ---------------------------------------------------------
		if "is_stunned" in previous_holder:
			previous_holder.is_stunned = false

		if "is_heavy_lifting" in previous_holder:
			previous_holder.is_heavy_lifting = false

		if "held_object" in previous_holder:
			previous_holder.held_object = null
		elif "grabbed_object" in previous_holder:
			previous_holder.grabbed_object = null

		remove_collision_exception_with(previous_holder)

		if has_method("_wait_to_enable_collision"):
			_wait_to_enable_collision(previous_holder)

	if interact_comp:
		interact_comp.process_mode = Node.PROCESS_MODE_INHERIT


func throw(_impulse: Vector3) -> void:
	drop()


func is_valid_pickup_position(player: Node3D) -> bool:
	var height_diff := player.global_position.y - global_position.y
	var flat_dist := (
		Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	)

	# If the player's feet are above the center and they are on top of the box
	if height_diff > 0.3 and flat_dist < (box_half_width + 0.3):
		return false

	return true
