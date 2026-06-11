class_name GliderItem
extends RigidBody3D

@onready var player_anchor: Marker3D = $PlayerAnchor


func pick_up(hold_position: Marker3D, player: CharacterBody3D) -> void:
	print("GliderItem: pick_up() called. Initiating tween sequence for player.")
	
	# 1. Disable physics while being picked up and held
	freeze = true
	collision_layer = 0
	collision_mask = 0
	
	# 2. Lock the player in place using your existing function
	player.set_machine_lock(true)
	
	# 3. Tween the player's global X/Z to the anchor, but keep their Y to avoid clipping into the floor
	var tween: Tween = get_tree().create_tween()
	var target_pos := Vector3(player_anchor.global_position.x, player.global_position.y, player_anchor.global_position.z)
	
	tween.tween_property(player, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_player_reached_anchor.bind(player, hold_position))


func _on_player_reached_anchor(player: CharacterBody3D, hold_position: Marker3D) -> void:
	print("GliderItem: Player reached anchor. Attaching glider to weapon holder.")
	
	# 1. Move the glider node into the player's weapon holder
	var current_parent: Node = get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(self)
		
	player.weapon_holder.add_child(self)
	
	# 2. Align the glider so the anchor sits exactly at the player's hold_position
	var offset: Vector3 = global_position - player_anchor.global_position
	global_position = hold_position.global_position + offset
	
	# 3. Reset rotation so it faces forward relative to the camera/holder
	transform.basis = Basis.IDENTITY
	
	# 4. Apply restrictions and unlock the player
	player.can_sprint = false
	player.set_machine_lock(false)


func throw_item(force: Vector3, scene_root: Node) -> void:
	print("GliderItem: throw_item() called. Releasing glider into the world.")
	
	# Detach from player and put back in world
	var current_parent: Node = get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(self)
		
	scene_root.add_child(self)
	
	# Re-enable physics
	freeze = false
	collision_layer = 1
	collision_mask = 1
	
	apply_central_impulse(force)


func drop_item(scene_root: Node, drop_pos: Vector3) -> void:
	print("GliderItem: drop_item() called. Detaching from player.")
	
	var current_parent: Node = get_parent()
	if is_instance_valid(current_parent):
		current_parent.remove_child(self)
		
	scene_root.add_child(self)
	
	# Place it safely at the player's feet
	global_position = drop_pos
	transform.basis = Basis.IDENTITY 
	
	# Re-enable physics so it can be picked up again
	freeze = false
	collision_layer = 1
	collision_mask = 1
