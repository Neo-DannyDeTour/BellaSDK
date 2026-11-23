@tool
## Editor plugin registering the GodotARKit bottom panel and [code]ARKitSingleton[/code] autoload.
extends EditorPlugin

## Autoload singleton name registered inside [ProjectSettings].
const ARKIT_AUTOLOAD_NAME: String = "ARKitSingleton"
## Resource path to the ARKit autoload script.
const ARKIT_AUTOLOAD_PATH: String = "res://addons/godot_arkit/arkit_autoload.gd"
## Preloaded bottom-panel scene for managing the ARKit UDP server and facial recording.
const ARKIT_MENU_SCENE: PackedScene = preload("res://addons/godot_arkit/arkit_menu.tscn")

## Instantiated bottom-panel control managed across plugin enter and exit lifecycle.
var control: Control = null


## Ensures the autoload is registered and attaches the GodotARKit bottom panel on editor startup.
func _enter_tree() -> void:
	if not ProjectSettings.has_setting("autoload/" + ARKIT_AUTOLOAD_NAME):
		add_autoload_singleton(ARKIT_AUTOLOAD_NAME, ARKIT_AUTOLOAD_PATH)
	_setup_ui()


## Removes and frees the GodotARKit bottom panel when the plugin exits the editor tree.
func _exit_tree() -> void:
	_teardown_ui()


## Registers the [code]ARKitSingleton[/code] autoload and initializes the bottom panel UI.
func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/" + ARKIT_AUTOLOAD_NAME):
		add_autoload_singleton(ARKIT_AUTOLOAD_NAME, ARKIT_AUTOLOAD_PATH)
	_setup_ui()


## Removes the bottom panel UI and unregisters the [code]ARKitSingleton[/code] autoload.
func _disable_plugin() -> void:
	_teardown_ui()
	if ProjectSettings.has_setting("autoload/" + ARKIT_AUTOLOAD_NAME):
		remove_autoload_singleton(ARKIT_AUTOLOAD_NAME)


## Instantiates [constant ARKIT_MENU_SCENE] and adds it to the editor bottom panel if not present.
func _setup_ui() -> void:
	if is_instance_valid(control):
		return
	var instance: Node = ARKIT_MENU_SCENE.instantiate()
	if instance is Control:
		control = instance as Control
		add_control_to_bottom_panel(control, "GodotARKit")


## Removes [member control] from the editor bottom panel and frees it safely.
func _teardown_ui() -> void:
	if is_instance_valid(control):
		remove_control_from_bottom_panel(control)
		control.queue_free()
		control = null
