@tool
## Surface enabling wolf wall climbing and running via angle detection.
class_name WolfClimbSurface
extends StaticBody3D

## Emitted when player latches to wall, passing player body.
@warning_ignore("unused_signal")
signal latched_to_wall(player: CharacterBody3D)

## Group name tag identifying climbable wolf geometry.
const GROUP_WOLF_CLIMBABLE: StringName = &"wolf_climbable"

## Width and height dimensions of the climbable surface.
@export var surface_size: Vector2 = Vector2(4.0, 4.0):
	set = set_surface_size

## Collision depth thickness for the climbable surface.
@export var surface_thickness: float = 0.2:
	set = set_surface_thickness

## Vector normal pointing outward from the climbable front face.
@export var local_face_normal: Vector3 = Vector3(0.0, 0.0, 1.0)

## Child [InteractComponent] enabling crosshair interactions.
@export var interact_component: InteractComponent

## Proximity detection area triggering air attachment.
@export var detection_area: Area3D

## Collision shape of the primary static body wall.
@export var wall_collision_shape: CollisionShape3D

## Collision shape of the proximity detection area.
@export var detection_collision_shape: CollisionShape3D

## Guard flag preventing cyclical setter recursion loops.
var _is_updating_geometry: bool = false

## Reusable transition payload dictionary.
var _transition_msg: Dictionary = {}

## Maps player instances to cooldown timestamps.
var _dismount_cooldowns: Dictionary[CharacterBody3D, int] = {}


## Updates surface size and recalculates collider boundaries.
func set_surface_size(new_size: Vector2) -> void:
	var clamped: Vector2 = new_size.max(Vector2(0.1, 0.1))
	if surface_size.is_equal_approx(clamped):
		return
	print("WolfClimbSurface: set_surface_size() called with: ", clamped)
	surface_size = clamped
	if is_inside_tree() and not _is_updating_geometry:
		update_surface_geometry()


## Updates surface thickness and recalculates collider boundaries.
func set_surface_thickness(new_thickness: float) -> void:
	var clamped: float = maxf(new_thickness, 0.05)
	if is_equal_approx(surface_thickness, clamped):
		return
	print("WolfClimbSurface: set_surface_thickness() called with: ", clamped)
	surface_thickness = clamped
	if is_inside_tree() and not _is_updating_geometry:
		update_surface_geometry()


## Adjusts child collision box sizes to match surface dimensions.
func update_surface_geometry() -> void:
	if not is_inside_tree() or _is_updating_geometry:
		return

	_is_updating_geometry = true
	print("WolfClimbSurface: update_surface_geometry() adjusting shapes.")

	var current_scale: Vector3 = scale
	if (
		not is_equal_approx(current_scale.x, 1.0)
		or not is_equal_approx(current_scale.y, 1.0)
		or not is_equal_approx(current_scale.z, 1.0)
	):
		print("WolfClimbSurface: Absorbing non-uniform scale into size dimensions.")
		surface_size = (
			Vector2(surface_size.x * absf(current_scale.x), surface_size.y * absf(current_scale.y))
			. max(Vector2(0.1, 0.1))
		)
		scale = Vector3.ONE

	if not is_instance_valid(wall_collision_shape):
		wall_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

	if is_instance_valid(wall_collision_shape):
		var box: BoxShape3D = wall_collision_shape.shape as BoxShape3D
		if box == null:
			box = BoxShape3D.new()
			wall_collision_shape.shape = box
		var target_wall_size: Vector3 = Vector3(surface_size.x, surface_size.y, surface_thickness)
		if not box.size.is_equal_approx(target_wall_size):
			box.size = target_wall_size

	if not is_instance_valid(detection_area):
		detection_area = get_node_or_null("DetectionArea") as Area3D

	if is_instance_valid(detection_area):
		if not is_instance_valid(detection_collision_shape):
			detection_collision_shape = (
				detection_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
			)

		if is_instance_valid(detection_collision_shape):
			var dbox: BoxShape3D = detection_collision_shape.shape as BoxShape3D
			if dbox == null:
				dbox = BoxShape3D.new()
				detection_collision_shape.shape = dbox
			var target_detect_size: Vector3 = Vector3(
				surface_size.x + 0.2, surface_size.y + 0.2, surface_thickness + 0.8
			)
			if not dbox.size.is_equal_approx(target_detect_size):
				dbox.size = target_detect_size
			detection_collision_shape.position = local_face_normal * 0.4

	var mesh_node: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if is_instance_valid(mesh_node) and mesh_node.mesh is BoxMesh:
		var box_mesh: BoxMesh = mesh_node.mesh as BoxMesh
		var target_mesh_size: Vector3 = Vector3(surface_size.x, surface_size.y, surface_thickness)
		if not box_mesh.size.is_equal_approx(target_mesh_size):
			box_mesh.size = target_mesh_size

	_is_updating_geometry = false


