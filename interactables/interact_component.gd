@tool
class_name InteractComponent
extends Node

signal interacted(character: CharacterBody3D)
signal focused
signal unfocused

var characters_hovering: Dictionary = {}
var is_currently_focused: bool = false
var last_hit_position: Vector3 = Vector3.ZERO
var _last_hover_time_msec: int = 0


func _ready() -> void:
	# Disable process by default to save performance.
	# It will only be enabled when actively hovered.
	set_process(false)


func interact_with(character: CharacterBody3D) -> void:
	print("InteractComponent: Passing interaction to parent from ", character.name)
	interacted.emit(character)  # Keep this in case you use signals elsewhere

	# Actually pass the call up to the parent node (e.g., your NoteItem)
	var parent: Node = get_parent()
	if parent and parent.has_method("interact_with"):
		parent.interact_with(character)


func hover_cursor(character: CharacterBody3D, hit_position: Vector3) -> void:
	#print("InteractComponent: hover_cursor called by ", character.name)

	var current_time: int = Time.get_ticks_msec()
	characters_hovering[character] = current_time
	_last_hover_time_msec = current_time
	last_hit_position = hit_position

	if not is_currently_focused:
		is_currently_focused = true
		print("InteractComponent: Focus gained.")
		focused.emit()
		set_process(true)  # Turn on _process only when needed


func get_character_hovered_by_cur_camera() -> CharacterBody3D:
	# ... (keep your existing camera check code) ...
	return null


func _process(_delta: float) -> void:
	var current_time: int = Time.get_ticks_msec()

	# Check a single global expiration timestamp instead of looping the dictionary
	if current_time - _last_hover_time_msec > 50:
		is_currently_focused = false
		characters_hovering.clear()

		print("InteractComponent: Focus lost due to timeout.")
		unfocused.emit()

		# Disable process loop completely until hovered again
		set_process(false)
