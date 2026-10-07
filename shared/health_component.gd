## Manages entity hit points, damage mitigation, and death lifecycle pooling.
class_name HealthComponent
extends Node

## Emitted when [member current_health] changes. Passes the new health value.
signal health_changed(current_health: int)

## Emitted when [member max_health] changes. Passes the new maximum capacity.
signal max_health_changed(new_max: int)

## Emitted when [member current_health] drops to zero or below.
signal died

## The maximum health capacity of this entity.
@export var max_health: int = 100

## Teleports entity out of view for pooling instead of freeing upon death.
@export var use_pooling: bool = true

## Broadcasts updates directly to the global [Events] bus for player instances.
@export var is_player_health: bool = false

## The current internal health points remaining for this entity.
var current_health: int = 100


## Initializes health capacity and registers entity into the damageable group.
func _ready() -> void:
	print("HealthComponent: _ready() - Initializing health component.")
	current_health = max_health
	add_to_group(&"damageable")


## Subtracts damage from current health and handles death triggers.
## [param amount] Health points subtracted.
func take_damage(amount: int) -> void:
	print("HealthComponent: take_damage() - Took ", amount, " damage.")

	if is_player_health and Events.is_godmode:
		print("HealthComponent: take_damage() - Godmode active. Ignoring damage.")
		return

	if current_health <= 0 or amount <= 0:
		return

	current_health = maxi(0, current_health - amount)
	health_changed.emit(current_health)
	print("HealthComponent: take_damage() - Current health is now ", current_health, ".")

	if is_player_health:
		print("HealthComponent: take_damage() - Relaying damage to Events bus.")
		Events.player_damaged.emit(amount)
		Events.player_health_changed.emit(current_health)

	if current_health == 0:
		die()


## Restores health up to maximum capacity and emits update signals.
## [param amount] Health points added.
func heal(amount: int) -> void:
	print("HealthComponent: heal() - Healing for ", amount, ".")

	if current_health <= 0 or amount <= 0:
		return

	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health)
	print("HealthComponent: heal() - Current health is now ", current_health, ".")

	if is_player_health:
		print("HealthComponent: heal() - Relaying heal to global Events bus.")
		Events.player_healed.emit(amount)
		Events.player_health_changed.emit(current_health)


## Increases maximum capacity and raises current health proportionally.
## [param amount] Maximum capacity increase.
func increase_max_health(amount: int) -> void:
	print("HealthComponent: increase_max_health() - Increasing by ", amount, ".")
	max_health += amount
	current_health = mini(current_health + amount, max_health)

	health_changed.emit(current_health)
	max_health_changed.emit(max_health)
	print("HealthComponent: New max is ", max_health, ", current is ", current_health, ".")

	if is_player_health:
		print("HealthComponent: Relaying new health to global Events bus.")
		Events.player_health_changed.emit(current_health)


## Broadcasts death signals and hides, teleports, or frees the parent actor.
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
			var node_3d: Node3D = target_node if target_node is Node3D else null
			node_3d.global_position = Vector3(0.0, -10000.0, 0.0)
			node_3d.visible = false

		target_node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		print("HealthComponent: die() - Freeing actor.")
		if not target_node.is_in_group(&"player"):
			target_node.queue_free()


## Resets health to maximum and reactivates parent [Node3D] for pool reuse.
func reset() -> void:
	print("HealthComponent: reset() - Restoring health for next spawn.")
	current_health = max_health

	var target_node: Node = get_parent()
	if target_node is Node3D:
		var node_3d: Node3D = target_node if target_node is Node3D else null
		node_3d.visible = true
		node_3d.process_mode = Node.PROCESS_MODE_INHERIT

	health_changed.emit(current_health)
