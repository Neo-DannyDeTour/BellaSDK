class_name PlayerInteractionComponent
extends Node

@export_category("Item Handling")
@export var throw_strength: float = 15.0

@export_category("Node References")
@export var interact_cast: ShapeCast3D
@export var hold_position: Marker3D
@export var weapon_holder: Node3D
@export var camera: Camera3D
@export var interaction_scanner: Node

var player: Node3D
var held_item: RigidBody3D = null
var is_operating_machine: bool = false
var is_heavy_lifting: bool = false
var heavy_lift_yaw_base: float = 0.0
var is_in_terminal_mode: bool = false

var _last_grab_time: int = 0


func initialize(p_player: Node3D) -> void:
	print("InteractionComponent: initialize() called. Caching player reference.")
	player = p_player
	
	# Establish the hard link so the Scanner can talk back to the Master
	if is_instance_valid(interaction_scanner) and interaction_scanner.has_method("setup_master_link"):
		interaction_scanner.setup_master_link(self)
		
	# NEW: Listen for the item dropping so we can clear our hands automatically,
	# regardless of whether the player dropped it or it snagged on a wall.
	if not Events.item_dropped.is_connected(_on_global_item_dropped):
		Events.item_dropped.connect(_on_global_item_dropped)


func process_unhandled_input(event: InputEvent) -> void:
	# 1. Master Intercepts Held Item Actions First
	if event.is_action_pressed("interact") and is_instance_valid(held_item):
		if held_item.has_method("is_class") and held_item.get("class_name") == "GliderItem" and not player.is_on_floor():
			return
			
		if Time.get_ticks_msec() - _last_grab_time < 100:
			return

		print("InteractionComponent: Interact pressed while holding item. Requesting drop.")
		drop_held_item()
		return

	if (event.is_action_pressed("grenade_throw") or event.is_action_pressed("shoot")) and is_instance_valid(held_item):
		print("InteractionComponent: Throw action pressed. Throwing item.")
		throw_held_item()
		return

	# 2. Master Tries Short-Range Grab
	if event.is_action_pressed("interact") and not is_instance_valid(held_item):
		if _try_pick_up():
			return

	# 3. Master Delegates to Scanner for Long-Range / Terminals
	if event.is_action_pressed("interact") and is_instance_valid(interaction_scanner):
		if interaction_scanner.has_method("handle_interact_input"):
			interaction_scanner.handle_interact_input()

	if event.is_action_pressed("shoot") and is_instance_valid(interaction_scanner):
		if interaction_scanner.has_method("handle_shoot_input"):
			interaction_scanner.handle_shoot_input()


func _try_pick_up() -> bool:
	interact_cast.force_shapecast_update()
	if interact_cast.is_colliding():
		for i: int in range(interact_cast.get_collision_count()):
			var collider: Object = interact_cast.get_collider(i)
			var target_body: Object = collider
			if target_body is Area3D:
				target_body = target_body.get_parent()

			if target_body is RigidBody3D and target_body.has_method("pick_up"):
				print("InteractionComponent: Short-range grab successful on ", target_body.name)
				force_grab_item(target_body as RigidBody3D)
				return true
	return false


# --- MADE PUBLIC FOR EXTERNAL ACCESS ---
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


func drop_held_item() -> void:
	print("InteractionComponent: drop_held_item() called. Placing item on ground.")
	if not is_instance_valid(held_item):
		return
		
	var item_to_drop: RigidBody3D = held_item

	if item_to_drop.has_method("drop"):
		item_to_drop.drop()
	elif item_to_drop.has_method("drop_item"):
		item_to_drop.drop_item(get_tree().current_scene, player.global_position)


func _on_global_item_dropped(item: Node3D, actor: Node3D) -> void:
	# If the actor that dropped the item was this player, clear hands and reset state.
	# This fires whether the player chose to drop it, threw it, or a wall knocked it loose!
	if actor == player:
		print("InteractionComponent: Global drop received. Restoring hands/weapons.")
		held_item = null
		_check_glider_restore(item)
		_set_weapon_active(true)


func _check_glider_restore(item: Node) -> void:
	if item.has_method("is_class") and item.get("class_name") == "GliderItem":
		print("InteractionComponent: Released GliderItem. Restoring sprint.")
		if "locomotion_component" in player and is_instance_valid(player.locomotion_component):
			player.locomotion_component.can_sprint = true
		is_heavy_lifting = false


func _set_weapon_active(active: bool) -> void:
	if is_instance_valid(weapon_holder):
		weapon_holder.visible = active
		weapon_holder.set_process(active)
		weapon_holder.set_physics_process(active)


# --- SYNCHRONIZATION METHODS ---
func force_grab_item(item: RigidBody3D) -> void:
	print("InteractionComponent: force_grab_item() taking ownership of ", item.name)
	if is_instance_valid(held_item):
		drop_held_item()
		
	held_item = item
	_last_grab_time = Time.get_ticks_msec()
	
	if held_item.has_method("pick_up"):
		held_item.pick_up(hold_position, player)
		
	_set_weapon_active(false)


func force_clear_hands() -> void:
	print("InteractionComponent: force_clear_hands() called. Clearing tracking variables.")
	held_item = null
	_set_weapon_active(true)
