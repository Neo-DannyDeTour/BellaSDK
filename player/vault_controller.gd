class_name VaultController
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
signal vault_started
signal vault_finished
signal crouch_state_changed(is_crouching: bool)

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
## Reference to the character body for physical movement.
@export var player_body: CharacterBody3D
## Reference to the main player camera.
@export var camera: Camera3D
## Reference to the node representing the player's head.
@export var head: Node3D
## Reference to the node representing the player's eye level or view pivot.
@export var eyes: Node3D
## The collision shape used when the player is standing.
@export var standing_collision: CollisionShape3D
## The collision shape used when the player is crouching.
@export var crouching_collision: CollisionShape3D

@export_category("Vault Settings")
## The maximum height difference allowed to consider an obstacle a step rather than a vault.
@export var max_step_height: float = 0.5
## The target depth for the head position during a crouching vault.
@export var crouching_depth: float = 0.7
## The required clearance depth behind the ledge to complete a vault.
@export var vault_depth_clearance: float = 0.5

# --------------------------------------
# VARIABLES
# --------------------------------------
## Tracks if the player is currently executing a vault maneuver.
var is_vaulting: bool = false
## Tracks if the last scan found a valid ledge that can be vaulted.
var can_vault_current_ledge: bool = false
## The 3D position of the ledge currently identified for vaulting.
var current_ledge_point: Vector3 = Vector3.ZERO
## The calculated height of the current vault obstacle.
var current_vault_height: float = 0.0
## Determines if the player must end the vault in a crouching state due to limited headroom.
var current_vault_requires_crouch: bool = false

## Visual indicator showing where a vault will be executed.
var vault_indicator: MeshInstance3D


func _ready() -> void:
	print("VaultController: _ready() called. Initializing and setting up vault indicator.")
	_setup_vault_indicator()


func _setup_vault_indicator() -> void:
	print("VaultController: _setup_vault_indicator() called. Setting up vault indicator.")
	vault_indicator = MeshInstance3D.new()

	var dot_mesh: SphereMesh = SphereMesh.new()
	dot_mesh.radius = 0.03
	dot_mesh.height = 0.06
	vault_indicator.mesh = dot_mesh

	var dot_mat: StandardMaterial3D = StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color.WHITE
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.albedo_color.a = 0.6
	dot_mat.no_depth_test = true

	vault_indicator.material_override = dot_mat
	vault_indicator.top_level = true
	add_child(vault_indicator)
	vault_indicator.hide()


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
func process_vault_scan(max_reach: float = 2.8) -> void:
	print("VaultController: process_vault_scan() called. Processing vault scan.")
	can_vault_current_ledge = false

	if vault_indicator:
		vault_indicator.hide()

	if is_vaulting:
		return

	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var exclude_rids: Array[RID] = [player_body.get_rid()]

	var forward_dir: Vector3 = -camera.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3.ZERO, Vector3.ZERO
	)
	ray_query.exclude = exclude_rids

	# 1. FORWARD CAST (Multi-Height Wall Check & Exclusion Group)
	var heights_to_check: Array[float] = [0.5, 1.0, 1.5]
	var forward_result: Dictionary = {}

	for height_offset: float in heights_to_check:
		var detect_start: Vector3 = player_body.global_position + Vector3(0.0, height_offset, 0.0)
		ray_query.from = detect_start
		ray_query.to = detect_start + (forward_dir * 1.2)

		var hit: Dictionary = space_state.intersect_ray(ray_query)
		if not hit.is_empty():
			if absf(hit["normal"].y) <= 0.2:
				if _is_collider_or_parent_in_group(hit["collider"], "not_climbable"):
					print("VaultController: Ledge rejected. Forward object is 'not_climbable'.")
					return

				forward_result = hit
				break

	if forward_result.is_empty():
		return

	var highest_hit: Vector3 = forward_result["position"]
	var hit_normal: Vector3 = forward_result["normal"]

	# 2. DOWNWARD CAST (Find Ledge)
	var down_start: Vector3 = highest_hit - (hit_normal * 0.15)
	down_start.y = player_body.global_position.y + max_reach

	ray_query.from = down_start
	ray_query.to = down_start + Vector3(0.0, -max_reach - 0.5, 0.0)

	var down_result: Dictionary = space_state.intersect_ray(ray_query)
	if down_result.is_empty() or down_result["normal"].y < 0.7:
		return

	if _is_collider_or_parent_in_group(down_result["collider"], "not_climbable"):
		print("VaultController: Ledge rejected. Top landing surface is 'not_climbable'.")
		return

	var down_collider: Object = down_result["collider"]
	if down_collider is Node and down_collider.is_in_group("not_climbable"):
		print("VaultController: Ledge rejected. Surface is in 'not_climbable' group.")
		return

	var ledge_point: Vector3 = down_result["position"]
	var vault_height: float = ledge_point.y - player_body.global_position.y

	if vault_height <= max_step_height or vault_height > max_reach:
		return

	# 3. CLEARANCE CAST (Headroom Check at Destination)
	var clearance_start: Vector3 = ledge_point + (forward_dir * 0.15) + Vector3(0.0, 0.05, 0.0)
	var clearance_end: Vector3 = clearance_start + Vector3(0.0, 1.8, 0.0)

	ray_query.from = clearance_start
	ray_query.to = clearance_end

	var clearance_result: Dictionary = space_state.intersect_ray(ray_query)
	var requires_crouch: bool = false

	if not clearance_result.is_empty():
		var hit_height: float = clearance_result["position"].y - ledge_point.y
		if hit_height < 0.9:
			return
		requires_crouch = true

	# SUCCESS
	can_vault_current_ledge = true
	current_ledge_point = ledge_point
	current_vault_height = vault_height
	current_vault_requires_crouch = requires_crouch

	if vault_height > 1.6 and vault_indicator:
		var exact_edge: Vector3 = highest_hit
		exact_edge.y = ledge_point.y + 0.03
		exact_edge += hit_normal * 0.05
		vault_indicator.global_position = exact_edge
		vault_indicator.show()


