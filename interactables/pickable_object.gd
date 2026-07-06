class_name PickableObject
extends RigidBody3D

@export_category("Pickable Nodes")
@export var interact_comp: Interact_Component
@export var mesh: Node3D
@export var label: Label3D

@onready var interact_comp: Interact_Component = $Interact_Component
@onready var mesh: Node3D = $Mesh
@onready var label: Label3D = $Label3D
@onready var probe_container: Node3D = $ProbeContainer
@onready var highlight_comp: HighlightComponent = $HighlightComponent
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interaction_shape: CollisionShape3D = $Interact_Component/CollisionShape3D

@export_category("Buoyancy")
@export var probe_container: Node3D
## How strongly the water pushes up. (3.0 is a great value!)
@export var float_force: float = 3.0
## Friction. (May need to increase this to 2.0 or 4.0 to stop bouncing!)
@export var water_drag: float = 0.5
@export var water_angular_drag: float = 0.5

# --- HOLDING CONFIG ---
## How much closer to the player this object should be held.
@export var hold_distance_offset: float = 0.0

## How transparent the object gets when held (0.0 = solid, 1.0 = completely invisible)
@export_range(0.0, 1.0) var held_transparency: float = 0.25

## NEW: The mass at which an object is forced to be held low (e.g., barrels).
@export var heavy_mass_threshold: float = 10.0
## NEW: How far down heavy objects are held (0.5 was your old default).
@export var heavy_y_drop: float = 0.5

var is_held: bool = false
var hold_target: Marker3D = null
var holder: Node3D = null

# --- GLOBAL STATE TRACKING ---
var is_locked: bool = false:
	set(value):
		is_locked = value
		if is_locked:
			if mesh:
				mesh.material_overlay = null
			if label:
				label.hide()
var is_in_water: bool = false:
	set(value):
		if is_in_water != value:
			is_in_water = value
			_update_process_state()
	set(value):
		is_locked = value
		if is_locked:
			if mesh:
				mesh.material_overlay = null
			if label:
				label.hide()
	set(value):
		if is_in_water != value:
			is_in_water = value
			_update_process_state()
var _is_player_flying: bool = false
# --- WATER TRACKING ---
	set(value):
		if is_in_water != value:
			is_in_water = value
			_update_process_state()

var submerged: bool = false
var current_water_node: Node3D = null
	set(value):
		is_locked = value
		if is_locked:
			if mesh:
				mesh.material_overlay = null
			if label:
				label.hide()

var _grab_time: int = 0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	if label:
		label.hide()

	if interact_comp:
		if not interact_comp.focused.is_connected(_on_interact_component_focused):
			interact_comp.focused.connect(_on_interact_component_focused)
		if not interact_comp.unfocused.is_connected(_on_interact_component_unfocused):
			interact_comp.unfocused.connect(_on_interact_component_unfocused)

	# Allow Rigidbody to sleep when sitting still
	sleeping_state_changed.connect(_on_sleeping_state_changed)

	# Listen to the global Event Bus for state changes
	if Events.noclip_toggled.is_connected(_on_noclip_toggled) == false:
		Events.noclip_toggled.connect(_on_noclip_toggled)

	# Initialize process state
	_update_process_state()

	# --- SHADER WARM-UP (Fixes the first-pickup frame drop) ---
	if mesh:
		_set_model_transparency(mesh, held_transparency)
		_revert_warmup_deferred()


func _on_noclip_toggled(is_flying: bool) -> void:
	print("PickableObject: Noclip state updated via Event Bus -> ", is_flying)
	_is_player_flying = is_flying


func _on_sleeping_state_changed() -> void:
	_update_process_state()


func _update_process_state() -> void:
	# OPTIMIZATION: Only run _physics_process if we are held, in water, or actively falling/moving
	var should_process: bool = is_held or is_in_water or not sleeping
	set_physics_process(should_process)


func _revert_warmup_deferred() -> void:
	print("PickableObject: _revert_warmup_deferred() executing shader compilation.")

	# Wait for the GPU to actually render the transparent pipeline state
	await get_tree().process_frame
	await get_tree().process_frame

	if is_instance_valid(mesh):
		_set_model_transparency(mesh, 0.0)


