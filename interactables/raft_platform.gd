## Buoyant floating raft platform with four barrel pontoons supporting heavy carry and riding.
class_name RaftPlatform
extends PickableObject

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Default mass scalar in kilograms providing heavy carry resistance and buoyancy stability.
const DEFAULT_RAFT_MASS: float = 60.0

## Target vertical center of mass offset placing ballast below waterline.
const DEFAULT_COM_OFFSET_Y: float = -0.35

## Default standoff distance offset pulling large raft platform forward during carry.
const DEFAULT_HOLD_OFFSET: float = -1.6

## Maximum detach distance threshold before dropping large platform.
const DEFAULT_DETACH_DISTANCE: float = 3.6

## Pre-allocated group name matching water trigger volumes in scene tree.
const GROUP_WATER_AREA_NAME: StringName = &"water_area"

## Pre-allocated method name for registering body entry with water volumes.
const METHOD_ENTER_WATER_NAME: StringName = &"enter_water"

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_group("Raft Stability")
## Vertical center of mass offset below deck origin to prevent capsizing.
@export var com_offset_y: float = DEFAULT_COM_OFFSET_Y


# --------------------------------------
# LIFECYCLE
# --------------------------------------
## Configures raft buoyancy parameters, heavy carry offsets, and center of mass ballast.
func _ready() -> void:
	# Ensure raft stays dynamic so player weight and water waves pitch/roll naturally
	lock_on_player_stand = false

	if mass <= 0.0 or mass == 1.0:
		mass = DEFAULT_RAFT_MASS

	hold_distance_offset = DEFAULT_HOLD_OFFSET
	max_detach_distance = DEFAULT_DETACH_DISTANCE

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, com_offset_y, 0.0)

	super._ready()
	print("RaftPlatform: Initialized ", name, " with mass ", mass, "kg.")
	_check_initial_water_overlap_deferred.call_deferred()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Checks if raft was placed submerged on initial startup and wakes up buoyancy immediately.
func _check_initial_water_overlap_deferred() -> void:
	if not is_inside_tree() or is_in_water:
		return

	var water_areas: Array[Node] = get_tree().get_nodes_in_group(GROUP_WATER_AREA_NAME)
	for node: Node in water_areas:
		var area: Area3D = node as Area3D
		if not is_instance_valid(area):
			continue

		var water_parent: Node3D = area.get_parent() as Node3D
		if not is_instance_valid(water_parent):
			continue

		var is_inside: bool = false
		if water_parent.has_method(&"get_wave_height_at_pos"):
			var surface_y: float = float(
				water_parent.call(&"get_wave_height_at_pos", global_position)
			)
			var raw_water_size: Variant = water_parent.get(&"water_size")
			var half_size: Vector3 = Vector3(500.0, 500.0, 500.0)
			if raw_water_size is Vector3:
				var size_vec: Vector3 = raw_water_size
				half_size = size_vec * 0.5

			var local_pos: Vector3 = water_parent.to_local(global_position)
			if (
				absf(local_pos.x) <= half_size.x
				and absf(local_pos.z) <= half_size.z
				and global_position.y <= surface_y
				and local_pos.y >= -half_size.y
			):
				is_inside = true

		if is_inside:
			print("RaftPlatform: Detected initial placement inside water -> ", water_parent.name)
			current_water_node = water_parent
			is_in_water = true
			sleeping = false

			if water_parent.has_method(METHOD_ENTER_WATER_NAME):
				water_parent.call(METHOD_ENTER_WATER_NAME, self)
			elif water_parent.has_method(&"_on_body_entered"):
				water_parent.call(&"_on_body_entered", self)
			elif water_parent.has_method(&"_on_swimmable_area_body_entered"):
				water_parent.call(&"_on_swimmable_area_body_entered", self)

			_update_process_state()
			break


