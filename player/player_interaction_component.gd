## Manages player object grabbing, throwing, inventory anchoring, and scanner routing.
class_name PlayerInteractionComponent
extends Node

## Minimum mass in kilograms required for an object to be considered heavy.
const HEAVY_OBJECT_MASS_THRESHOLD: float = 10.0

## Cooldown duration in milliseconds after dropping before re-grab is allowed.
const DROP_REPICK_COOLDOWN_MSEC: int = 400

@export_category("Item Handling")

## Impulse force magnitude applied when throwing a held physical item.
@export var throw_strength: float = 15.0

@export_category("Node References")

## Shape cast used for detecting short-range physics items to grab.
@export var interact_cast: ShapeCast3D

## Marker indicating anchor point for picked-up items in front of player.
@export var hold_position: Marker3D

## Socket node holding equipped weapons and tools for the [Player].
@export var weapon_holder: Node3D

## Reference to the primary [Player] camera node.
@export var camera: Camera3D

## Reference to the [InteractionScanner] sub-component.
@export var interaction_scanner: InteractionScanner

## Reference to the parent [Player] character entity.
var player: Player

## The [RigidBody3D] currently carried by the [Player].
var held_item: RigidBody3D = null:
	set(value):
		var changed: bool = held_item != value
		held_item = value
		if changed:
			var is_holding: bool = is_instance_valid(held_item)
			print("InteractionComponent: Held item state changed -> ", is_holding)
			Events.held_item_changed.emit(is_holding)

## Indicates whether the player is currently operating fixed machinery.
var is_operating_machine: bool = false

## Tracks if a carried object or lifting state restricts sprint and jump.
var is_heavy_carrying: bool = false

## Indicates whether the player is carrying a heavy two-handed object.
var is_heavy_lifting: bool = false:
	set(value):
		is_heavy_lifting = value
		update_heavy_carry_state()

## Yaw heading baseline used for heavy lifting rotation clamping.
var heavy_lift_yaw_base: float = 0.0

## Indicates whether terminal focus mode is currently active.
var is_in_terminal_mode: bool = false

## Timestamp in milliseconds of the last grab execution.
var _last_grab_time: int = 0

## Timestamp in milliseconds of the last drop execution to debounce re-grabs.
var _last_drop_time: int = 0


## Initializes component, caches player, and binds scanner and event listeners.
func initialize(p_player: CharacterBody3D) -> void:
	print("InteractionComponent: initialize() called. Caching player reference.")
	if p_player is Player:
		player = p_player

	if (
		is_instance_valid(interaction_scanner)
		and interaction_scanner.has_method(&"setup_master_link")
	):
		interaction_scanner.setup_master_link(self)

	Utilities.safe_connect(Events.item_dropped, _on_global_item_dropped)


