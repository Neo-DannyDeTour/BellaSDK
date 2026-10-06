## Component enabling spatial nodes to receive crosshair focus and player interactions.
@tool
class_name InteractComponent
extends Node

## Emitted when [param character] initiates an interaction with this component.
signal interacted(character: CharacterBody3D)

## Emitted when the crosshair first focuses this component.
signal focused

## Emitted when the crosshair un-focuses this component.
signal unfocused

## Toggles whether interactions and hover tracking are accepted.
@export var is_enabled: bool = true:
	set(value):
		is_enabled = value
		if not is_inside_tree():
			return
		if not is_enabled:
			is_currently_focused = false
			characters_hovering.clear()
			set_process(false)

## Dictionary tracking hovering character bodies and their hover timestamps.
var characters_hovering: Dictionary = {}

## Indicates whether crosshair focus is currently active on this component.
var is_currently_focused: bool = false

## Stores the last world hit position recorded from interaction raycasts.
var last_hit_position: Vector3 = Vector3.ZERO

## Timestamp in milliseconds of the last registered hover event.
var _last_hover_time_msec: int = 0


## Disables frame processing on initialization until focus is acquired.
func _ready() -> void:
	set_process(false)


## Dispatches interaction event to listeners and invokes parent method.
func interact_with(character: CharacterBody3D) -> void:
	if not is_enabled:
		return

	print("InteractComponent: Passing interaction to parent from ", character.name)
	interacted.emit(character)

	var parent: Node = get_parent()
	if is_instance_valid(parent) and parent.has_method(&"interact_with"):
		parent.call(&"interact_with", character)


## Updates hover timestamps, contact position, and emits [signal focused].
func hover_cursor(character: CharacterBody3D, hit_position: Vector3) -> void:
	if not is_enabled:
		if is_currently_focused:
			is_currently_focused = false
			unfocused.emit()
			set_process(false)
		return

	var current_time: int = Time.get_ticks_msec()
	characters_hovering[character] = current_time
	_last_hover_time_msec = current_time
	last_hit_position = hit_position

	if not is_currently_focused:
		is_currently_focused = true
		print("InteractComponent: Focus gained.")
		focused.emit()
		set_process(true)


## Returns character hovered by the current camera viewport or null.
func get_character_hovered_by_cur_camera() -> CharacterBody3D:
	return null


## Checks hover timeout and deactivates focus when cursor leaves target.
func _process(_delta: float) -> void:
	var current_time: int = Time.get_ticks_msec()

	if current_time - _last_hover_time_msec > 50:
		is_currently_focused = false
		characters_hovering.clear()

		print("InteractComponent: Focus lost due to timeout.")
		unfocused.emit()
		set_process(false)


## Passes sustained interaction hold events to parent entity.
func interact_held(character: CharacterBody3D) -> void:
	if not is_enabled:
		return

	print("InteractComponent: Passing sustained interaction to parent from ", character.name)
	var parent: Node = get_parent()
	if is_instance_valid(parent) and parent.has_method(&"interact_held"):
		parent.call(&"interact_held", character)
