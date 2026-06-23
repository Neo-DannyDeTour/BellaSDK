class_name InteractionScanner
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
signal terminal_mode_toggled(is_active: bool)
signal heavy_lift_state_changed(is_lifting: bool, yaw_base: float)

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
@export var player_body: CharacterBody3D
@export var camera: Camera3D
@export var interact_shapecast: ShapeCast3D
@export var hold_position: Marker3D
@export var weapon_holder: Node3D

@export_category("Interaction Settings")
@export var base_reach: float = 0.7
@export var floor_reach: float = 2.2
@export var throw_force: float = 12.0

# --------------------------------------
# VARIABLES
# --------------------------------------
var current_interactable: Node = null
var held_object: Node3D = null

var is_heavy_lifting: bool = false
var heavy_lift_yaw_base: float = 0.0

var is_in_terminal_mode: bool = false
var active_terminal: Node3D = null
var terminal_start_pos: Vector3 = Vector3.ZERO


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
func process_interaction(_delta: float) -> void:
	if is_in_terminal_mode:
		if _should_exit_terminal_mode():
			exit_terminal_mode()
			return
			
		if is_instance_valid(active_terminal):
			# The click is now safely handled by handle_shoot_input().
			# This just continuously updates the mouse hover position.
			shoot_terminal_raycast(false)
			
		return

	_update_dynamic_reach()
	current_interactable = _get_interactable_component_at_shapecast()

	if current_interactable:
		var hit_point: Vector3 = interact_shapecast.get_collision_point(0)
		if current_interactable.has_method("hover_cursor"):
			# Note: I removed the print() statement from this specific block. 
			# Printing to the console every single frame causes massive performance 
			# bottlenecks and will prevent you from holding a steady 60 FPS.
			current_interactable.hover_cursor(player_body, hit_point)

# --------------------------------------
# INPUT HANDLING
# --------------------------------------
func handle_interact_input() -> void:
	print("InteractionScanner: handle_interact_input called.")
	
	if is_in_terminal_mode:
		exit_terminal_mode()
		return

	if held_object:
		if held_object.has_method("on_released"):
			print("InteractionScanner: Releasing held object.")
			held_object.on_released()

		if held_object.has_method("drop"):
			print("InteractionScanner: Dropping held object.")
			held_object.drop()

		held_object = null
		set_heavy_lifting(false)

		if weapon_holder:
			weapon_holder.show()

	elif current_interactable:
		if current_interactable.has_method("interact_with"):
			print("InteractionScanner: Interacting with object.")
			current_interactable.interact_with(player_body)

		var parent_node: Node = current_interactable.get_parent() as Node
		if parent_node and parent_node.has_method("pick_up"):
			held_object = parent_node as Node3D
			print("InteractionScanner: Picking up object.")
			held_object.pick_up(hold_position, player_body)

			if held_object.has_method("on_grabbed"):
				held_object.on_grabbed()

			if weapon_holder:
				weapon_holder.hide()


func handle_shoot_input() -> void:
	print("InteractionScanner: handle_shoot_input called.")
	
	if is_in_terminal_mode and is_instance_valid(active_terminal):
		shoot_terminal_raycast(true)
		get_viewport().set_input_as_handled()
		return

	if held_object:
		if held_object.has_method("on_released"):
			held_object.on_released()

		var throw_dir: Vector3 = -camera.global_transform.basis.z.normalized()
		throw_dir.y += 0.2

		if held_object.has_method("throw"):
			print("InteractionScanner: Throwing held object.")
			held_object.throw(throw_dir.normalized() * throw_force)

		held_object = null
		set_heavy_lifting(false)

		if weapon_holder:
			weapon_holder.show()

		return 

	if weapon_holder and weapon_holder.get_child_count() > 0:
		var active_weapon: Node3D = weapon_holder.get_child(0) as Node3D
		if active_weapon and active_weapon.has_method("shoot"):
			print("InteractionScanner: Shooting active weapon.")
			active_weapon.shoot(camera)


# --------------------------------------
# HEAVY LIFTING
# --------------------------------------
func set_heavy_lifting(value: bool) -> void:
	print("InteractionScanner: set_heavy_lifting called with value: ", value)
	is_heavy_lifting = value
	if is_heavy_lifting:
		heavy_lift_yaw_base = player_body.rotation.y
	heavy_lift_state_changed.emit(is_heavy_lifting, heavy_lift_yaw_base)