## Evaluates physics frame tick updates and polls action inputs consistently.
func process_interaction(delta: float) -> void:
	if is_instance_valid(interaction_scanner):
		interaction_scanner.process_interaction(delta)

	# 1. Throwing Held Items
	if is_instance_valid(held_item):
		var is_throw_triggered: bool = (
			GestureInputManager.consume_buffered_action("shoot")
			or GestureInputManager.consume_buffered_action("grenade_throw")
			or (InputMap.has_action("shoot") and Input.is_action_just_pressed("shoot"))
			or (
				InputMap.has_action("grenade_throw")
				and Input.is_action_just_pressed("grenade_throw")
			)
		)

		if is_throw_triggered:
			print("InteractionComponent: Throw input validated. Throwing item.")
			throw_held_item()
			return

	# 2. Dropping or Picking Up Items via Interact Action
	var is_interact_triggered: bool = (
		GestureInputManager.consume_buffered_action("interact")
		or (InputMap.has_action("interact") and Input.is_action_just_pressed("interact"))
	)

	if is_interact_triggered:
		if is_instance_valid(held_item):
			if (
				held_item.has_method(&"is_class")
				and held_item.get("class_name") == "GliderItem"
				and is_instance_valid(player)
				and not player.is_on_floor()
			):
				return

			if Time.get_ticks_msec() - _last_grab_time < 200:
				return

			print("InteractionComponent: Interact pressed while holding. Drop.")
			drop_held_item()
			return

		var time_since_drop: int = Time.get_ticks_msec() - _last_drop_time
		if time_since_drop < DROP_REPICK_COOLDOWN_MSEC:
			return

		if _try_pick_up():
			return

		if is_instance_valid(interaction_scanner):
			print("InteractionComponent: Forwarding interact to scanner.")
			interaction_scanner.handle_interact_input()
			return

	# 3. Forward Shoot and Reload Inputs when Hands are Empty
	if not is_instance_valid(held_item):
		var is_shoot_triggered: bool = (
			GestureInputManager.consume_buffered_action("shoot")
			or (InputMap.has_action("shoot") and Input.is_action_just_pressed("shoot"))
		)
		if is_shoot_triggered and is_instance_valid(interaction_scanner):
			print("InteractionComponent: Forwarding shoot to scanner.")
			interaction_scanner.handle_shoot_input()

		var is_reload_triggered: bool = (
			GestureInputManager.consume_buffered_action("reload")
			or (InputMap.has_action("reload") and Input.is_action_just_pressed("reload"))
		)
		if is_reload_triggered and is_instance_valid(interaction_scanner):
			print("InteractionComponent: Forwarding reload to scanner.")
			interaction_scanner.handle_reload_input()


## Evaluates unhandled input events for gesture-resolved input routing.
func process_unhandled_input(_event: InputEvent = null) -> void:
	pass


## Attempts to detect and grab a nearby physics item using [NodeQuery].
func _try_pick_up() -> bool:
	var time_since_drop: int = Time.get_ticks_msec() - _last_drop_time
	if time_since_drop < DROP_REPICK_COOLDOWN_MSEC:
		return false

	interact_cast.force_shapecast_update()
	if interact_cast.is_colliding():
		for i: int in range(interact_cast.get_collision_count()):
			var collider: Object = interact_cast.get_collider(i)
			if not (collider is Node3D):
				continue
			var target_body: Node3D = collider if collider is Node3D else null
			if target_body is Area3D:
				var parent_node: Node = target_body.get_parent()
				target_body = parent_node if parent_node is Node3D else null

			if not is_instance_valid(target_body):
				continue

			var root_node: Node3D = NodeQuery.resolve_interactable_root(target_body)
			if root_node is RigidBody3D and root_node.has_method(&"pick_up"):
				print("InteractionComponent: Short-range grab on ", root_node.name)
				var rb_root: RigidBody3D = root_node
				force_grab_item(rb_root)
				return true

			if target_body is RigidBody3D and target_body.has_method(&"pick_up"):
				print("InteractionComponent: Short-range grab on ", target_body.name)
				var rb_target: RigidBody3D = target_body
				force_grab_item(rb_target)
				return true

	return false


## Throws currently held physics object forward along camera orientation.
func throw_held_item() -> void:
	print("InteractionComponent: throw_held_item() called.")
	if not is_instance_valid(held_item):
		return

	_last_drop_time = Time.get_ticks_msec()
	var item_to_throw: RigidBody3D = held_item
	held_item = null
	update_heavy_carry_state()

	var throw_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	throw_dir.y += 0.2
	var throw_force: Vector3 = throw_dir.normalized() * throw_strength

	if item_to_throw.has_method(&"throw"):
		item_to_throw.call(&"throw", throw_force)
	elif item_to_throw.has_method(&"throw_item"):
		item_to_throw.call(&"throw_item", throw_force, get_tree().current_scene)


## Releases and drops currently held physics object down to the floor.
func drop_held_item() -> void:
	print("InteractionComponent: drop_held_item() called. Placing item on ground.")
	if not is_instance_valid(held_item):
		return

	_last_drop_time = Time.get_ticks_msec()
	var item_to_drop: RigidBody3D = held_item
	held_item = null
	update_heavy_carry_state()

	if item_to_drop.has_method(&"drop"):
		item_to_drop.call(&"drop")
	elif item_to_drop.has_method(&"drop_item"):
		item_to_drop.call(&"drop_item", get_tree().current_scene, player.global_position)


