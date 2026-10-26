## Drops onto the main menu to trigger [LoadingScreen] transitions to a testbed.
class_name DevTestbedLoader
extends Node

## Fallback path to the loading screen scene resource.
const DEFAULT_LOADING_SCREEN_PATH: String = "res://ui/loading_screen.tscn"

## Scene template for the [LoadingScreen] interface.
@export var loading_screen_scene: PackedScene

## Scene file path of the testbed level to load.
@export_file("*.tscn", "*.scn") var testbed_path: String = "res://levels/testbed2.tscn"

## If true, automatically loads the testbed when running in debug mode.
@export var auto_launch_in_debug: bool = true

## Keyboard shortcut used to trigger the testbed load manually.
@export var quick_load_key: Key = KEY_F1


## Evaluates debug mode and schedules auto-launch if configured.
func _ready() -> void:
	if not OS.is_debug_build():
		return

	if auto_launch_in_debug:
		print("DevTestbedLoader: Debug build detected. Auto-launching testbed.")
		launch_testbed.call_deferred()


## Listens for [member quick_load_key] to start transition.
func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == quick_load_key:
			print("DevTestbedLoader: Quick load shortcut triggered.")
			launch_testbed()


## Spawns [LoadingScreen] and requests asynchronous level loading.
func launch_testbed() -> void:
	print("DevTestbedLoader: Launching testbed via LoadingScreen.")
	if LoadingScreen.is_transition_active:
		push_warning("DevTestbedLoader: Transition already active.")
		return

	var target_scene: PackedScene = loading_screen_scene
	if not is_instance_valid(target_scene):
		if ResourceLoader.exists(DEFAULT_LOADING_SCREEN_PATH):
			target_scene = load(DEFAULT_LOADING_SCREEN_PATH) as PackedScene

	if not is_instance_valid(target_scene):
		push_error("DevTestbedLoader: No loading_screen_scene assigned or found at default path!")
		return

	if testbed_path.is_empty():
		push_error("DevTestbedLoader: No testbed_path configured!")
		return

	var loader_instance: LoadingScreen = target_scene.instantiate() as LoadingScreen
	loader_instance.level_scene_path = testbed_path
	get_tree().root.add_child(loader_instance)
