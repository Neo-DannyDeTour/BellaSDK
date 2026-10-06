## Scans and evaluates interactable components in the center of the viewport.
class_name InteractionScanner
extends Node

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when terminal focus mode begins or terminates.
signal terminal_mode_toggled(is_active: bool)

## Emitted when heavy lifting state changes. Passes state and heading baseline.
signal heavy_lift_state_changed(is_lifting: bool, yaw_base: float)

## Emitted when interactable enters crosshair reach. Passes target name and node.
signal object_hover_focused(object_name: String, caller: Node)

# --------------------------------------
# ZERO-ALLOCATION IDENTIFIERS
# --------------------------------------
## Name identifier of the interactable component node to search for.
const COMPONENT_NAME: StringName = &"InteractComponent"

## Property identifier for custom interactable display titles.
const PROP_DISPLAY_NAME: StringName = &"display_name"

## Property identifier for checking if an interactable is active.
const PROP_IS_ENABLED: StringName = &"is_enabled"

## Action identifier for triggering primary interaction.
const ACTION_INTERACT: StringName = &"interact"

## Action identifier for triggering weapon fire or terminal clicks.
const ACTION_SHOOT: StringName = &"shoot"

## Action identifier for triggering weapon reload.
const ACTION_RELOAD: StringName = &"reload"

## Maximum query rate in seconds for continuous terminal hover queries.
const TERMINAL_RAYCAST_INTERVAL: float = 0.05

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Node References")
## Interacting [Player] controller instance.
@export var player_body: Player

## First-person gameplay camera reference.
@export var camera: Camera3D

## Shapecast detecting interactable targets in crosshair reach.
@export var interact_shapecast: ShapeCast3D

## Audio player for interactions when hands are empty.
@export var empty_interact_audio: AudioStreamPlayer

@export_category("Interaction Settings")
## Minimum horizontal reach distance in meters.
@export var base_reach: float = 0.7

## Extended reach distance in meters when looking down at floor surfaces.
@export var floor_reach: float = 2.2

## Interval in seconds between interactable shapecast scan passes.
@export var scan_interval: float = 0.1

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Stores previous interactable to avoid re-announcing on every frame.
var _last_focused_interactable: Node = null

## Cached array of RIDs excluded from terminal interaction raycasts.
var _excluded_rids: Array[RID] = []

## Accumulator measuring elapsed frame time for throttled interaction scans.
var _scan_timer: float = 0.0

## Accumulator measuring elapsed frame time for terminal hover raycasts.
var _terminal_raycast_timer: float = 0.0

## Active interactable component currently in crosshair focus.
var current_interactable: Node = null

## Reference to the master [PlayerInteractionComponent].
var master_component: PlayerInteractionComponent = null

## Indicates whether the player is currently carrying a heavy object.
var is_heavy_lifting: bool = false

## Yaw heading baseline for clamping rotation during heavy carry.
var heavy_lift_yaw_base: float = 0.0

## Indicates whether terminal focus mode is currently active.
var is_in_terminal_mode: bool = false

## Active terminal instance currently being operated.
var active_terminal: Node3D = null

## Coordinates of player when terminal mode began.
var terminal_start_pos: Vector3 = Vector3.ZERO

## Hit coordinate of the most recent interaction query.
var current_hit_point: Vector3 = Vector3.ZERO


## Establishes link to master [PlayerInteractionComponent] and caches RIDs.
func setup_master_link(master: PlayerInteractionComponent) -> void:
	print("InteractionScanner: Link to Master Component established.")
	master_component = master
	if is_instance_valid(player_body):
		_excluded_rids = [player_body.get_rid()]


