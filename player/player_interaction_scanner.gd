class_name InteractionScanner
extends Node

signal terminal_mode_toggled(is_active: bool)
signal heavy_lift_state_changed(is_lifting: bool, yaw_base: float)

## Emitted when an interactable object enters the center of the player's crosshair.
## [param object_name] Semantic name of the focused object.
## [param caller] Node instance sending the trigger.
signal object_hover_focused(object_name: String, caller: Node)

## Stores the previous interactable to avoid re-announcing on every frame.
var _last_focused_interactable: Node = null

@export_category("Node References")
@export var player_body: CharacterBody3D
@export var camera: Camera3D
@export var interact_shapecast: ShapeCast3D
@export var empty_interact_audio: AudioStreamPlayer

@export_category("Interaction Settings")
@export var base_reach: float = 0.7
@export var floor_reach: float = 2.2

# --- CLEANED UP VARIABLES ---
var current_interactable: Node = null
var master_component: Node = null  # Reference to the Master

var is_heavy_lifting: bool = false
var heavy_lift_yaw_base: float = 0.0

var is_in_terminal_mode: bool = false
var active_terminal: Node3D = null
var terminal_start_pos: Vector3 = Vector3.ZERO
var current_hit_point: Vector3 = Vector3.ZERO


func setup_master_link(master: Node) -> void:
	print("InteractionScanner: Link to Master Component established.")
	master_component = master


## Evaluates the active Shapecast to detect interactables and trigger audio cues.
## [param _delta] Elapsed physics frame time in seconds.
func process_interaction(_delta: float) -> void:
	if is_in_terminal_mode:
		if _should_exit_terminal_mode():
			exit_terminal_mode()
			return

		if is_instance_valid(active_terminal):
			shoot_terminal_raycast(false)
		return

	_update_dynamic_reach()
	current_interactable = _get_interactable_component_at_shapecast()

	if current_interactable != _last_focused_interactable:
		_last_focused_interactable = current_interactable
		if is_instance_valid(current_interactable):
			var target_node: Node = current_interactable.get_parent()
			var speakable_name: String = target_node.name
			if "display_name" in target_node:
				speakable_name = target_node.display_name as String

			print("InteractionScanner: Focused interactable -> ", speakable_name)
			object_hover_focused.emit(speakable_name, target_node)
			# NOTE: Do NOT emit Events.object_focused here.
			# Hovering below triggers hover_cursor(), which manages TTS prompt emission.

	if current_interactable:
		var hit_point: Vector3 = interact_shapecast.get_collision_point(0)
		if current_interactable.has_method("hover_cursor"):
			current_interactable.hover_cursor(player_body, hit_point)

		if GestureInputManager.is_action_pressed("interact"):
			var is_hands_empty: bool = true
			if is_instance_valid(master_component) and master_component.get("held_item") != null:
				is_hands_empty = false

			if is_hands_empty and current_interactable.has_method("interact_held"):
				current_interactable.interact_held(player_body)


func handle_interact_input() -> void:
	# 1. We ONLY reach this function if the Master Component confirmed hands are empty!
	if is_in_terminal_mode:
		exit_terminal_mode()
		return

	if current_interactable:
		if current_interactable.has_method("interact_with"):
			print("InteractionScanner: Triggering interaction on object.")
			current_interactable.interact_with(player_body)

		var parent_node: Node = current_interactable.get_parent() as Node
		if is_instance_valid(parent_node) and parent_node.has_method("pick_up"):
			print("InteractionScanner: Found pickable object. Instructing Master to grab.")
			if is_instance_valid(master_component):
				master_component.force_grab_item(parent_node as RigidBody3D)

			if parent_node.has_method("on_grabbed"):
				parent_node.on_grabbed()
	else:
		if is_instance_valid(empty_interact_audio):
			empty_interact_audio.play()


func handle_shoot_input() -> void:
	if is_in_terminal_mode and is_instance_valid(active_terminal):
		print("InteractionScanner: Shooting terminal raycast.")
		shoot_terminal_raycast(true)
		get_viewport().set_input_as_handled()
		return

	var weapon_holder: Node = (
		master_component.get("weapon_holder") if is_instance_valid(master_component) else null
	)
	if is_instance_valid(weapon_holder):
		var inv: WeaponInventoryComponent = (
			weapon_holder.get_node_or_null("WeaponInventoryComponent") as WeaponInventoryComponent
		)
		if is_instance_valid(inv):
			inv.shoot_active_weapon()
		else:
			for child: Node in weapon_holder.get_children():
				if child.has_method("shoot") and bool(child.get("visible")):
					child.call("shoot", camera)
					break


## Routes reload inputs to the equipped inventory weapon or weapon holder child.
func handle_reload_input() -> void:
	print("InteractionScanner: handle_reload_input() called.")
	var weapon_holder: Node = (
		master_component.get("weapon_holder") if is_instance_valid(master_component) else null
	)
	if is_instance_valid(weapon_holder):
		var inv: WeaponInventoryComponent = (
			weapon_holder.get_node_or_null("WeaponInventoryComponent") as WeaponInventoryComponent
		)
		if is_instance_valid(inv):
			inv.reload_active_weapon()
		else:
			for child: Node in weapon_holder.get_children():
				if child.has_method("reload") and bool(child.get("visible")):
					child.call("reload")
					break


