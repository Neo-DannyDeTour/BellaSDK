## Manages player entity physics properties, health linkage, and save state.
class_name PlayerStatsComponent
extends Node

## Player body mass used for weighing down dynamic puzzle platforms.
@export var player_mass: float = 80.0

## Injected [HealthComponent] managing player life points and death events.
@export var health_component: HealthComponent

## Cached reference to the controlling [Player] entity.
var player: Player


## Binds the controlling player and connects lifecycle signals.
func initialize(p_player: Player) -> void:
	print("StatsComponent: initialize() called. Caching player reference.")
	player = p_player

	if health_component == null and is_instance_valid(player):
		var found_health: Node = NodeQuery.find_first_child_of_type(player, HealthComponent)
		if found_health is HealthComponent:
			health_component = found_health as HealthComponent

	if is_instance_valid(health_component):
		health_component.health_changed.connect(_on_health_changed)
		health_component.died.connect(_on_player_died)


## Relays updated health points to the global [Events] bus.
func _on_health_changed(new_health: int) -> void:
	print("StatsComponent: _on_health_changed() called. New health: ", new_health)
	Events.player_health_changed.emit(new_health)


## Relays player death signal to the global [Events] bus.
func _on_player_died() -> void:
	print("StatsComponent: _on_player_died() called. Triggering game over.")
	Events.player_died.emit()


## Serializes player health state into a save data dictionary.
func get_save_data() -> Dictionary:
	print("StatsComponent: get_save_data() called. Fetching health.")
	var health_val: int = 100
	if is_instance_valid(health_component):
		health_val = health_component.current_health

	return {"health": health_val}


## Deserializes and restores player health from saved data.
func load_save_data(data: Dictionary) -> void:
	print("StatsComponent: load_save_data() called. Restoring health.")
	if is_instance_valid(health_component):
		var saved_health: int = data.get("health", 100)
		health_component.current_health = saved_health
		_on_health_changed(saved_health)