## Clears hands and restores weapons when an item is dropped globally.
func _on_global_item_dropped(item: Node3D, actor: Node3D) -> void:
	if actor == player:
		print("InteractionComponent: Global drop received. Restoring weapons.")
		_last_drop_time = Time.get_ticks_msec()
		held_item = null
		update_heavy_carry_state()
		_check_glider_restore(item)
		_set_weapon_active(true)


## Clears tracking state for carried items and restores active weapons.
func force_clear_hands() -> void:
	print("InteractionComponent: force_clear_hands() called.")
	_last_drop_time = Time.get_ticks_msec()
	if is_instance_valid(held_item) and held_item.has_method(&"drop"):
		held_item.call(&"drop")
	held_item = null
	update_heavy_carry_state()
	_set_weapon_active(true)


## Restores player sprint capabilities if the dropped item is a glider.
func _check_glider_restore(item: Node) -> void:
	if item.has_method(&"is_class") and item.get("class_name") == "GliderItem":
		print("InteractionComponent: Released GliderItem. Restoring sprint.")
		if is_instance_valid(player) and is_instance_valid(player.locomotion_component):
			player.locomotion_component.can_sprint = true
		is_heavy_lifting = false


## Enables or disables active weapon holder visibility and processing.
func _set_weapon_active(active: bool) -> void:
	if is_instance_valid(weapon_holder):
		print("InteractionComponent: Setting weapon active state to: ", active)
		weapon_holder.visible = active
		weapon_holder.set_process(active)
		weapon_holder.set_physics_process(active)


## Synchronizes heavy carry state, updates movement, and emits event signal.
func update_heavy_carry_state() -> void:
	var is_heavy: bool = (
		is_heavy_lifting
		or (is_instance_valid(held_item) and held_item.mass >= HEAVY_OBJECT_MASS_THRESHOLD)
	)
	if is_heavy_carrying != is_heavy:
		is_heavy_carrying = is_heavy
		print("InteractionComponent: Heavy carry toggled -> ", is_heavy_carrying)
		if is_instance_valid(player) and is_instance_valid(player.locomotion_component):
			player.locomotion_component.can_sprint = not is_heavy_carrying
			player.locomotion_component.can_jump = not is_heavy_carrying
		Events.heavy_carry_toggled.emit(is_heavy_carrying)


## Directly forces the player to grab and hold a designated physics object.
func force_grab_item(item: RigidBody3D) -> void:
	print("InteractionComponent: force_grab_item() taking ownership of ", item.name)
	if is_instance_valid(held_item):
		drop_held_item()

	held_item = item
	_last_grab_time = Time.get_ticks_msec()
	update_heavy_carry_state()

	if held_item.has_method(&"pick_up"):
		held_item.call(&"pick_up", hold_position, player)

	_set_weapon_active(false)


## Attaches an item to the weapon holder socket using [Utilities].
func attach_item_to_weapon_holder(
	item: Node3D, item_anchor: Marker3D, p_player: Node3D = null
) -> void:
	print("InteractionComponent: attach_item_to_weapon_holder() reparenting item.")
	Utilities.reparent_keep_transform(item, weapon_holder, true)

	var offset: Vector3 = item.global_position - item_anchor.global_position
	item.global_position = hold_position.global_position + offset
	item.transform.basis = Basis.IDENTITY

	var target_player: Player = p_player if p_player is Player else player
	if is_instance_valid(target_player) and is_instance_valid(target_player.locomotion_component):
		target_player.locomotion_component.can_sprint = false


## Sets heavy lifting state, restricts player sprint, and emits global event.
func _set_heavy_lifting(active: bool) -> void:
	if is_heavy_lifting == active:
		return

	print("InteractionComponent: Setting heavy lifting state to: ", active)
	is_heavy_lifting = active

	if is_instance_valid(player) and is_instance_valid(player.locomotion_component):
		player.locomotion_component.can_sprint = not active

	Events.heavy_carry_toggled.emit(active)