func set_heavy_lifting(value: bool) -> void:
	is_heavy_lifting = value
	if is_heavy_lifting and is_instance_valid(player_body):
		heavy_lift_yaw_base = player_body.rotation.y
	heavy_lift_state_changed.emit(is_heavy_lifting, heavy_lift_yaw_base)


func drop_heavy_object_safely() -> void:
	# Route the drop command back up to the Master
	if is_heavy_lifting and is_instance_valid(master_component):
		print("InteractionScanner: Routing heavy drop request to Master.")
		master_component.drop_held_item()
		set_heavy_lifting(false)


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
			var current_node: Node = collider as Node
			var comp: Node = null

			while is_instance_valid(current_node) and current_node != get_tree().root:
				comp = current_node.get_node_or_null("InteractComponent")
				if is_instance_valid(comp):
					break
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
					current_hit_point = hit_point

	return closest_comp


# --------------------------------------
# TERMINAL MODE
# --------------------------------------
## Activates terminal focus mode, differentiating between numeric and minigame terminals.
## [param terminal] The terminal [Node3D] interacted with.
func enter_terminal_mode(terminal: Node3D) -> void:
	print("InteractionScanner: Entering terminal mode.")
	is_in_terminal_mode = true
	active_terminal = terminal

	if is_instance_valid(player_body):
		terminal_start_pos = player_body.global_position

	var captures_wasd_val: Variant = (
		terminal.get("captures_wasd") if is_instance_valid(terminal) else null
	)
	var is_circle_keypad: bool = captures_wasd_val == true

	if is_circle_keypad:
		print("InteractionScanner: Circle keypad detected. Locking player and camera.")
		if is_instance_valid(player_body):
			player_body.set("is_terminal_locked", true)

		# Center camera on the terminal mesh
		if is_instance_valid(camera) and is_instance_valid(terminal):
			var target_pos: Vector3 = terminal.global_position
			if "mesh_instance_3d" in terminal and is_instance_valid(terminal.mesh_instance_3d):
				target_pos = terminal.mesh_instance_3d.global_position
			camera.look_at(target_pos, Vector3.UP)
	else:
		print("InteractionScanner: Numeric keypad detected. Leaving player free to aim.")
		if is_instance_valid(player_body):
			player_body.set("is_terminal_locked", false)

	if is_instance_valid(Events) and Events.has_signal("terminal_mode_toggled"):
		Events.terminal_mode_toggled.emit(true)
	terminal_mode_toggled.emit(true)


## Exits terminal mode, restores movement and camera look, and stops minigames.
func exit_terminal_mode() -> void:
	print("InteractionScanner: Exiting terminal mode.")
	if is_instance_valid(active_terminal):
		if active_terminal.has_method("clear_mouse_hover"):
			active_terminal.clear_mouse_hover()

	is_in_terminal_mode = false
	active_terminal = null

	if is_instance_valid(player_body):
		player_body.set("is_terminal_locked", false)
		if is_instance_valid(player_body.locomotion_component):
			player_body.locomotion_component.set_physics_active(true)

	if is_instance_valid(Events) and Events.has_signal("terminal_mode_toggled"):
		Events.terminal_mode_toggled.emit(false)
	terminal_mode_toggled.emit(false)


## Evaluates whether the player should automatically exit terminal mode.
## [return] True if exit thresholds are crossed.
func _should_exit_terminal_mode() -> bool:
	var captures_wasd_val: Variant = (
		active_terminal.get("captures_wasd") if is_instance_valid(active_terminal) else null
	)
	var is_circle_keypad: bool = captures_wasd_val == true

	# Circle keypad: ONLY the Interact key can exit. Never auto-exit.
	if is_circle_keypad:
		return false

	# Numeric keypad: Auto-exits if the player walks away or looks away
	if (
		is_instance_valid(player_body)
		and player_body.global_position.distance_squared_to(terminal_start_pos) > 2.5
	):
		return true

	if is_instance_valid(active_terminal) and is_instance_valid(camera):
		var dir_to_terminal: Vector3 = camera.global_position.direction_to(
			active_terminal.global_position
		)
		var camera_forward: Vector3 = -camera.global_transform.basis.z
		if rad_to_deg(camera_forward.angle_to(dir_to_terminal)) > 55.0:
			return true

	return false


func shoot_terminal_raycast(is_click: bool) -> void:
	if is_click:
		print("InteractionScanner: shoot_terminal_raycast executed a click.")

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size / 2.0

	if not is_instance_valid(camera):
		return

	var ray_origin: Vector3 = camera.project_ray_origin(screen_center)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_center)
	var ray_end: Vector3 = ray_origin + ray_normal * 3.0

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)

	if is_instance_valid(player_body):
		query.exclude = [player_body.get_rid()]

	query.collision_mask = 5

	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query)

	if result and result.get("collider") == active_terminal:
		if is_click and active_terminal.has_method("inject_mouse_click"):
			active_terminal.inject_mouse_click(result.position)
		elif active_terminal.has_method("inject_mouse_motion"):
			active_terminal.inject_mouse_motion(result.position)
