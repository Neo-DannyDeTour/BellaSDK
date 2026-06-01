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
func process_vault_scan(max_reach: float = 2.8) -> void:
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

	# 1. VERTICAL SWEEP (Find where the wall ends and the opening begins)
	var hit_any: bool = false
	var highest_hit: Vector3 = Vector3.ZERO
	var hit_normal: Vector3 = Vector3.ZERO
	var gap_height: float = max_reach + 0.3

	var h: float = max_step_height
	while h <= max_reach + 0.3:
		var start: Vector3 = player_body.global_position + Vector3(0.0, h, 0.0)
		var end: Vector3 = start + (forward_dir * 1.2)
		var query := PhysicsRayQueryParameters3D.create(start, end)
		query.exclude = exclude_rids

		var result: Dictionary = space_state.intersect_ray(query)

		if not result.is_empty() and absf(result["normal"].y) <= 0.2:
			# Wall detected
			hit_any = true
			highest_hit = result["position"]
			hit_normal = result["normal"]
		elif hit_any:
			# The current ray missed, but a lower one hit. We found the opening!
			gap_height = h
			break

		h += 0.3

	if not hit_any:
		return

	# 2. DOWNWARD CAST (Find exact ledge entirely inside the opening)
	var down_start: Vector3 = highest_hit - (hit_normal * 0.15)
	down_start.y = player_body.global_position.y + gap_height

	# Cast down slightly below our highest known hit to guarantee contact
	var hit_relative_y: float = highest_hit.y - player_body.global_position.y
	var ray_length: float = (gap_height - hit_relative_y) + 0.4

	var down_query := PhysicsRayQueryParameters3D.create(
		down_start,
		down_start + Vector3(0.0, -ray_length, 0.0)
	)
	down_query.exclude = exclude_rids

	var down_result: Dictionary = space_state.intersect_ray(down_query)
	if down_result.is_empty():
		return

	var ledge_point: Vector3 = down_result["position"]
	var vault_height: float = ledge_point.y - player_body.global_position.y

	if vault_height <= max_step_height or vault_height > max_reach:
		return

	# 3. DEPTH CAST (Check for Handrails/Obstacles on the ledge)
	var depth_start: Vector3 = ledge_point + Vector3(0.0, 0.15, 0.0)
	var depth_query := PhysicsRayQueryParameters3D.create(
		depth_start,
		depth_start + (forward_dir * vault_depth_clearance)
	)
	depth_query.exclude = exclude_rids

	var depth_result: Dictionary = space_state.intersect_ray(depth_query)
	if not depth_result.is_empty():
		# GLITCH FIX: If the normal points up (like a floor or ramp), allow it.
		# Only abort the vault if the object is a steep obstacle (wall/fence).
		if absf(depth_result["normal"].y) < 0.5:
			return

	# 4. CLEARANCE CAST (Headroom Check)
	# GLITCH FIX: Use the wall's normal to push inward instead of the camera's
	# forward direction. This guarantees you won't clip into sloped geometry 
	# regardless of which angle you are looking from.
	var clearance_start: Vector3 = ledge_point - (hit_normal * 0.15)
	clearance_start += Vector3(0.0, 0.05, 0.0)
	
	var clearance_end: Vector3 = clearance_start + Vector3(0.0, 1.8, 0.0)
	var clearance_query := PhysicsRayQueryParameters3D.create(clearance_start, clearance_end)
	clearance_query.exclude = exclude_rids

	var requires_crouch: bool = false
	var clearance_result: Dictionary = space_state.intersect_ray(clearance_query)

	if not clearance_result.is_empty():
		var room_height: float = clearance_result["position"].y - ledge_point.y
		if room_height < 0.9:
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
	
	is_vaulting = true
	vault_started.emit()

	if force_crouch:
		if not is_currently_crouching:
			crouch_state_changed.emit(true)
		standing_collision.disabled = true
		crouching_collision.disabled = false # <-- Fixed variable name

	var vault_time: float = clampf(vault_height * 0.75, 0.4, 1.5)
	var final_pos: Vector3 = target_point + (forward_dir * 0.2)

	var vault_tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	vault_tween.set_parallel(true)

	# 1. Move Forward (XZ Plane) over the entire vault time
	(vault_tween.tween_property(player_body, "global_position:x", final_pos.x, vault_time)
		.set_trans(Tween.TRANS_LINEAR))
	(vault_tween.tween_property(player_body, "global_position:z", final_pos.z, vault_time)
		.set_trans(Tween.TRANS_LINEAR))

	# 2. Move Up (Y Axis) quickly for the first 70%
	(vault_tween.tween_property(player_body, "global_position:y", final_pos.y + 0.1, vault_time * 0.7)
		.set_trans(Tween.TRANS_QUAD)
		.set_ease(Tween.EASE_OUT))
		
	# 3. Settle Down (Y Axis) gently to the exact ledge height for the last 30%
	(vault_tween.tween_property(player_body, "global_position:y", final_pos.y, vault_time * 0.3)
		.set_trans(Tween.TRANS_SINE)
		.set_ease(Tween.EASE_IN)
		.set_delay(vault_time * 0.7))

	if force_crouch:
		(vault_tween.tween_property(head, "position:y", crouching_depth, vault_time * 0.6)
			.set_trans(Tween.TRANS_SINE)
			.set_ease(Tween.EASE_OUT))

	var tilt_amount: float = deg_to_rad(5.0)
	(vault_tween.tween_property(eyes, "rotation:z", tilt_amount, vault_time * 0.5)
		.set_trans(Tween.TRANS_SINE)
		.set_ease(Tween.EASE_IN_OUT))
		
	(vault_tween.tween_property(eyes, "rotation:z", 0.0, vault_time * 0.5)
		.set_delay(vault_time * 0.5))

	vault_tween.chain().tween_callback(func() -> void:
		is_vaulting = false
		eyes.rotation.z = 0.0
		vault_finished.emit()
	)