## Catches transform changes in editor to absorb non-uniform scale.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if Engine.is_editor_hint() and is_inside_tree() and not _is_updating_geometry:
			var cur_s: Vector3 = scale
			if (
				not is_equal_approx(cur_s.x, 1.0)
				or not is_equal_approx(cur_s.y, 1.0)
				or not is_equal_approx(cur_s.z, 1.0)
			):
				update_surface_geometry()


## Registers groups, connects triggers, and synchronizes dimensions.
func _ready() -> void:
	print("WolfClimbSurface: Initializing climbable surface on: ", name)
	add_to_group(GROUP_WOLF_CLIMBABLE)
	set_notify_transform(true)
	update_surface_geometry()

	if not is_instance_valid(interact_component):
		interact_component = get_node_or_null("InteractComponent") as InteractComponent
	if is_instance_valid(interact_component):
		interact_component.interacted.connect(interact_with)

	if not is_instance_valid(detection_area):
		detection_area = get_node_or_null("DetectionArea") as Area3D
	if is_instance_valid(detection_area):
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		detection_area.body_exited.connect(_on_detection_area_body_exited)


## Polls overlapping bodies and evaluates climb vs wall run.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not is_instance_valid(detection_area):
		return

	var current_time: int = Time.get_ticks_msec()
	var overlapping: Array[Node3D] = detection_area.get_overlapping_bodies()

	for body: Node3D in overlapping:
		if not _can_character_climb(body, current_time):
			continue

		var player_node: CharacterBody3D = body as CharacterBody3D
		var wall_norm: Vector3 = get_climb_normal()

		if player_node.is_on_floor():
			var is_interact_pressed: bool = (
				GestureInputManager.is_action_just_triggered(&"interact")
				or GestureInputManager.is_action_just_pressed(&"interact")
				or Input.is_physical_key_pressed(KEY_E)
			)
			if is_interact_pressed:
				print("WolfClimbSurface: Ground interact detected. Forcing climb.")
				_attach_player(player_node, wall_norm, true)
				return
		else:
			var inward_dir: Vector3 = -wall_norm
			var velocity_inward: float = player_node.velocity.dot(inward_dir)
			var is_pressing_fwd: bool = GestureInputManager.is_action_active(&"forward")
			if velocity_inward > 0.25 or (velocity_inward > 0.0 and is_pressing_fwd):
				print("WolfClimbSurface: Airborne inward contact detected.")
				_attach_player(player_node, wall_norm, false)
				return


## Handles crosshair interaction triggered by [InteractComponent].
func interact_with(character: CharacterBody3D) -> void:
	print("WolfClimbSurface: interact_with() invoked by: ", character.name)
	var current_time: int = Time.get_ticks_msec()
	if not _can_character_climb(character, current_time):
		return
	_attach_player(character, get_climb_normal(), true)


## Evaluates character entry into proximity detection trigger.
func _on_detection_area_body_entered(body: Node3D) -> void:
	print("WolfClimbSurface: Body entered detection area: ", body.name)
	var current_time: int = Time.get_ticks_msec()
	if not _can_character_climb(body, current_time):
		return

	var player_node: CharacterBody3D = body as CharacterBody3D
	if not player_node.is_on_floor():
		var wall_norm: Vector3 = get_climb_normal()
		var velocity_inward: float = player_node.velocity.dot(-wall_norm)
		var is_pressing_fwd: bool = GestureInputManager.is_action_active(&"forward")
		if velocity_inward > 0.25 or (velocity_inward > 0.0 and is_pressing_fwd):
			print("WolfClimbSurface: Air trigger entered with inward velocity.")
			_attach_player(player_node, wall_norm, false)


## Handles character exit from proximity detection trigger.
func _on_detection_area_body_exited(body: Node3D) -> void:
	print("WolfClimbSurface: Body exited detection area: ", body.name)
	if not (body is CharacterBody3D and body.is_in_group(&"player")):
		return

	var player_node: CharacterBody3D = body as CharacterBody3D
	set_dismount_cooldown(player_node, 500)

	var raw_sm: Variant = player_node.get(&"state_machine")
	if not (raw_sm is StateMachine and is_instance_valid(raw_sm)):
		return

	@warning_ignore("unsafe_cast")
	var sm: StateMachine = raw_sm as StateMachine
	if sm.is_in_state(&"WolfClimb") or sm.is_in_state(&"WolfWallRun"):
		print("WolfClimbSurface: Player exited surface area. Falling to ground.")
		sm.transition_to(&"Air")


