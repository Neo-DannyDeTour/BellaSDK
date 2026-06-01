class_name HealthComponent
extends Node

signal health_changed(new_health: int)
signal died

@export var max_health: int = 300
var current_health: int


func _ready() -> void:
	current_health = max_health
	# We delay the initial signal slightly to ensure UI is ready to receive it
	call_deferred("emit_initial_health")


func emit_initial_health() -> void:
	health_changed.emit(current_health)


func take_damage(amount: int) -> void:
	if current_health <= 0:
		return

	current_health -= amount
	current_health = clampi(current_health, 0, max_health)

	health_changed.emit(current_health)

	if current_health == 0:
		died.emit()
		print("you're dead")


func heal(amount: int) -> void:
	if current_health <= 0:
		return

	current_health += amount
	current_health = clampi(current_health, 0, max_health)
	health_changed.emit(current_health)
