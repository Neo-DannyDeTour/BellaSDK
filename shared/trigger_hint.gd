@tool
class_name HintTrigger
extends Area3D

enum HintType { CUSTOM, INTERACT, JUMP, CROUCH, SPRINT, FLASHLIGHT, ZOOM }

@export_category("Level Design")

## Defines the 3D dimensions of the trigger volume in the editor.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_visuals()

## Determines the color of the editor-only visualizer box.
@export var trigger_color: Color = Color(0.2, 0.6, 1.0, 0.8):
	set(value):
		trigger_color = value
		_update_visuals()

## Sets the 3D text floating above the visualizer in the editor.
@export var trigger_text: String = "HINT":
	set(value):
		trigger_text = value
		_update_visuals()

@export_category("Hint Settings")

## Select a predefined message from the dropdown or choose CUSTOM.
@export var hint_type: HintType = HintType.INTERACT

## The text to display only if hint_type is set to CUSTOM. Use brackets like [interact].
@export var custom_message: String = ""

## If true, the hint will only trigger once and then permanently ignore future overlaps.
@export var trigger_once: bool = true

## Determines how long the hint message remains visible on the screen in seconds.
@export var duration: float = 3.0

## Internal flag indicating if the hint has already been shown.
var _triggered: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_visuals()
		return

	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			child.queue_free()

	body_entered.connect(_on_body_entered)


func _update_visuals() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		if not col.shape:
			col.shape = BoxShape3D.new()

		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true

		if col.shape is BoxShape3D:
			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = trigger_size

	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			child.trigger_size = trigger_size
			child.trigger_color = trigger_color
			child.trigger_text = trigger_text
			break


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	if trigger_once and _triggered:
		return

	_triggered = true
	var raw_message: String = _get_raw_message()
	var formatted_message: String = _format_message_with_keys(raw_message)

	print(
		"HintTrigger: Activated by ",
		body.name,
		" | Duration: ",
		duration,
		"s | Emitting: '",
		formatted_message,
		"'"
	)
	Events.hint_requested.emit(formatted_message, duration)


func _get_raw_message() -> String:
	match hint_type:
		HintType.INTERACT:
			return "Press [interact] to interact."
		HintType.JUMP:
			return "Press [jump] to jump."
		HintType.CROUCH:
			return "Press [crouch] to crouch."
		HintType.SPRINT:
			return "Press [sprint] to sprint."
		HintType.FLASHLIGHT:
			return "Press [flashlight] to toggle flashlight."
		HintType.ZOOM:
			return "Press [zoom] to zoom in."
		HintType.CUSTOM:
			return custom_message
		_:
			return ""


func _format_message_with_keys(text: String) -> String:
	print("HintTrigger: Parsing keys for message template...")
	var final_text: String = text
	var actions: Array[String] = [
		"forward",
		"backward",
		"left",
		"right",
		"jump",
		"crouch",
		"sprint",
		"interact",
		"flashlight",
		"zoom"
	]

	for action: String in actions:
		var bracket_action: String = "[" + action + "]"
		if final_text.contains(bracket_action):
			var events: Array[InputEvent] = InputMap.action_get_events(action)
			var key_name: String = "Unassigned"

			if events.size() > 0:
				var ev: InputEvent = events[0]

				if ev is InputEventKey:
					if ev.physical_keycode != 0:
						key_name = OS.get_keycode_string(ev.physical_keycode)
					else:
						key_name = OS.get_keycode_string(ev.keycode)
				elif ev is InputEventMouseButton:
					match ev.button_index:
						MOUSE_BUTTON_LEFT:
							key_name = "Left Click"
						MOUSE_BUTTON_RIGHT:
							key_name = "Right Click"
						MOUSE_BUTTON_MIDDLE:
							key_name = "Middle Click"
						_:
							key_name = "Mouse " + str(ev.button_index)
				else:
					key_name = ev.as_text().get_slice(" (", 0).strip_edges()

			final_text = final_text.replace(bracket_action, key_name)

	return final_text
