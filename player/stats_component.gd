class_name PlayerStatsComponent
extends Node

@export_category("Physics Properties")
## Essential for weighing down pulley carts and platforms.
@export var player_mass: float = 80.0

@export_category("Node References")
@export var health_component: Node

var player: Player

func initialize(p_player: Player) -> void:
	print("StatsComponent: initialize() called. Caching player reference.")
	player = p_player
	
	if is_instance_valid(health_component):
		if health_component.has_signal("health_changed"):
			health_component.health_changed.connect(_on_health_changed)
		if health_component.has_signal("died"):
			health_component.died.connect(_on_player_died)

func _on_health_changed(new_health: int) -> void:
	print("StatsComponent: _on_health_changed() called. New health: ", new_health)
	if Events.has_signal("player_health_changed"):
		Events.player_health_changed.emit(new_health)

func _on_player_died() -> void:
	print("StatsComponent: _on_player_died() called. Triggering game over.")
	if Events.has_signal("player_died"):
		Events.player_died.emit()

func get_save_data() -> Dictionary:
	print("StatsComponent: get_save_data() called. Fetching health.")
	var health_val: int = 100

	if is_instance_valid(health_component):
		if "current_health" in health_component:
			health_val = health_component.get("current_health")
		elif "health" in health_component:
			health_val = health_component.get("health")

	return {
		"health": health_val
	}

func load_save_data(data: Dictionary) -> void:
	print("StatsComponent: load_save_data() called. Restoring health.")
	if is_instance_valid(health_component):
		var saved_health: int = data.get("health", 100)

		if "current_health" in health_component:
			health_component.set("current_health", saved_health)
		elif "health" in health_component:
			health_component.set("health", saved_health)

		_on_health_changed(saved_health)
