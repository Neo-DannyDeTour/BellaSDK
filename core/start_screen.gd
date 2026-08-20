## Initial entry point screen that unlocks the browser audio context and pointer lock.
## Serves as an accessible barrier for web exports and sets up gameplay input.
class_name StartScreen
extends Control

## Target scene path to load once the user initiates focus.
@export_file("*.tscn") var main_game_scene_path: String = "res://scenes/MainGame.tscn"

## Reference to the primary activation button.
@onready var start_button: Button = $CenterContainer/StartButton


## Initializes UI focus on the main action button for screen-reader and keyboard users.
func _ready() -> void:
	print("StartScreen: _ready() called. Grabbing button focus.")
	start_button.pressed.connect(_on_start_button_pressed)
	start_button.grab_focus()


## Listens for initial key presses or clicks to unlock the browser session.
## [param event] The unhandled input event.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		if event.is_pressed():
			print("StartScreen: User interaction detected via input event.")
			_activate_and_start()


## Handles the start button press signal.
func _on_start_button_pressed() -> void:
	print("StartScreen: Start button pressed.")
	_activate_and_start()


## Acquires mouse capture, speaks the startup greeting, and transitions to the main scene.
func _activate_and_start() -> void:
	print("StartScreen: Activating pointer lock and routing to game scene.")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if has_node("/root/TTSManager"):
		var tts: Node = get_node("/root/TTSManager")
		if tts.has_method("play_startup_message"):
			tts.call("play_startup_message")

	if not main_game_scene_path.is_empty():
		get_tree().change_scene_to_file(main_game_scene_path)
