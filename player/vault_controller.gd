## Manages multi-height raycasts, ledge finding, and vault animation execution.
class_name VaultController
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when a vault movement sequence starts.
signal vault_started
## Emitted when a vault movement sequence completes.
signal vault_finished
## Emitted when crouching stance toggles during a vault.
signal crouch_state_changed(is_crouching: bool)

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
## Character body used for physical movement.
@export var player_body: CharacterBody3D
## Camera used to derive forward heading.
@export var camera: Camera3D
## Head node used for camera vertical offsets.
@export var head: Node3D
## Eye level node used for rotational roll tilts.
@export var eyes: Node3D
## Full-height physical collision shape.
@export var standing_collision: CollisionShape3D
## Crouch-height physical collision shape.
@export var crouching_collision: CollisionShape3D

@export_category("Vault Settings")
## Maximum height considered a step instead of a vault.
@export var max_step_height: float = 0.5
## Target depth for the head position during crouching vaults.
@export var crouching_depth: float = 0.7
## Clearance depth required behind the ledge to complete a vault.
@export var vault_depth_clearance: float = 0.5
## Automatically scans for vaultable ledges during physics frames.
@export var auto_scan: bool = true

# --------------------------------------
# VARIABLES
# --------------------------------------
## Tracks whether a vault tween sequence is actively executing.
var is_vaulting: bool = false
## Flags whether the most recent raycast scan discovered a ledge.
var can_vault_current_ledge: bool = false
## World space coordinate of the top surface of the detected ledge.
var current_ledge_point: Vector3 = Vector3.ZERO
## World space coordinate of the outer edge of the detected ledge.
var current_ledge_edge: Vector3 = Vector3.ZERO
## Height differential between the player body and the ledge top.
var current_vault_height: float = 0.0
## Flags whether landing clearance mandates ending in a crouch.
var current_vault_requires_crouch: bool = false


## Lifecycle callback initializing controller properties.
func _ready() -> void:
	print("VaultController: _ready() called. Initialized.")


## Physics frame update managing continuous obstacle and ledge scanning.
## [param _delta] Elapsed physics frame delta in seconds.
func _physics_process(_delta: float) -> void:
	if auto_scan and is_instance_valid(player_body) and is_instance_valid(camera):
		if not is_vaulting:
			process_vault_scan()


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
## Casts rays forward and downward to identify vaultable ledge geometry.
## [param max_reach] Maximum reach distance in meters.
func process_vault_scan(max_reach: float = 2.1) -> void:
	can_vault_current_ledge = false

	if is_vaulting:
		Events.vault_prompt_updated.emit(false, Vector3.ZERO)
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

	# 1. FORWARD CAST (Multi-Height Wall Check)
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
					Events.vault_prompt_updated.emit(false, Vector3.ZERO)
					return
				forward_result = hit
				break

	if forward_result.is_empty():
		Events.vault_prompt_updated.emit(false, Vector3.ZERO)
		return

	var highest_hit: Vector3 = forward_result["position"]
	var hit_normal: Vector3 = forward_result["normal"]

	# 2. DOWNWARD CAST (Find Ledge Top)
	var down_start: Vector3 = highest_hit - (hit_normal * 0.15)
	down_start.y = player_body.global_position.y + max_reach

	ray_query.from = down_start
	ray_query.to = down_start + Vector3(0.0, -max_reach - 0.5, 0.0)

	var down_result: Dictionary = space_state.intersect_ray(ray_query)
	if down_result.is_empty() or down_result["normal"].y < 0.7:
		Events.vault_prompt_updated.emit(false, Vector3.ZERO)
		return

	if _is_collider_or_parent_in_group(down_result["collider"], "not_climbable"):
		Events.vault_prompt_updated.emit(false, Vector3.ZERO)
		return

	var down_collider: Object = down_result["collider"]
	if down_collider is Node and down_collider.is_in_group("not_climbable"):
		Events.vault_prompt_updated.emit(false, Vector3.ZERO)
		return

	var ledge_point: Vector3 = down_result["position"]
	var vault_height: float = ledge_point.y - player_body.global_position.y

	if vault_height <= max_step_height or vault_height > max_reach:
		Events.vault_prompt_updated.emit(false, Vector3.ZERO)
		return

	# 3. CLEARANCE CAST (Headroom Check)
	var clearance_start: Vector3 = ledge_point + (forward_dir * 0.15) + Vector3(0.0, 0.05, 0.0)
	var clearance_end: Vector3 = clearance_start + Vector3(0.0, 1.8, 0.0)

	ray_query.from = clearance_start
	ray_query.to = clearance_end

	var clearance_result: Dictionary = space_state.intersect_ray(ray_query)
	var requires_crouch: bool = false

	if not clearance_result.is_empty():
		var hit_height: float = clearance_result["position"].y - ledge_point.y
		if hit_height < 0.9:
			Events.vault_prompt_updated.emit(false, Vector3.ZERO)
			return
		requires_crouch = true

	# SUCCESS
	can_vault_current_ledge = true
	current_ledge_point = ledge_point
	current_vault_height = vault_height
	current_vault_requires_crouch = requires_crouch

	var exact_edge: Vector3 = highest_hit
	exact_edge.y = ledge_point.y + 0.03
	exact_edge += hit_normal * 0.05
	current_ledge_edge = exact_edge

	Events.vault_prompt_updated.emit(true, exact_edge)


# --------------------------------------
# VAULT EXECUTION
# --------------------------------------
## Initiates a vault sequence towards the cached ledge if available.
## [param is_currently_crouching] Player's starting crouch stance flag.
## [return] True if vault execution began successfully.
func try_vault(is_currently_crouching: bool) -> bool:
	print("VaultController: try_vault() called.")
	if not can_vault_current_ledge:
		return false

	can_vault_current_ledge = false

	var forward_dir: Vector3 = -camera.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	Events.vault_prompt_updated.emit(false, Vector3.ZERO)

	_perform_vault(
		current_ledge_point,
		forward_dir,
		current_vault_height,
		current_vault_requires_crouch,
		is_currently_crouching
	)

	return true


## Runs tween animations moving the character body onto the ledge.
## [param target_point] Destination point coordinate on top of the ledge.
## [param forward_dir] Normalized forward movement direction vector.
## [param vault_height] Vertical distance to travel in meters.
## [param force_crouch] Mandates ending stance crouched due to low headroom.
## [param is_currently_crouching] Starting stance crouch state.
func _perform_vault(
	target_point: Vector3,
	forward_dir: Vector3,
	vault_height: float,
	force_crouch: bool,
	is_currently_crouching: bool
) -> void:
	print("VaultController: _perform_vault() called.")
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


## Tests motion recovery to push the player clear if stuck in walls.
## [param forward_dir] Facing direction during vault traversal.
func _ensure_player_unstuck(forward_dir: Vector3) -> void:
	print("VaultController: _ensure_player_unstuck() called.")
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
			print("VaultController: Player stuck. Backed out.")
		else:
			player_body.global_position += push_vector
			print("VaultController: Corrected overlap by: ", push_vector)


## Checks whether a collider or its parent hierarchy belongs to a group.
## [param collider] The hit physics body or area.
## [param group_name] The group string identifier to locate.
## [return] True if any node up to 4 ancestors belongs to the group.
func _is_collider_or_parent_in_group(collider: Object, group_name: String) -> bool:
	if not collider is Node:
		return false

	var current_node: Node = collider as Node
	for i: int in range(4):
		if current_node == null:
			return false
		if current_node.is_in_group(group_name):
			return true
		current_node = current_node.get_parent()

	return false