## Evaluates shapecast at throttled rate to detect interactables.
func process_interaction(delta: float) -> void:
	if is_in_terminal_mode:
		if _should_exit_terminal_mode():
			exit_terminal_mode()
			return

		if is_instance_valid(active_terminal):
			_terminal_raycast_timer += delta
			if _terminal_raycast_timer >= TERMINAL_RAYCAST_INTERVAL:
				_terminal_raycast_timer = 0.0
				shoot_terminal_raycast(false)
		return

	_scan_timer += delta
	var should_rescan: bool = _scan_timer >= scan_interval
	if should_rescan:
		_scan_timer = 0.0
		_update_dynamic_reach()
		current_interactable = _get_interactable_component_at_shapecast()
		_update_focus_announcements()

	if is_instance_valid(current_interactable):
		if interact_shapecast.get_collision_count() > 0:
			current_hit_point = interact_shapecast.get_collision_point(0)
			if current_interactable.has_method(&"hover_cursor"):
				current_interactable.call(&"hover_cursor", player_body, current_hit_point)

		if GestureInputManager.is_action_pressed(ACTION_INTERACT):
			var is_hands_empty: bool = true
			if is_instance_valid(master_component) and master_component.held_item != null:
				is_hands_empty = false

			if is_hands_empty and current_interactable.has_method(&"interact_held"):
				current_interactable.call(&"interact_held", player_body)


## Broadcasts focus change events when a new interactable enters view.
func _update_focus_announcements() -> void:
	if current_interactable == _last_focused_interactable:
		return

	_last_focused_interactable = current_interactable
	if is_instance_valid(current_interactable):
		var target_node: Node = current_interactable.get_parent()
		var speakable_name: String = target_node.name
		if PROP_DISPLAY_NAME in target_node:
			speakable_name = str(target_node.get(PROP_DISPLAY_NAME))

		print("InteractionScanner: Focused interactable -> ", speakable_name)
		object_hover_focused.emit(speakable_name, target_node)
		if Events.has_signal("object_focused"):
			Events.object_focused.emit(speakable_name, target_node)


## Triggers object interaction, item pickup, or empty sound cue.
func handle_interact_input() -> void:
	if is_in_terminal_mode:
		exit_terminal_mode()
		return

	if current_interactable:
		if current_interactable.has_method(&"interact_with"):
			print("InteractionScanner: Triggering interaction on object.")
			current_interactable.call(&"interact_with", player_body)

		var parent_node: Node = current_interactable.get_parent()
		if is_instance_valid(parent_node) and parent_node.has_method(&"pick_up"):
			print("InteractionScanner: Found pickable object. Instructing Master to grab.")
			if is_instance_valid(master_component):
				master_component.force_grab_item(parent_node as RigidBody3D)

			if parent_node.has_method(&"on_grabbed"):
				parent_node.call(&"on_grabbed")
	else:
		_play_empty_interact_audio()


## Plays empty interaction audio cue via throttled audio manager.
func _play_empty_interact_audio() -> void:
	if not is_instance_valid(empty_interact_audio) or empty_interact_audio.stream == null:
		return
	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if is_instance_valid(audio_mgr) and audio_mgr.has_method(&"play_sfx_2d_throttled"):
		audio_mgr.call(
			&"play_sfx_2d_throttled", empty_interact_audio.stream, empty_interact_audio.bus
		)
	else:
		empty_interact_audio.play()


## Routes trigger shoot inputs to terminal clicks or equipped weapons.
func handle_shoot_input() -> void:
	if is_in_terminal_mode and is_instance_valid(active_terminal):
		print("InteractionScanner: Shooting terminal raycast.")
		shoot_terminal_raycast(true)
		get_viewport().set_input_as_handled()
		return

	var weapon_holder: Node3D = (
		master_component.weapon_holder if is_instance_valid(master_component) else null
	)
	if is_instance_valid(weapon_holder):
		var inv: WeaponInventoryComponent = (
			weapon_holder.get_node_or_null("WeaponInventoryComponent") as WeaponInventoryComponent
		)
		if is_instance_valid(inv):
			inv.shoot_active_weapon()
		else:
			for child: Node in weapon_holder.get_children():
				if child.has_method(&"shoot") and child.get("visible") == true:
					child.call(&"shoot", camera)
					break


