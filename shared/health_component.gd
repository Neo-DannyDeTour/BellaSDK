extends Node
## Manages health values, damage mitigation, and death pooling logic for game entities.
##
## Attach this to any node that needs to be damageable. Works directly with the player
## to broadcast global signals via [Events] and coordinates pooling via moving the parent [Node3D].
class_name HealthComponent

## Emitted when the current health changes.
signal health_changed(current_health: int)

## Emitted when the maximum health capacity changes.
signal max_health_changed(new_max: int)

## Emitted when current health reaches zero.
signal died

## The maximum health capacity of this entity.
@export var max_health: int = 100

## Determines if the entity is hidden and teleported for pooling instead of being freed on death.
@export var use_pooling: bool = true

## Flag to determine if this component belongs to the player,
## allowing broadcasting to the global Events bus.
@export var is_player_health: bool = false

## The current internal health amount of this entity.
var current_health: int = 100


## Initializes internal state and sets current health to the maximum capacity on node load.
func _ready() -> void:
	print("HealthComponent: _ready() - Initializing health component.")
	current_health = max_health


## Subtracts the given amount from current health and manages player death scenarios.
## [param amount] The damage value to apply.
func take_damage(amount: int) -> void:
	print("HealthComponent: take_damage() - Took ", amount, " damage.")

	if is_player_health and Events.get("is_godmode"):
		print("HealthComponent: take_damage() - Godmode is active. Ignoring damage.")
		return

	if current_health <= 0:
		return

	current_health -= amount
	current_health = maxi(0, current_health)

	health_changed.emit(current_health)
	print("HealthComponent: take_damage() - Current health is now ", current_health, ".")

	if is_player_health and Events.has_signal("player_health_changed"):
		print("HealthComponent: take_damage() - Relaying health to global Events bus.")
		Events.player_health_changed.emit(current_health)

	if current_health == 0:
		die()


## Adds the given amount to current health without exceeding the maximum capacity.
## [param amount] The healing value to apply.
func heal(amount: int) -> void:
	print("HealthComponent: heal() - Healing for ", amount, ".")

	if current_health <= 0:
		return

	current_health += amount
	current_health = mini(current_health, max_health)

	health_changed.emit(current_health)
	print("HealthComponent: heal() - Current health is now ", current_health, ".")


## Permanently increases the maximum health capacity and scales current health proportionally.
## [param amount] The health capacity value to add.
func increase_max_health(amount: int) -> void:
	print(
		"HealthComponent: increase_max_health() - Increasing max health capacity by ", amount, "."
	)

	max_health += amount
	current_health += amount
	current_health = mini(current_health, max_health)

	health_changed.emit(current_health)
	max_health_changed.emit(max_health)

	print(
		"HealthComponent: increase_max_health() - New max is ",
		max_health,
		". Current is ",
		current_health,
		"."
	)

	if is_player_health and Events.has_signal("player_health_changed"):
		print("HealthComponent: increase_max_health() - Relaying new health to global Events bus.")
		Events.player_health_changed.emit(current_health)


## Broadcasts death signals and hides/pools the parent node based on [member use_pooling].
func die() -> void:
	print("HealthComponent: die() - Entity died.")
	died.emit()

	var target_node: Node = get_parent()
	if target_node != null and target_node.get_class() == "Node":
		target_node = target_node.get_parent()

	if target_node == null:
		return

	if use_pooling:
		print("HealthComponent: die() - Hiding and teleporting actor for pooling.")
		if target_node is Node3D:
			target_node.global_position = Vector3(0.0, -10000.0, 0.0)

		if target_node.has_method("hide"):
			target_node.hide()

		target_node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		print("HealthComponent: die() - Freeing actor (or handling player death).")
		if not target_node.is_in_group("player"):
			target_node.queue_free()


## Resets current health back to maximum and re-enables the parent [Node3D] for pooling reuse.
func reset() -> void:
	print("HealthComponent: reset() - Restoring health for next spawn.")
	current_health = max_health

	var target_node: Node = get_parent()
	if target_node is Node3D:
		target_node.visible = true
		target_node.process_mode = Node.PROCESS_MODE_INHERIT

	health_changed.emit(current_health)