## Solves carry spring velocities while preserving exact grab yaw to prevent 180 flip.
func _process_standard_hold(_delta: float) -> void:
	var target_pos: Vector3 = hold_target.global_position
	var cam: Camera3D = _get_camera()
	var cam_origin: Vector3 = (
		cam.global_position if is_instance_valid(cam) else holder.global_position
	)
	var cam_forward: Vector3 = (
		-cam.global_transform.basis.z if is_instance_valid(cam) else Vector3.FORWARD
	)

	var is_heavy: bool = mass >= heavy_mass_threshold

	if is_heavy:
		var flat_forward: Vector3 = Vector3(cam_forward.x, 0.0, cam_forward.z).normalized()
		var carry_dist: float = maxf(MIN_HOLD_DISTANCE - hold_distance_offset, 1.1)
		target_pos = holder.global_position + (flat_forward * carry_dist)

		var bottom_extent: float = _get_upright_bottom_extent()
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var floor_hit: Dictionary = NodeQuery.cast_ray(
			space_state,
			target_pos + Vector3(0.0, 0.5, 0.0),
			target_pos + Vector3(0.0, -2.0, 0.0),
			CollisionLayers.MASK_ENVIRONMENT,
			_cached_exclude_rids
		)
		if not floor_hit.is_empty():
			var hit_pos: Vector3 = floor_hit.get("position", Vector3.ZERO)
			var ground_y: float = hit_pos.y
			target_pos.y = ground_y + bottom_extent + heavy_floor_clearance
		else:
			target_pos.y = (
				holder.global_position.y + bottom_extent + heavy_floor_clearance - heavy_y_drop
			)
	else:
		var to_target: Vector3 = target_pos - cam_origin
		var forward_projection: float = to_target.dot(cam_forward)
		var required_dist: float = maxf(MIN_HOLD_DISTANCE - hold_distance_offset, 0.8)

		if forward_projection < required_dist:
			target_pos += cam_forward * (required_dist - forward_projection)

	var dist_sq: float = global_position.distance_squared_to(target_pos)
	var has_grab_settled: bool = (Time.get_ticks_msec() - _grab_time) > 250
	var detach_threshold_sq: float = max_detach_distance * max_detach_distance
	if dist_sq > detach_threshold_sq and has_grab_settled and not _is_player_flying:
		drop()
		return

	var holder_velocity: Vector3 = Vector3.ZERO
	if "velocity" in holder:
		var raw_vel: Variant = holder.get(&"velocity")
		if raw_vel is Vector3:
			holder_velocity = raw_vel

	var distance_vector: Vector3 = target_pos - global_position
	var pos_stiffness: float = 14.0 if is_heavy else 20.0
	linear_velocity = holder_velocity + (distance_vector * pos_stiffness)

	var cam_yaw: float = (
		cam.global_transform.basis.get_euler().y
		if is_instance_valid(cam)
		else holder.global_transform.basis.get_euler().y
	)

	# Preserve exact relative grab yaw without lerping to 0.0 (prevents 180 flip)
	var target_yaw: float = cam_yaw + _held_relative_yaw
	var target_basis: Basis = Basis.from_euler(Vector3(0.0, target_yaw, 0.0))

	var q_target: Quaternion = target_basis.get_rotation_quaternion()
	var q_current: Quaternion = global_basis.get_rotation_quaternion()
	var q_diff: Quaternion = q_target * q_current.inverse()
	if q_diff.w < 0.0:
		q_diff = -q_diff

	var angle: float = 2.0 * acos(clampf(q_diff.w, -1.0, 1.0))
	var axis_len_sq: float = q_diff.x * q_diff.x + q_diff.y * q_diff.y + q_diff.z * q_diff.z

	var rot_stiffness: float = 8.0 if is_heavy else 18.0
	if axis_len_sq > 0.0001:
		var axis: Vector3 = Vector3(q_diff.x, q_diff.y, q_diff.z) / sqrt(axis_len_sq)
		angular_velocity = axis * (angle * rot_stiffness)
	else:
		angular_velocity = Vector3.ZERO