## Routes reload inputs to the equipped inventory weapon.
func handle_reload_input() -> void:
	print("InteractionScanner: handle_reload_input() called.")
	var weapon_holder: Node3D = (
		master_component.weapon_holder if is_instance_valid(master_component) else null
	)
	if is_instance_valid(weapon_holder):
		var inv: WeaponInventoryComponent = (
			weapon_holder.get_node_or_null("WeaponInventoryComponent") as WeaponInventoryComponent
		)
		if is_instance_valid(inv):
			inv.reload_active_weapon()
		else:
			for child: Node in weapon_holder.get_children():
				if child.has_method(&"reload") and child.get("visible") == true:
					child.call(&"reload")
					break


## Sets heavy lifting state and captures initial yaw heading.
func set_heavy_lifting(value: bool) -> void:
	is_heavy_lifting = value
	if is_heavy_lifting and is_instance_valid(player_body):
		heavy_lift_yaw_base = player_body.rotation.y
	heavy_lift_state_changed.emit(is_heavy_lifting, heavy_lift_yaw_base)


## Safely drops held heavy physics object via master component.
func drop_heavy_object_safely() -> void:
	if is_heavy_lifting and is_instance_valid(master_component):
		print("InteractionScanner: Routing heavy drop request to Master.")
		master_component.drop_held_item()
		set_heavy_lifting(false)


## Adjusts shapecast ray length based on camera pitch angle.
func _update_dynamic_reach() -> void:
	var look_pitch: float = interact_shapecast.global_rotation.x
	var down_weight: float = clampf(-look_pitch / (PI / 2.0), 0.0, 1.0)
	var current_reach: float = lerpf(base_reach, floor_reach, down_weight)
	interact_shapecast.target_position = Vector3(0, 0, -current_reach)


## Finds closest enabled interactable component via [NodeQuery].
func _get_interactable_component_at_shapecast() -> Node:
	var closest_comp: Node = null
	var closest_dist: float = INF
	var cast_origin: Vector3 = interact_shapecast.global_position

	for i: int in interact_shapecast.get_collision_count():
		var collider: Object = interact_shapecast.get_collider(i)

		if not is_instance_valid(collider) or collider == player_body:
			continue

		if collider is Node3D:
			var comp: Node = null
			var root_target: Node3D = NodeQuery.resolve_interactable_root(collider as Node3D)
			if is_instance_valid(root_target):
				comp = root_target.get_node_or_null(NodePath(COMPONENT_NAME))

			if not is_instance_valid(comp):
				var current_node: Node = collider as Node
				while is_instance_valid(current_node) and current_node != get_tree().root:
					comp = current_node.get_node_or_null(NodePath(COMPONENT_NAME))
					if is_instance_valid(comp):
						break
					current_node = current_node.get_parent()

			if is_instance_valid(comp):
				if PROP_IS_ENABLED in comp and comp.get(PROP_IS_ENABLED) == false:
					continue

				var interactable_parent: Node = comp.get_parent()
				if interactable_parent.has_method(&"is_valid_pickup_position"):
					var is_valid: bool = (
						interactable_parent.call(&"is_valid_pickup_position", player_body) == true
					)
					if not is_valid:
						continue

				var hit_point: Vector3 = interact_shapecast.get_collision_point(i)
				var dist: float = cast_origin.distance_squared_to(hit_point)

				if dist < closest_dist:
					closest_dist = dist
					closest_comp = comp
					current_hit_point = hit_point

	return closest_comp


