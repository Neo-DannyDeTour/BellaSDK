extends Node
class_name HealthComponent

signal health_changed(current_health: int)
signal died()

@export var max_health: int = 100
@export var use_pooling: bool = false # Changed default to false to protect players

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
		
	# Failsafe: Never pool the player to prevent softlocks
	if use_pooling and not target_node.is_in_group("player"):
		print("HealthComponent: die() - Hiding and teleporting actor for pooling.")
		if target_node is Node3D:
			target_node.global_position = Vector3(0.0, -10000.0, 0.0)
			
		if target_node.has_method("hide"):
			target_node.hide()
			
		target_node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		print("HealthComponent: die() - Freeing actor (or handling player death).")
		# If this is the player, we just emit the signal and let the game manager handle death
		if not target_node.is_in_group("player"):
			target_node.queue_free()


func reset() -> void:
	print("HealthComponent: reset() - Restoring health for next spawn.")
	current_health = max_health
	health_changed.emit(current_health)
