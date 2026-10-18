@tool
## Physics trigger displaying key-binding hints and notifying [TTSManager].
class_name HintTrigger
extends BaseTriggerArea3D

## Predefined action types mapped to dynamic input hints.
enum HintType { CUSTOM, INTERACT, JUMP, CROUCH, SPRINT, FLASHLIGHT, ZOOM }

@export_category("Hint Settings")
## Select predefined message from dropdown or choose CUSTOM.
@export var hint_type: HintType = HintType.INTERACT

## Text displayed when [member hint_type] is CUSTOM. Use [interact].
@export_multiline var custom_message: String = ""

## Duration in seconds that hint remains visible on screen.
@export var duration: float = 3.0

## Broadcasts formatted hint message to screen UI via Events.
@export var show_on_screen: bool = true


## Initializes default trigger text label for editor visualizer.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "HINT"
	if trigger_color == Color(0.9, 0.5, 0.1, 0.25):
		trigger_color = Color(0.2, 0.6, 1.0, 0.25)
	if outline_color == Color(1.0, 0.8, 0.3, 0.9):
		outline_color = Color(0.4, 0.8, 1.0, 0.9)
	super._ready()


## Evaluates player entry, formats template tokens, and fires hints.
func _on_player_entered(player_node: Node3D) -> void:
	var raw_message: String = _get_raw_message()
	var formatted_message: String = _format_message_with_keys(raw_message)

	print(
		"HintTrigger: Activated by ",
		player_node.name,
		" | Emitting: '",
		formatted_message,
		"' | Screen: ",
		show_on_screen
	)

	if show_on_screen and has_node("/root/Events"):
		var events_node: Node = get_node("/root/Events")
		if events_node.has_signal(&"hint_requested"):
			events_node.emit_signal(&"hint_requested", formatted_message, duration)

	_dispatch_tts(formatted_message)


## Dispatches speech synthesis requests safely to [TTSManager].
func _dispatch_tts(message: String) -> void:
	print("HintTrigger: Forwarding message to TTSManager autoload.")
	if not has_node("/root/TTSManager"):
		return

	var tts_node: Node = get_node("/root/TTSManager")
	if is_instance_valid(tts_node) and tts_node.has_method(&"speak"):
		tts_node.call(&"speak", message, self)


## Resolves template prompt text matching assigned [member hint_type].
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


## Replaces bracket action tokens with key strings from [InputMap].
func _format_message_with_keys(text: String) -> String:
	print("HintTrigger: Formatting action tokens with InputMap keys.")
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

			if not events.is_empty():
				var ev: InputEvent = events[0]
				if ev is InputEventKey:
					var key_ev: InputEventKey = ev as InputEventKey
					if key_ev.physical_keycode != KEY_NONE:
						key_name = OS.get_keycode_string(key_ev.physical_keycode)
					else:
						key_name = OS.get_keycode_string(key_ev.keycode)
				elif ev is InputEventMouseButton:
					var mouse_ev: InputEventMouseButton = ev as InputEventMouseButton
					match mouse_ev.button_index:
						MOUSE_BUTTON_LEFT:
							key_name = "Left Click"
						MOUSE_BUTTON_RIGHT:
							key_name = "Right Click"
						MOUSE_BUTTON_MIDDLE:
							key_name = "Middle Click"
						_:
							key_name = "Mouse " + str(mouse_ev.button_index)
				else:
					key_name = ev.as_text().get_slice(" (", 0).strip_edges()

			final_text = final_text.replace(bracket_action, key_name)

	return final_text