## Activates terminal focus mode for numeric or minigame interfaces.
@warning_ignore("unsafe_cast")
func enter_terminal_mode(terminal: Node3D) -> void:
	print("InteractionScanner: Entering terminal mode.")
	is_in_terminal_mode = true
	active_terminal = terminal
	_terminal_raycast_timer = 0.0

	if is_instance_valid(player_body):
		terminal_start_pos = player_body.global_position

	var is_circle_keypad: bool = (
		is_instance_valid(terminal)
		and ("captures_wasd" in terminal)
		and terminal.get("captures_wasd") == true
	)

	if is_circle_keypad:
		print("InteractionScanner: Circle keypad detected. Locking player.")
		if is_instance_valid(player_body):
			player_body.is_terminal_locked = true

		if is_instance_valid(camera) and is_instance_valid(terminal):
			var target_pos: Vector3 = terminal.global_position
			if "mesh_instance_3d" in terminal:
				var mesh_candidate: Variant = terminal.get("mesh_instance_3d")
				if mesh_candidate is Node3D:
					target_pos = (mesh_candidate as Node3D).global_position
			camera.look_at(target_pos, Vector3.UP)
	else:
		print("InteractionScanner: Keypad detected. Leaving player free to aim.")
		if is_instance_valid(player_body):
			player_body.is_terminal_locked = false

	if is_instance_valid(Events) and Events.has_signal("terminal_mode_toggled"):
		Events.terminal_mode_toggled.emit(true)
	terminal_mode_toggled.emit(true)


## Exits terminal mode and restores default camera and movement control.
func exit_terminal_mode() -> void:
	if not is_in_terminal_mode:
		return

	print("InteractionScanner: Exiting terminal mode.")
	var terminal_to_clear: Node3D = active_terminal
	is_in_terminal_mode = false
	active_terminal = null
	_terminal_raycast_timer = 0.0

	if is_instance_valid(terminal_to_clear):
		if terminal_to_clear.has_method(&"clear_mouse_hover"):
			terminal_to_clear.call(&"clear_mouse_hover")

	if is_instance_valid(player_body):
		player_body.is_terminal_locked = false
		player_body.set_terminal_mouse_sensitivity_scale(1.0)
		player_body.exit_terminal_mode()

	if is_instance_valid(Events) and Events.has_signal("terminal_mode_toggled"):
		Events.terminal_mode_toggled.emit(false)
	terminal_mode_toggled.emit(false)


## Evaluates whether the player should automatically exit terminal mode.
func _should_exit_terminal_mode() -> bool:
	var is_circle_keypad: bool = (
		is_instance_valid(active_terminal)
		and ("captures_wasd" in active_terminal)
		and active_terminal.get("captures_wasd") == true
	)

	if is_circle_keypad:
		return false

	if (
		is_instance_valid(player_body)
		and (player_body.global_position.distance_squared_to(terminal_start_pos) > 2.5)
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


## Projects raycast from screen center via [method Utilities.raycast_3d].
@warning_ignore("unsafe_cast")
func shoot_terminal_raycast(is_click: bool) -> void:
	if is_click:
		print("InteractionScanner: shoot_terminal_raycast executed a click.")

	if not is_instance_valid(camera) or not is_instance_valid(player_body):
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	var ray_origin: Vector3 = camera.project_ray_origin(screen_center)
	var ray_normal: Vector3 = camera.project_ray_normal(screen_center)
	var ray_end: Vector3 = ray_origin + (ray_normal * 3.0)

	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	if not is_instance_valid(space_state):
		return

	var result: Dictionary = Utilities.raycast_3d(
		space_state, ray_origin, ray_end, Types.MASK_SOLID_WORLD, _excluded_rids
	)

	if not result.is_empty() and result.get("collider") == active_terminal:
		var hit_pos: Vector3 = Vector3.ZERO
		if result.has(&"position") and result[&"position"] is Vector3:
			hit_pos = result[&"position"] as Vector3

		if is_click and active_terminal.has_method(&"inject_mouse_click"):
			active_terminal.call(&"inject_mouse_click", hit_pos)
		elif active_terminal.has_method(&"inject_mouse_motion"):
			active_terminal.call(&"inject_mouse_motion", hit_pos)
