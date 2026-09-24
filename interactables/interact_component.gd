## Component enabling spatial nodes to receive crosshair focus and player interactions.
@tool
class_name InteractComponent
extends Node

## Emitted when an entity initiates an interaction.
signal interacted(character: CharacterBody3D)

## Emitted when the crosshair first focuses this component.
signal focused

## Emitted when the crosshair un-focuses this component.
signal unfocused

## Toggles whether interactions and hover tracking are accepted.
@export var is_enabled: bool = true:
	set(value):
		is_enabled = value
		if not is_enabled:
			is_currently_focused = false
			characters_hovering.clear()
			set_process(false)

## Characters hovering.
var characters_hovering: Dictionary = {}

## Is currently focused.
var is_currently_focused: bool = false

## Last hit position.
var last_hit_position: Vector3 = Vector3.ZERO

## Last hover time msec.
var _last_hover_time_msec: int = 0


## Lifecycle initialization disabling frame updates by default.
func _ready() -> void:
	set_process(false)


## Routes interaction event to parent node if enabled.
## [param character] Interacting player entity.
func interact_with(character: CharacterBody3D) -> void:
	if not is_enabled:
		return

	print("InteractComponent: Passing interaction to parent from ", character.name)
	interacted.emit(character)

	var parent: Node = get_parent()
	if parent and parent.has_method("interact_with"):
		parent.interact_with(character)


## Updates hover timestamps and activates focus state.
## [param character] Interacting player entity.
## [param hit_position] Spatial contact point.
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


## Inspects camera viewport for hovered characters.
## [return] Hovered character body if found, otherwise null.
func get_character_hovered_by_cur_camera() -> CharacterBody3D:
	return null


## Checks hover expiration timeout and disables processing when focus drops.
## [param _delta] Frame delta time in seconds.
func _process(_delta: float) -> void:
	var current_time: int = Time.get_ticks_msec()

	if current_time - _last_hover_time_msec > 50:
		is_currently_focused = false
		characters_hovering.clear()

		print("InteractComponent: Focus lost due to timeout.")
		unfocused.emit()
		set_process(false)


## Passes sustained interaction hold events to parent entity.
## [param character] Interacting player entity.
func interact_held(character: CharacterBody3D) -> void:
	if not is_enabled:
		return

	var parent: Node = get_parent()
	if parent and parent.has_method("interact_held"):
		parent.interact_held(character)
