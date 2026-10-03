## Initial entry point screen unlocking audio context and pointer lock for web exports.
class_name StartScreen
extends Control

## Target scene path to load once the user initiates focus.
@export_file("*.tscn") var main_game_scene_path: String = "res://scenes/MainGame.tscn"

## Reference to the primary activation [Button] node.
@onready var start_button: Button = $CenterContainer/StartButton


## Initializes UI focus on the main action button.
func _ready() -> void:
	print("StartScreen: _ready() called. Grabbing button focus.")
	start_button.pressed.connect(_on_start_button_pressed)
	start_button.grab_focus()


## Listens for initial key presses or clicks to unlock session.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			print("StartScreen: User interaction detected via input event.")
			_activate_and_start()


## Handles the start button press event.
func _on_start_button_pressed() -> void:
	print("StartScreen: Start button pressed.")
	_activate_and_start()


## Captures mouse cursor, triggers TTS greeting, and loads scene.
func _activate_and_start() -> void:
	print("StartScreen: Activating pointer lock and routing to game scene.")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	var tts: Node = SystemLocator.get_tts_manager()
	if is_instance_valid(tts) and tts.has_method("play_startup_message"):
		tts.call("play_startup_message")

	if not main_game_scene_path.is_empty():
		get_tree().change_scene_to_file(main_game_scene_path)
