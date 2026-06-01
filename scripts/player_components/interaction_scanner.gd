class_name InteractionScanner
extends Node3D

# --------------------------------------
# SIGNALS (To talk to Player.gd safely later)
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
var current_interactable: Node = null  # Assuming Interact_Component is a Node
var held_object: Node3D = null  # Assuming PickableObject extends Node3D

var is_heavy_lifting: bool = false
var heavy_lift_yaw_base: float = 0.0

# Terminal Mode Vars
var is_in_terminal_mode: bool = false
var active_terminal: Node3D = null
var terminal_start_pos: Vector3 = Vector3.ZERO


# --------------------------------------
# CORE PROCESS LOGIC
# --------------------------------------
func process_interaction(_delta: float) -> void:
	# 1. Handle Terminal Mode Exit Conditions
	if is_in_terminal_mode:
		if _should_exit_terminal_mode():
			exit_terminal_mode()
			return
		return  # Block standard interactions while in the terminal

	# 2. Dynamic Reach Fix
	_update_dynamic_reach()

	# 3. Scan for Interactables
	current_interactable = _get_interactable_component_at_shapecast()

	if current_interactable:
		var hit_point: Vector3 = interact_shapecast.get_collision_point(0)
		if current_interactable.has_method("hover_cursor"):
			current_interactable.hover_cursor(player_body, hit_point)


# --------------------------------------
# INPUT HANDLING
# --------------------------------------
func handle_interact_input() -> void:
	if is_in_terminal_mode:
		exit_terminal_mode()
		return

	# Drop Object
	if held_object:
		if held_object.has_method("on_released"):
			held_object.on_released()  # Handle TetheredPlug logic safely

		if held_object.has_method("drop"):
			held_object.drop()

		held_object = null
		set_heavy_lifting(false)

		if weapon_holder:
			weapon_holder.show()

	# Pick Up / Interact
	elif current_interactable:
		if current_interactable.has_method("interact_with"):
			current_interactable.interact_with(player_body)

		var parent_node: Node = current_interactable.get_parent()
		if parent_node.has_method("pick_up"):  # Duck typing for PickableObject
			held_object = parent_node as Node3D
			held_object.pick_up(hold_position, player_body)

			if held_object.has_method("on_grabbed"):
				held_object.on_grabbed()

			if weapon_holder:
				weapon_holder.hide()


func handle_shoot_input() -> void:
	# 1. Click Terminal
	if is_in_terminal_mode and is_instance_valid(active_terminal):
		shoot_terminal_raycast(true)
		get_viewport().set_input_as_handled()
		return

	# 2. Throw Object
	if held_object:
		if held_object.has_method("on_released"):
			held_object.on_released()

		var throw_direction: Vector3 = -camera.global_transform.basis.z.normalized()
		throw_direction.y += 0.2

		if held_object.has_method("throw"):
			held_object.throw(throw_direction.normalized() * throw_force)

		held_object = null
		set_heavy_lifting(false)

		if weapon_holder:
			weapon_holder.show()

		return  # <-- ADDED: Stop the function here so we don't shoot while throwing!

	# 3. ---> THE MISSING WEAPON LOGIC <---
	# If we aren't using a terminal and aren't holding a box, fire the gun!
	if weapon_holder and weapon_holder.get_child_count() > 0:
		var active_weapon: Node3D = weapon_holder.get_child(0)
		if active_weapon.has_method("shoot"):
			active_weapon.shoot(camera)


# --------------------------------------
# HEAVY LIFTING
# --------------------------------------
func set_heavy_lifting(value: bool) -> void:
	is_heavy_lifting = value
	if is_heavy_lifting:
		heavy_lift_yaw_base = player_body.rotation.y
	heavy_lift_state_changed.emit(is_heavy_lifting, heavy_lift_yaw_base)


func drop_heavy_object_safely() -> void:
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
	# Looking forward is 0, straight down is roughly -1.57 rads
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
			var comp: Node = collider.get_node_or_null("Interact_Component")
			if comp:
				# Heavy Box Anti-Stand Check
				if collider.has_method("is_valid_pickup_position"):
					if not collider.is_valid_pickup_position(player_body):
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
	is_in_terminal_mode = true
	active_terminal = terminal
	terminal_start_pos = player_body.global_position

	Events.terminal_mode_toggled.emit(true)
	terminal_mode_toggled.emit(true)


func exit_terminal_mode() -> void:
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
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_center := viewport_size / 2.0

	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_normal := camera.project_ray_normal(screen_center)
	var ray_end := ray_origin + ray_normal * 3.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var space_state := player_body.get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	if result and result.collider == active_terminal:
		if is_click and active_terminal.has_method("inject_mouse_click"):
			active_terminal.inject_mouse_click(result.position)
		elif active_terminal.has_method("inject_mouse_motion"):
			active_terminal.inject_mouse_motion(result.position)