func drop_heavy_object_safely() -> void:
	print("InteractionScanner: drop_heavy_object_safely called.")
	if is_heavy_lifting and held_object:
		if held_object.has_method("on_released"):
			held_object.on_released()
		if held_object.has_method("drop"):
			held_object.drop()
		held_object = null
		set_heavy_lifting(false)
		if weapon_holder:
			weapon_holder.show()


# --------------------------------------
# DYNAMIC REACH & SCANNING
# --------------------------------------
func _update_dynamic_reach() -> void:
	var look_pitch: float = interact_shapecast.global_rotation.x
	var down_weight: float = clampf(-look_pitch / (PI / 2.0), 0.0, 1.0)
	var current_reach: float = lerpf(base_reach, floor_reach, down_weight)

	interact_shapecast.target_position = Vector3(0, 0, -current_reach)


func _get_interactable_component_at_shapecast() -> Node:
	var closest_comp: Node = null
	var closest_dist: float = INF
	var cast_origin: Vector3 = interact_shapecast.global_position

	for i: int in interact_shapecast.get_collision_count():
		var collider: Object = interact_shapecast.get_collider(i)

		if not is_instance_valid(collider) or collider == player_body:
			continue

		if collider is Node:
			var current_node: Node = collider
			var comp: Node = null
			
			# Climb up the scene tree to find the Interact_Component
			while is_instance_valid(current_node) and current_node != get_tree().root:
				comp = current_node.get_node_or_null("Interact_Component")
				if is_instance_valid(comp):
					break # Component found, stop climbing
				current_node = current_node.get_parent()

			if is_instance_valid(comp):
				var interactable_parent: Node = comp.get_parent()
				
				if interactable_parent.has_method("is_valid_pickup_position"):
					if not interactable_parent.is_valid_pickup_position(player_body):
						continue

				var hit_point: Vector3 = interact_shapecast.get_collision_point(i)
				var dist: float = cast_origin.distance_squared_to(hit_point)

				if dist < closest_dist:
					closest_dist = dist
					closest_comp = comp

	return closest_comp


# --------------------------------------
# TERMINAL MODE
# --------------------------------------
func enter_terminal_mode(terminal: Node3D) -> void:
	print("InteractionScanner: enter_terminal_mode called.")
	is_in_terminal_mode = true
	active_terminal = terminal
	terminal_start_pos = player_body.global_position

	# Assuming Events is an autoloaded globally available script
	Events.terminal_mode_toggled.emit(true)
	terminal_mode_toggled.emit(true)


func exit_terminal_mode() -> void:
	print("InteractionScanner: exit_terminal_mode called.")
	
	if is_instance_valid(active_terminal):
		if active_terminal.has_method("clear_mouse_hover"):
			active_terminal.clear_mouse_hover()
		
	is_in_terminal_mode = false
	active_terminal = null

	Events.terminal_mode_toggled.emit(false)
	terminal_mode_toggled.emit(false)


func _should_exit_terminal_mode() -> bool:
	if (
		Input.is_action_pressed("forward")
		or Input.is_action_pressed("backward")
		or Input.is_action_pressed("left")
		or Input.is_action_pressed("right")
	):
		return true
		
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch"):
		return true
		
	if player_body.global_position.distance_to(terminal_start_pos) > 1.0:
		return true

	if active_terminal:
		var dir_to_terminal := camera.global_position.direction_to(active_terminal.global_position)
		var camera_forward := -camera.global_transform.basis.z
		if rad_to_deg(camera_forward.angle_to(dir_to_terminal)) > 45.0:
			return true

	return false


func shoot_terminal_raycast(is_click: bool) -> void:
	if is_click:
		print("InteractionScanner: shoot_terminal_raycast executed a click.")
		
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size / 2.0

	var ray_origin: Vector3 = camera.project_ray_origin(screen_center)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_center)
	var ray_end: Vector3 = ray_origin + ray_normal * 3.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	
	if is_instance_valid(player_body):
		query.exclude = [player_body.get_rid()]
	
	query.collision_mask = 5

	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.collider == active_terminal:
		if is_click and active_terminal.has_method("inject_mouse_click"):
			active_terminal.inject_mouse_click(result.position)
		elif active_terminal.has_method("inject_mouse_motion"):
			active_terminal.inject_mouse_motion(result.position)
