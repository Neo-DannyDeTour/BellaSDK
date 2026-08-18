## Manages player object grabbing, throwing, inventory anchoring, and scanner routing.
class_name PlayerInteractionComponent
extends Node

# --------------------------------------
# EXPORTS
# --------------------------------------
@export_category("Item Handling")
## The impulse force magnitude applied when throwing a held item.
@export var throw_strength: float = 15.0

@export_category("Node References")
## Shape cast used for detecting short-range physics items to grab.
@export var interact_cast: ShapeCast3D

## Marker indicating the point where picked-up items are anchored in front of the player.
@export var hold_position: Marker3D

## Socket node holding equipped weapons and tools.
@export var weapon_holder: Node3D

## Reference to the primary player camera node.
@export var camera: Camera3D

## Reference to the long-range interaction and scanner sub-component.
@export var interaction_scanner: Node

# --------------------------------------
# VARIABLES
# --------------------------------------
## Reference to the parent player entity.
var player: CharacterBody3D

## The RigidBody3D currently being carried by the player.
var held_item: RigidBody3D = null

## Flag indicating whether the player is currently operating fixed machinery.
var is_operating_machine: bool = false

## Flag indicating whether the player is carrying a heavy two-handed object.
var is_heavy_lifting: bool = false

## Yaw heading baseline used for heavy lifting rotation clamping.
var heavy_lift_yaw_base: float = 0.0

## Flag indicating whether terminal focus mode is active.
var is_in_terminal_mode: bool = false

## Timestamp in milliseconds of the last grab execution to debounce rapid drops.
var _last_grab_time: int = 0


## Initializes the interaction component and registers event bus listeners.
## [param p_player] The owner [Node3D] player controller.
func initialize(p_player: Node3D) -> void:
	print("InteractionComponent: initialize() called. Caching player reference.")
	player = p_player as CharacterBody3D

	if (
		is_instance_valid(interaction_scanner)
		and interaction_scanner.has_method("setup_master_link")
	):
		interaction_scanner.setup_master_link(self)

	if not Events.item_dropped.is_connected(_on_global_item_dropped):
		Events.item_dropped.connect(_on_global_item_dropped)


## Evaluates gesture-resolved inputs polled each frame from the master player loop.
## [param _event] The [InputEvent] dispatched from the engine (kept for API compatibility).
func process_unhandled_input(_event: InputEvent = null) -> void:
	# 1. Throwing Held Items
	if (
		(
			GestureInputManager.is_action_just_triggered("grenade_throw")
			or GestureInputManager.is_action_just_triggered("shoot")
		)
		and is_instance_valid(held_item)
	):
		print("InteractionComponent: Throw action triggered. Throwing item.")
		throw_held_item()
		return

	# 2. Dropping or Picking Up Items via Interact Action
	if GestureInputManager.is_action_just_triggered("interact"):
		if is_instance_valid(held_item):
			if (
				held_item.has_method("is_class")
				and held_item.get("class_name") == "GliderItem"
				and not player.is_on_floor()
			):
				return

			if Time.get_ticks_msec() - _last_grab_time < 100:
				return

			print(
				"InteractionComponent: Interact triggered while holding item." + " Requesting drop."
			)
			drop_held_item()
			return

		if _try_pick_up():
			return

		if is_instance_valid(interaction_scanner):
			if interaction_scanner.has_method("handle_interact_input"):
				print("InteractionComponent: Forwarding interact to scanner.")
				interaction_scanner.handle_interact_input()
			return

	# 3. Scanner Shoot Inputs
	if (
		GestureInputManager.is_action_just_triggered("shoot")
		and is_instance_valid(interaction_scanner)
	):
		if interaction_scanner.has_method("handle_shoot_input"):
			print("InteractionComponent: Forwarding shoot to scanner.")
			interaction_scanner.handle_shoot_input()


## Attempts to detect and grab a physics item within the grab shape cast volume.
## [return] True if an item was successfully grabbed.
func _try_pick_up() -> bool:
	interact_cast.force_shapecast_update()
	if interact_cast.is_colliding():
		for i: int in range(interact_cast.get_collision_count()):
			var collider: Object = interact_cast.get_collider(i)
			var target_body: Object = collider
			if target_body is Area3D:
				target_body = (target_body as Area3D).get_parent()

			if target_body is RigidBody3D and target_body.has_method("pick_up"):
				print(
					"InteractionComponent: Short-range grab successful on ",
					(target_body as Node).name
				)
				force_grab_item(target_body as RigidBody3D)
				return true
	return false


