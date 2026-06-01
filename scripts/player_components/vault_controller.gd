class_name VaultController
extends Node3D

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
@export var player_body: CharacterBody3D
@export var camera: Camera3D
@export var head: Node3D
@export var eyes: Node3D
@export var standing_collision: CollisionShape3D
@export var crouching_collision: CollisionShape3D

@export_category("Vault Settings")
@export var max_step_height: float = 0.5
@export var crouching_depth: float = 0.7
@export var vault_depth_clearance: float = 0.5

# --------------------------------------
# VARIABLES
# --------------------------------------
var is_vaulting: bool = false
var can_vault_current_ledge: bool = false
var current_ledge_point: Vector3 = Vector3.ZERO
var current_vault_height: float = 0.0
var current_vault_requires_crouch: bool = false

var vault_indicator: MeshInstance3D

func _ready() -> void:
	_setup_vault_indicator()

func _setup_vault_indicator() -> void:
	vault_indicator = MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.03
	dot_mesh.height = 0.06
	vault_indicator.mesh = dot_mesh

	var dot_mat := StandardMaterial3D.new()
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
func process_vault_scan() -> void:
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

	# 1. FORWARD CAST (Find Wall)
	var detect_start: Vector3 = player_body.global_position + Vector3(0.0, 0.5, 0.0)
	var forward_query := PhysicsRayQueryParameters3D.create(
		detect_start, 
		detect_start + forward_dir * 1.2
	)
	forward_query.exclude = exclude_rids

	var forward_result: Dictionary = space_state.intersect_ray(forward_query)
	if forward_result.is_empty():
		return

	var wall_normal: Vector3 = forward_result["normal"]
	if absf(wall_normal.y) > 0.2:
		return

	# 2. DOWNWARD CAST (Find Ledge)
	var wall_hit: Vector3 = forward_result["position"]
	var down_start: Vector3 = wall_hit - (wall_normal * 0.15) + Vector3(0.0, 2.0, 0.0)

	var down_query := PhysicsRayQueryParameters3D.create(
		down_start, 
		down_start + Vector3(0.0, -2.5, 0.0)
	)
	down_query.exclude = exclude_rids

	var down_result: Dictionary = space_state.intersect_ray(down_query)
	if down_result.is_empty():
		return

	var ledge_point: Vector3 = down_result["position"]
	var vault_height: float = ledge_point.y - player_body.global_position.y

	if vault_height <= max_step_height or vault_height > 1.8:
		return

	# 3. DEPTH CAST (Check for Handrails/Obstacles on the ledge)
	var depth_start: Vector3 = ledge_point + Vector3(0.0, 0.1, 0.0)
	var depth_query := PhysicsRayQueryParameters3D.create(
		depth_start, 
		depth_start + (forward_dir * vault_depth_clearance)
	)
	depth_query.exclude = exclude_rids
	
	var depth_result: Dictionary = space_state.intersect_ray(depth_query)
	if not depth_result.is_empty():
		# Something is blocking the landing zone
		return

	# 4. CLEARANCE CAST (Headroom Check)
	var clearance_start: Vector3 = ledge_point + (forward_dir * 0.15) + Vector3(0.0, 0.05, 0.0)
	var clearance_end: Vector3 = clearance_start + Vector3(0.0, 1.8, 0.0)
	var clearance_query := PhysicsRayQueryParameters3D.create(clearance_start, clearance_end)
	clearance_query.exclude = exclude_rids

	var requires_crouch: bool = false
	var clearance_result: Dictionary = space_state.intersect_ray(clearance_query)

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
		var exact_edge: Vector3 = wall_hit
		exact_edge.y = ledge_point.y + 0.03
		exact_edge += wall_normal * 0.05
		vault_indicator.global_position = exact_edge
		vault_indicator.show()

# --------------------------------------
# VAULT EXECUTION
# --------------------------------------
func try_vault(is_currently_crouching: bool) -> bool:
	if not can_vault_current_ledge:
		return false

	# Consume the vault immediately so it cannot be triggered twice
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

func _perform_vault(target_point: Vector3, forward_dir: Vector3, vault_height: float, force_crouch: bool, is_currently_crouching: bool) -> void:
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

	(vault_tween.tween_property(player_body, "global_position:y", final_pos.y + 0.1, vault_time * 0.7)
		.set_trans(Tween.TRANS_QUAD)
		.set_ease(Tween.EASE_OUT))
		
	(vault_tween.tween_property(player_body, "global_position", final_pos, vault_time * 0.3)
		.set_trans(Tween.TRANS_LINEAR)
		.set_delay(vault_time * 0.7))

	if force_crouch:
		(vault_tween.tween_property(head, "position:y", crouching_depth, vault_time * 0.6)
			.set_trans(Tween.TRANS_SINE)
			.set_ease(Tween.EASE_OUT))

	var tilt_amount: float = deg_to_rad(5.0)
	(vault_tween.tween_property(eyes, "rotation:z", tilt_amount, vault_time * 0.5)
		.set_trans(Tween.TRANS_SINE)
		.set_ease(Tween.EASE_IN_OUT))
		
	vault_tween.tween_property(eyes, "rotation:z", 0.0, vault_time * 0.5).set_delay(vault_time * 0.5)

	vault_tween.chain().tween_callback(func() -> void:
		is_vaulting = false
		eyes.rotation.z = 0.0
		vault_finished.emit()
	)