func pick_up(target: Marker3D, player: Node3D) -> void:
	if is_locked:
		return

	print("PickableObject: pick_up() called. Grabbed: ", name)
	_grab_time = Time.get_ticks_msec()
	is_held = true
	hold_target = target
	holder = player

	if label:
		label.hide()

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	sleeping = false
	gravity_scale = 0.0

	if mesh:
		_set_model_transparency(mesh, held_transparency)

	if interact_comp:
		interact_comp.is_currently_focused = false
		interact_comp.unfocused.emit()
		interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

	add_collision_exception_with(holder)
	_update_process_state()

	# Notify the rest of the game that this item was picked up
	Events.item_picked_up.emit(self, holder)


func drop() -> void:
	if Time.get_ticks_msec() - _grab_time < 100:
		return

	print("PickableObject: drop() called. Releasing: ", name)
	is_held = false

	if interact_comp:
		interact_comp.process_mode = Node.PROCESS_MODE_INHERIT

	if is_locked:
		holder = null
		if interact_comp:
			interact_comp.is_currently_focused = false
		_update_process_state()
		return

	freeze = false
	sleeping = false
	gravity_scale = 1.0
	if mesh:
		_set_model_transparency(mesh, 0.0)

	if holder:
		if "velocity" in holder:
			linear_velocity = holder.velocity

		# Safely fetch the camera directly from the viewport
		var cam_forward := Vector3.FORWARD
		var cam: Camera3D = get_viewport().get_camera_3d()
		if is_instance_valid(cam):
			cam_forward = -cam.global_transform.basis.z

		var flat_cam_forward := Vector3(cam_forward.x, 0.0, cam_forward.z)
		var push_dir := flat_cam_forward.normalized()

		# Velocity Compensation
		var player_vel: Vector3 = holder.get("velocity") if "velocity" in holder else Vector3.ZERO
		var velocity_offset := Vector3(player_vel.x, 0.0, player_vel.z) * 0.15

		# Smart Object Nudge (Looking Down Check)
		var is_nudging := false
		if cam_forward.y < -0.2:
			var space_state := get_world_3d().direct_space_state
			var intended_slide := (push_dir * 0.35) + velocity_offset

			var check_dir := intended_slide.normalized()
			var check_dist := intended_slide.length() + 0.1
			var ray_end := global_position + (check_dir * check_dist)

			var query := PhysicsRayQueryParameters3D.create(global_position, ray_end)
			query.exclude = [self.get_rid(), holder.get_rid()]

			var result := space_state.intersect_ray(query)
			var target_pos := global_position

			if result:
				var safe_dist := global_position.distance_to(result.position) - 0.1
				if safe_dist > 0:
					target_pos += check_dir * safe_dist
			else:
				target_pos += intended_slide

			if target_pos != global_position:
				is_nudging = true
				angular_velocity = Vector3.ZERO

				var nudge_tween := create_tween()
				(
					nudge_tween
					. tween_property(self, "global_position:x", target_pos.x, 0.15)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_OUT)
				)
				(
					nudge_tween
					. parallel()
					. tween_property(self, "global_position:z", target_pos.z, 0.15)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_OUT)
				)

				nudge_tween.tween_callback(
					func() -> void:
						var toss_dir := push_dir
						toss_dir.y = 0.5
						apply_central_impulse(toss_dir * 5.0)
				)

		# Standard toss if we didn't tween it
		if not is_nudging:
			push_dir.y = 0.5
			apply_central_impulse(push_dir * 5.0)

		# Broadcast the drop event globally. The player's InteractionComponent
		# should connect to this signal and nullify its own variables.
		Events.item_dropped.emit(self, holder)

		var previous_holder := holder
		_wait_to_enable_collision(previous_holder)

	holder = null
	if interact_comp:
		interact_comp.is_currently_focused = false

	_update_process_state()


func _attempt_enable_collision(player: Node3D) -> void:
	if not is_instance_valid(self) or not is_instance_valid(player):
		return

	# Check the distance between the box and the player
	var distance := global_position.distance_to(player.global_position)

	# 1.5 meters is usually safe, but you can increase this if your player has a wide collision shape
	if distance > 1.5:
		remove_collision_exception_with(player)
	else:
		# If they are still overlapping, wait 0.1s and recursively check again.
		# This allows you to walk away from the box without getting teleported!
		get_tree().create_timer(0.1).timeout.connect(_attempt_enable_collision.bind(player))