# --------------------------------------
# VAULT EXECUTION
# --------------------------------------
func try_vault(is_currently_crouching: bool) -> bool:
	print("VaultController: try_vault() called. Initiating vault sequence toward ledge point.")
	if not can_vault_current_ledge:
		return false

	can_vault_current_ledge = false

	var forward_dir: Vector3 = -camera.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	vault_indicator.hide()
	_perform_vault(
		current_ledge_point,
		forward_dir,
		current_vault_height,
		current_vault_requires_crouch,
		is_currently_crouching
	)

	return true


func _perform_vault(
	target_point: Vector3,
	forward_dir: Vector3,
	vault_height: float,
	force_crouch: bool,
	is_currently_crouching: bool
) -> void:
	print("VaultController: _perform_vault() called. Vault started.")
	is_vaulting = true
	vault_started.emit()

	if force_crouch:
		if not is_currently_crouching:
			crouch_state_changed.emit(true)
		standing_collision.disabled = true
		crouching_collision.disabled = false

	var vault_time: float = clampf(vault_height * 0.75, 0.4, 1.5)
	var final_pos: Vector3 = target_point + (forward_dir * 0.2)

	var vault_tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	vault_tween.set_parallel(true)

	(
		vault_tween
		. tween_property(player_body, "global_position:y", final_pos.y + 0.1, vault_time * 0.7)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	(
		vault_tween
		. tween_property(player_body, "global_position", final_pos, vault_time * 0.3)
		. set_trans(Tween.TRANS_LINEAR)
		. set_delay(vault_time * 0.7)
	)

	if force_crouch:
		(
			vault_tween
			. tween_property(head, "position:y", crouching_depth, vault_time * 0.6)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)

	var tilt_amount: float = deg_to_rad(5.0)
	(
		vault_tween
		. tween_property(eyes, "rotation:z", tilt_amount, vault_time * 0.5)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	vault_tween.tween_property(eyes, "rotation:z", 0.0, vault_time * 0.5).set_delay(
		vault_time * 0.5
	)

	vault_tween.chain().tween_callback(
		func() -> void:
			is_vaulting = false
			eyes.rotation.z = 0.0

			_ensure_player_unstuck(forward_dir)

			print("VaultController: Vault finished.")
			vault_finished.emit()
	)


func _ensure_player_unstuck(forward_dir: Vector3) -> void:
	print(
		"VaultController: _ensure_player_unstuck() called. Running anti-stuck depenetration routine."
	)

	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = player_body.global_transform
	params.motion = Vector3.ZERO
	params.recovery_as_collision = true

	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	var is_stuck: bool = PhysicsServer3D.body_test_motion(player_body.get_rid(), params, result)

	if is_stuck:
		var push_vector: Vector3 = result.get_travel()

		if push_vector == Vector3.ZERO:
			player_body.global_position -= forward_dir * 0.5
			print("VaultController: Player heavily stuck. Ejected backwards safely.")
		else:
			player_body.global_position += push_vector
			print("VaultController: Geometry overlap detected. Nudged player by: ", push_vector)


func _is_collider_or_parent_in_group(collider: Object, group_name: String) -> bool:
	print(
		"VaultController: _is_collider_or_parent_in_group() called. Checking collider tree for group: ",
		group_name
	)
	if not collider is Node:
		return false

	var current_node: Node = collider as Node

	# Climb up the tree up to 4 levels to check for the group tag
	for i: int in range(4):
		if current_node == null:
			return false
		if current_node.is_in_group(group_name):
			print("VaultController: Found ", group_name, " on node: ", current_node.name)
			return true
		current_node = current_node.get_parent()

	return false
