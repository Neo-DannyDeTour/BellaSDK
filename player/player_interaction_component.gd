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

var player: Player
var held_item: RigidBody3D = null
var is_operating_machine: bool = false
var is_heavy_lifting: bool = false
var heavy_lift_yaw_base: float = 0.0
var is_in_terminal_mode: bool = false

func initialize(p_player: Player) -> void:
	print("InteractionComponent: initialize() called. Caching player reference.")
	player = p_player


func process_unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and is_instance_valid(held_item):
		if held_item.has_method("is_class") and held_item.get("class_name") == "GliderItem" and not player.is_on_floor():
			return
			
		print("InteractionComponent: Interact pressed while holding item. Dropping.")
		_drop_held_item()
		return

	if (event.is_action_pressed("grenade_throw") or event.is_action_pressed("shoot")) and is_instance_valid(held_item):
		print("InteractionComponent: Throw action pressed. Throwing item.")
		_throw_held_item()
		return

	if event.is_action_pressed("interact") and not is_instance_valid(held_item):
		if _try_pick_up():
			return 

	if event.is_action_pressed("interact") and is_instance_valid(interaction_scanner):
		print("InteractionComponent: Routing unhandled interact input to scanner.")
		interaction_scanner.handle_interact_input()

	if event.is_action_pressed("shoot") and is_instance_valid(interaction_scanner):
		print("InteractionComponent: Routing unhandled shoot input to scanner.")
		interaction_scanner.handle_shoot_input()


func _try_pick_up() -> bool:
	print("InteractionComponent: _try_pick_up() called. Scanning for objects.")
	interact_cast.force_shapecast_update()

	if interact_cast.is_colliding():
		var collision_count: int = interact_cast.get_collision_count()

		for i: int in range(collision_count):
			var collider: Object = interact_cast.get_collider(i)
			print("InteractionComponent: Scanning [", i, "] ", collider.name)

			var target_body: Object = collider
			if target_body is Area3D:
				target_body = target_body.get_parent()

			if target_body is RigidBody3D and target_body.has_method("pick_up"):
				print("InteractionComponent: Successfully grabbed ", target_body.name, "!")
				held_item = target_body as RigidBody3D
				held_item.pick_up(hold_position, player)
				return true
	return false


func _throw_held_item() -> void:
	print("InteractionComponent: _throw_held_item() called.")
	var item_to_throw: RigidBody3D = held_item
	held_item = null  # Clear our reference before the item clears it for us
	
	var throw_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	throw_dir.y += 0.2
	var throw_force: Vector3 = throw_dir.normalized() * throw_strength

	if item_to_throw.has_method("throw"):
		item_to_throw.throw(throw_force)
	elif item_to_throw.has_method("throw_item"):
		item_to_throw.throw_item(throw_force, get_tree().current_scene)
	
	# Replace the duck-typed check here:
	if item_to_throw is GliderItem:
		print("InteractionComponent: Threw GliderItem. Restoring sprint.")
		if is_instance_valid(player.locomotion_component):
			player.locomotion_component.can_sprint = true
		is_heavy_lifting = false
		
	_set_weapon_active(true)


func _drop_held_item() -> void:
	print("InteractionComponent: _drop_held_item() called. Placing item on ground.")
	var item_to_drop: RigidBody3D = held_item
	held_item = null  # Clear our reference before the item clears it for us
	
	if item_to_drop.has_method("drop"):
		item_to_drop.drop()
	elif item_to_drop.has_method("drop_item"):
		item_to_drop.drop_item(get_tree().current_scene, player.global_position)
		
	# Replace the duck-typed check here:
	if item_to_drop is GliderItem:
		print("InteractionComponent: Dropped GliderItem. Restoring sprint.")
		if is_instance_valid(player.locomotion_component):
			player.locomotion_component.can_sprint = true
		is_heavy_lifting = false
		
	_set_weapon_active(true)


func _set_weapon_active(active: bool) -> void:
	print("InteractionComponent: _set_weapon_active() called. State: ", active)
	if is_instance_valid(weapon_holder):
		weapon_holder.visible = active
		weapon_holder.set_process(active)
		weapon_holder.set_physics_process(active)


func enter_terminal_mode(terminal: Node3D) -> void:
	print("InteractionComponent: enter_terminal_mode() called. Passing to Scanner.")
	if is_instance_valid(interaction_scanner):
		interaction_scanner.enter_terminal_mode(terminal)


func process_interaction(delta: float) -> void:
	# Print statement omitted here to prevent console spam at 60 FPS
	var scanner_valid: bool = is_instance_valid(interaction_scanner)
	if scanner_valid and interaction_scanner.has_method("process_interaction"):
		interaction_scanner.process_interaction(delta)