func throw(impulse_vector: Vector3) -> void:
	print(
		"PickableObject: throw() called. Throwing: ", name, " with force: ", impulse_vector.length()
	)
	drop()
	if not is_locked:
		apply_central_impulse(impulse_vector)


func _on_interact_component_focused() -> void:
	print("PickableObject: _on_interact_component_focused() called. Highlighting object.")
	if is_locked:
		return

	# 1. If we are holding it, NO highlight and NO label. Bail out!
	if is_held:
		# Verify mesh is a GeometryInstance3D before trying to access material_overlay
		if is_instance_valid(mesh) and mesh is GeometryInstance3D:
			mesh.material_overlay = null
		return

	# 3. Show the label
	if is_instance_valid(label):
		_update_label_text()
		label.show()


func _update_label_text() -> void:
	if not label:
		return
	var events := InputMap.action_get_events("interact")
	var key_name := "???"
	if events.size() > 0:
		var raw_text := events[0].as_text()
		key_name = (
			raw_text
			. replace(" (Physical)", "")
			. replace(" - Physical", "")
			. replace(" (Physics)", "")
			. replace(" - Physics", "")
			. replace("Left Mouse Button", "LMB")
			. replace("Right Mouse Button", "RMB")
			. replace("Middle Mouse Button", "MMB")
			. strip_edges()
		)
	label.text = "[%s]" % [key_name]


func _on_interact_component_unfocused() -> void:
	print("PickableObject: _on_interact_component_unfocused() called. Removing highlight.")
	if label:
		label.hide()


func _physics_process(_delta: float) -> void:
	if is_held and is_instance_valid(hold_target) and is_instance_valid(holder):
		var target_pos: Vector3 = hold_target.global_position

		# 1. APPLY OFFSETS FIRST
		var player_pos: Vector3 = holder.global_position

		# Safely fetch the camera directly from the viewport
		var cam_forward := Vector3.FORWARD
		var cam: Camera3D = get_viewport().get_camera_3d()
		if is_instance_valid(cam):
			cam_forward = -cam.global_transform.basis.z

		# Pull closer to face based on export setting
		target_pos -= cam_forward * hold_distance_offset

		# --- ADVANCED MASS MATH ---
		# 0.0 for things 5kg and under (Valves). 1.0 for 10kg and over (Barrels).
		var weight_ratio: float = clampf((mass - 5.0) / 5.0, 0.0, 1.0)

		# 1. BASE DROP: Heavy items sag down automatically. Light items (0.0) have NO drop.
		var current_y_drop: float = lerpf(0.0, 0.5, weight_ratio)
		target_pos.y -= current_y_drop

		# 2. THE "NO-DIP" LOOK-DOWN LOGIC
		# By multiplying by weight_ratio, a 5kg object multiplies this by 0.0 (No dip at all!)
		# A 10kg barrel will multiply by 1.0, pulling it down as you look at your toes.
		if cam_forward.y < 0.0:
			var dip_strength: float = absf(cam_forward.y) * 6.0
			target_pos.y -= (dip_strength * weight_ratio)

		# 3. THE UNBREAKABLE CEILING
		# We base this on your FEET (player_pos.y), NOT the camera.
		# Light objects can go up to 3 meters (above head). Heavy objects hard-capped at 1.0 meter.
		var max_allowed_height: float = lerpf(player_pos.y + 3.0, player_pos.y + 1.0, weight_ratio)

		if target_pos.y > max_allowed_height:
			target_pos.y = max_allowed_height

		# 2. APPLY CONSTRAINTS (Hula Hoop & Floor)
		var flat_offset := Vector2(target_pos.x - player_pos.x, target_pos.z - player_pos.z)
		if flat_offset.length() < 0.8:
			flat_offset = flat_offset.normalized() * 0.8
			target_pos.x = player_pos.x + flat_offset.x
			target_pos.z = player_pos.z + flat_offset.y

		# --- PURE FLOOR CLAMP ---
		# 0.2 meters above your feet gives it a nice physical resting spot on the ground.
		var min_height: float = player_pos.y + 0.2

		if target_pos.y < min_height:
			target_pos.y = min_height

		# 3. NOW DO THE SNAG CHECK
		var distance_to_target := global_position.distance_to(target_pos)

		# Evaluate flying locally based on Event Bus state
		if distance_to_target > 1.5 and not _is_player_flying:
			drop()
			return

		# 4. APPLY PHYSICS MOVE
		var distance_vector := target_pos - global_position
		linear_velocity = distance_vector * 15.0

		# --- ROTATION LOGIC ---
		var target_basis: Basis = holder.global_basis

		var diff_quat := (
			target_basis.get_rotation_quaternion()
			* global_basis.get_rotation_quaternion().inverse()
		)
		var axis := Vector3(diff_quat.x, diff_quat.y, diff_quat.z)
		var angle := 2.0 * acos(clampf(diff_quat.w, -1.0, 1.0))
		if angle > PI:
			angle -= TAU

		if axis.length_squared() > 0.0001:
			angular_velocity = axis.normalized() * (angle * 20.0)
		else:
			angular_velocity = Vector3.ZERO
		return

	# 2. MULTI-PROBE BUOYANCY
	submerged = false

	if is_in_water and is_instance_valid(current_water_node) and is_instance_valid(probe_container):
		var probe_count: int = probe_container.get_child_count()
		var probe_mass: float = mass / float(probe_count)

		for p: Node3D in probe_container.get_children():
			var wave_height: float = current_water_node.get_wave_height_at_pos(p.global_position)
			var depth: float = wave_height - p.global_position.y

			if depth > 0.0:
				submerged = true

				# --- THE SURFACE & PLUNGE FIX ---
				var depth_multiplier: float = clampf(depth * 4.0, 0.0, 4.0)

				var force: Vector3 = (
					Vector3.UP * probe_mass * float_force * gravity * depth_multiplier
				)
				var offset: Vector3 = p.global_position - global_position
				apply_force(force, offset)

	# 3. DRAG
	if submerged and not is_held:
		apply_central_force(-linear_velocity * water_drag * mass)
		apply_torque(-angular_velocity * water_angular_drag * mass)


