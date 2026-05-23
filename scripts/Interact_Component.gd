@tool
class_name Interact_Component
extends Node

signal interacted(character: CharacterBody3D)
signal focused
signal unfocused

var characters_hovering := {}
var is_currently_focused := false
var last_hit_position := Vector3.ZERO  # NEW: Store the exact hit point


func interact_with(character: CharacterBody3D) -> void:
	interacted.emit(character)


# NEW: Accept a hit_position argument
func hover_cursor(character: CharacterBody3D, hit_position: Vector3) -> void:
	# Store the exact time in milliseconds instead of frames
	characters_hovering[character] = Time.get_ticks_msec()
	last_hit_position = hit_position


func get_character_hovered_by_cur_camera() -> CharacterBody3D:
	# ... (keep your existing camera check code) ...
	return null


func _process(_delta: float) -> void:
	var is_hovered := false
	var current_time := Time.get_ticks_msec()

	for character: CharacterBody3D in characters_hovering:
		# A 50ms buffer easily bridges the gap between 60Hz physics ticks
		if current_time - characters_hovering[character] <= 50:
			is_hovered = true
			break

	# Handle the Outline Shader Signals only when needed
	if is_hovered != is_currently_focused:
		is_currently_focused = is_hovered
		if is_currently_focused:
			focused.emit()
		else:
			unfocused.emit()