## Evaluates whether [param character] is within surface bounds.
func is_character_on_surface(character: CharacterBody3D) -> bool:
	if not is_instance_valid(character):
		return false
	var local_pos: Vector3 = to_local(character.global_position)
	var half_w: float = (surface_size.x * 0.5) + 0.35
	var half_h: float = (surface_size.y * 0.5) + 0.35
	if absf(local_pos.x) > half_w or absf(local_pos.y) > half_h:
		return false
	return true


## Returns true if dismount cooldown is active for [param character].
func has_dismount_cooldown(character: CharacterBody3D) -> bool:
	var current_time: int = Time.get_ticks_msec()
	if _dismount_cooldowns.has(character):
		var expire_time: int = _dismount_cooldowns[character]
		if current_time < expire_time:
			return true
		_dismount_cooldowns.erase(character)
	return false


## Evaluates if [param character] is eligible to cling or run.
func _can_character_climb(character: Node, _current_time: int) -> bool:
	if not is_instance_valid(character) or not character.is_in_group(&"player"):
		return false

	var is_wolf: bool = character.get(&"is_wolf_mode") == true
	if not is_wolf:
		return false

	var p_body: CharacterBody3D = character as CharacterBody3D
	if is_instance_valid(p_body) and has_dismount_cooldown(p_body):
		return false

	var raw_sm: Variant = character.get(&"state_machine")
	if raw_sm is StateMachine and is_instance_valid(raw_sm):
		@warning_ignore("unsafe_cast")
		var sm: StateMachine = raw_sm as StateMachine
		if sm.is_in_state(&"WolfClimb") or sm.is_in_state(&"WolfWallRun"):
			return false

	return true


## Computes normalized world-space outward normal vector.
func get_climb_normal() -> Vector3:
	return (global_transform.basis * local_face_normal).normalized()


## Sets dismount cooldown duration in milliseconds.
func set_dismount_cooldown(character: CharacterBody3D, duration_ms: int = 500) -> void:
	print("WolfClimbSurface: Setting dismount cooldown for: ", character.name)
	_dismount_cooldowns[character] = Time.get_ticks_msec() + duration_ms


## Evaluates approach angle and transitions to climb or wall run.
func _attach_player(p: CharacterBody3D, wall_norm: Vector3, force_climb: bool = false) -> void:
	print("WolfClimbSurface: Resolving player attachment.")
	latched_to_wall.emit(p)
	_transition_msg.clear()
	_transition_msg[&"wall_normal"] = wall_norm
	_transition_msg[&"climb_surface"] = self

	var raw_sm: Variant = p.get(&"state_machine")
	if not (raw_sm is StateMachine and is_instance_valid(raw_sm)):
		return

	@warning_ignore("unsafe_cast")
	var sm: StateMachine = raw_sm as StateMachine

	if force_climb:
		print("WolfClimbSurface: Forced climb selected.")
		sm.transition_to(&"WolfClimb", _transition_msg)
		return

	var cam_fwd: Vector3 = -p.global_transform.basis.z.normalized()
	var raw_cam: Variant = p.get(&"camera_controller")
	if raw_cam is CameraController and is_instance_valid(raw_cam):
		@warning_ignore("unsafe_cast")
		var cam_ctrl: CameraController = raw_cam as CameraController
		cam_fwd = cam_ctrl.get_camera_look_dir().normalized()

	var dot_inward: float = cam_fwd.dot(-wall_norm)
	print("WolfClimbSurface: Approach angle dot product -> ", dot_inward)

	var has_wall_run: bool = sm.has_node("WolfWallRun") or sm.has_node("StateWolfWallRun")
	var wall_run_state: StringName = (
		&"WolfWallRun" if sm.has_node("WolfWallRun") else &"StateWolfWallRun"
	)

	if dot_inward > 0.65:
		print("WolfClimbSurface: Facing wall directly (>0.65) -> WolfClimb.")
		sm.transition_to(&"WolfClimb", _transition_msg)
	elif dot_inward > -0.20 and has_wall_run:
		print("WolfClimbSurface: Approaching at angle (<=0.65) -> ", wall_run_state)
		sm.transition_to(wall_run_state, _transition_msg)
	else:
		print("WolfClimbSurface: Fallback transition -> WolfClimb.")
		sm.transition_to(&"WolfClimb", _transition_msg)