func _wait_to_enable_collision(player: Node3D) -> void:
	var max_wait_frames := 30
	var current_frame := 0

	while is_instance_valid(self) and is_instance_valid(player) and current_frame < max_wait_frames:
		var flat_my_pos := Vector2(global_position.x, global_position.z)
		var flat_player_pos := Vector2(player.global_position.x, player.global_position.z)

		# Slightly tightened the clearance check from 1.2 to 1.0 for better feel
		if flat_my_pos.distance_to(flat_player_pos) >= 1.0:
			break

		current_frame += 1
		await get_tree().physics_frame

	if is_instance_valid(self) and is_instance_valid(player):
		var flat_my_pos := Vector2(global_position.x, global_position.z)
		var flat_player_pos := Vector2(player.global_position.x, player.global_position.z)

		# If they are STILL overlapping after the timer...
		if flat_my_pos.distance_to(flat_player_pos) < 1.0:
			var player_forward := -player.global_transform.basis.z
			var flat_backward := Vector3(-player_forward.x, 0.0, -player_forward.z).normalized()

			# 1. MUCH SMALLER DISTANCE (0.6 meters instead of 1.5)
			var push_distance := 0.2
			var push_vector := flat_backward * push_distance

			# 2. TEST THE WALL COLLISION (true = test_only)
			var safe_travel := push_vector
			var collision: KinematicCollision3D = player.move_and_collide(push_vector, true)
			if collision:
				safe_travel = collision.get_travel()

			var target_pos := player.global_position + safe_travel

			# 3. SMOOTH TWEEN SLIDE
			var tween := get_tree().create_tween()
			(
				tween
				. tween_property(player, "global_position", target_pos, 0.15)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_OUT)
			)

			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO

			# 4. TURN COLLISION ON *AFTER* THE TWEEN FINISHES
			tween.tween_callback(
				func() -> void:
					if is_instance_valid(self) and is_instance_valid(player):
						remove_collision_exception_with(player)
			)
			return  # Exit early so we don't accidentally enable collision below

		# If they stepped away naturally and no tween was needed, turn collision on immediately
		remove_collision_exception_with(player)


# --- Recursive Transparency Function ---
func _set_model_transparency(parent_node: Node, alpha: float) -> void:
	if not is_instance_valid(parent_node):
		return

	# If this specific piece is a mesh, make it transparent
	if parent_node is MeshInstance3D:
		parent_node.transparency = alpha

	# Dig through all of its children and do the exact same thing
	for child: Node in parent_node.get_children():
		_set_model_transparency(child, alpha)