## Throws the currently held physics object forward along camera orientation.
func throw_held_item() -> void:
	print("InteractionComponent: throw_held_item() called.")
	if not is_instance_valid(held_item):
		return

	var item_to_throw: RigidBody3D = held_item

	var throw_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	throw_dir.y += 0.2
	var throw_force: Vector3 = throw_dir.normalized() * throw_strength

	if item_to_throw.has_method("throw"):
		item_to_throw.throw(throw_force)
	elif item_to_throw.has_method("throw_item"):
		item_to_throw.throw_item(throw_force, get_tree().current_scene)


## Releases and drops the currently held physics object to the floor.
func drop_held_item() -> void:
	print("InteractionComponent: drop_held_item() called. Placing item on ground.")
	if not is_instance_valid(held_item):
		return

	var item_to_drop: RigidBody3D = held_item

	if item_to_drop.has_method("drop"):
		item_to_drop.drop()
	elif item_to_drop.has_method("drop_item"):
		item_to_drop.drop_item(get_tree().current_scene, player.global_position)


## Resets local hands and restores weapons when any item is dropped globally.
## [param item] The item [Node3D] dropped.
## [param actor] The entity [Node3D] that initiated the drop.
func _on_global_item_dropped(item: Node3D, actor: Node3D) -> void:
	if actor == player:
		print("InteractionComponent: Global drop received. Restoring hands/weapons.")
		held_item = null
		_check_glider_restore(item)
		_set_weapon_active(true)


## Restores player sprint capabilities if the dropped item is a glider.
## [param item] The item [Node] being checked.
func _check_glider_restore(item: Node) -> void:
	if item.has_method("is_class") and item.get("class_name") == "GliderItem":
		print("InteractionComponent: Released GliderItem. Restoring sprint.")
		if "locomotion_component" in player and is_instance_valid(player.locomotion_component):
			var loco: PlayerLocomotionComponent = (
				player.locomotion_component as PlayerLocomotionComponent
			)
			loco.can_sprint = true
		is_heavy_lifting = false


## Enables or disables active weapon nodes.
## [param active] Visibility and process state to set.
func _set_weapon_active(active: bool) -> void:
	if is_instance_valid(weapon_holder):
		print("InteractionComponent: Setting weapon active state to: ", active)
		weapon_holder.visible = active
		weapon_holder.set_process(active)
		weapon_holder.set_physics_process(active)


## Directly forces the player to grab and hold a designated physics object.
## [param item] The [RigidBody3D] to grab.
func force_grab_item(item: RigidBody3D) -> void:
	print("InteractionComponent: force_grab_item() taking ownership of ", item.name)
	if is_instance_valid(held_item):
		drop_held_item()

	held_item = item
	_last_grab_time = Time.get_ticks_msec()

	if held_item.has_method("pick_up"):
		held_item.pick_up(hold_position, player)

	_set_weapon_active(false)


## Clears tracking state for carried items and unhides weapons.
func force_clear_hands() -> void:
	print("InteractionComponent: force_clear_hands() called." + " Clearing tracking variables.")
	held_item = null
	_set_weapon_active(true)


## Reparents and positions an item onto the weapon holder socket.
## [param item] The [Node3D] to attach.
## [param item_anchor] Spatial anchor marker [Marker3D].
## [param p_player] Target [Node3D] player instance.
func attach_item_to_weapon_holder(
	item: Node3D, item_anchor: Marker3D, p_player: Node3D = null
) -> void:
	print("InteractionComponent: attach_item_to_weapon_holder() called." + " Reparenting item.")

	var current_parent: Node = item.get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(item)

	weapon_holder.add_child(item)

	var offset: Vector3 = item.global_position - item_anchor.global_position
	item.global_position = hold_position.global_position + offset
	item.transform.basis = Basis.IDENTITY

	var target_player: CharacterBody3D = (
		(p_player if p_player != null else player) as CharacterBody3D
	)
	if (
		"locomotion_component" in target_player
		and is_instance_valid(target_player.locomotion_component)
	):
		var loco: PlayerLocomotionComponent = (
			target_player.locomotion_component as PlayerLocomotionComponent
		)
		loco.can_sprint = false
