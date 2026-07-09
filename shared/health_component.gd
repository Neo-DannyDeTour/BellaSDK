extends Node
class_name HealthComponent

signal health_changed(current_health: int)
signal died()

@export var max_health: int = 100
@export var use_pooling: bool = true 
@export var is_player_health: bool = false

var current_health: int = 100


func _ready() -> void:
	current_health = max_health
	print("HealthComponent: _ready() - Initialized with ", current_health, " health.")


func take_damage(amount: int) -> void:
	print("HealthComponent: take_damage() - Took ", amount, " damage.")
	
	if current_health <= 0:
		return
		
	current_health -= amount
	current_health = maxi(0, current_health)
	
	health_changed.emit(current_health)
	print("HealthComponent: take_damage() - Current health is now ", current_health, ".")
	
	# Strictly check the export variable instead of the group tag
	if is_player_health and Events.has_signal("player_health_changed"):
		print("HealthComponent: take_damage() - Relaying health to global Events bus.")
		Events.player_health_changed.emit(current_health)
	
	if current_health == 0:
		die()


func heal(amount: int) -> void:
	print("HealthComponent: heal() - Healing for ", amount, ".")
	
	if current_health <= 0:
		return
		
	current_health += amount
	current_health = mini(current_health, max_health)
	
	health_changed.emit(current_health)
	print("HealthComponent: heal() - Current health is now ", current_health, ".")


func die() -> void:
	print("HealthComponent: die() - Entity died.")
	died.emit()
	
	var target_node: Node = get_parent()
	if target_node != null and target_node.get_class() == "Node":
		target_node = target_node.get_parent()
		
	if target_node == null:
		return
		
	# Trust the 'use_pooling' export toggle strictly instead of checking groups
	if use_pooling:
		print("HealthComponent: die() - Hiding and teleporting actor for pooling.")
		if target_node is Node3D:
			target_node.global_position = Vector3(0.0, -10000.0, 0.0)
			
		if target_node.has_method("hide"):
			target_node.hide()
			
		target_node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		print("HealthComponent: die() - Freeing actor (or handling player death).")
		# Only queue_free if this isn't the actual player character
		if not target_node.is_in_group("player"):
			target_node.queue_free()


func reset() -> void:
	print("HealthComponent: reset() - Restoring health for next spawn.")
	current_health = max_health
	
	var target_node: Node = get_parent()
	if target_node is Node3D:
		target_node.visible = true
		target_node.process_mode = Node.PROCESS_MODE_INHERIT
		
	health_changed.emit(current_health)
