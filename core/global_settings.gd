## Global autoload managing the persistent save state of user preferences.
##
## [GlobalSettings] reads and writes values to a `.cfg` file on disk. It handles
## applying startup configurations like window scales, inputs, and colorblind modes.
extends Node

## The file path where user preferences are saved locally on the player's disk.
const SAVE_PATH: String = "user://settings.cfg"

## The configuration object used to read, cache, and write save file data.
var config: ConfigFile = ConfigFile.new()

## List of available font types to cycle through for accessibility options.
const FONT_MAP: Array[String] = ["default", "dyslexic", "papyrus", "comic"]


## Called automatically upon instantiation.
## Populates the internal [ConfigFile] before other autoloads can read from it.
func _init() -> void:
	_load_all_settings()


## Called when the node enters the scene tree.
## Sets process mode and applies boot configurations.
func _ready() -> void:
	print("System: GlobalSettings Autoload initialized.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_input_mappings()
	call_deferred("_apply_boot_settings")


## Attempts to load the `.cfg` settings file from disk into the internal [ConfigFile].
func _load_all_settings() -> void:
	print("System: Loading global settings from disk.")
	var err: Error = config.load(SAVE_PATH)
	if err != OK:
		print("System: No save file found or error loading. Code: ", err)


## Broadcasts signals and sets global variables for visual options like UI scaling and fonts.
func _apply_boot_settings() -> void:
	print("System: Applying boot settings (UI scale, fonts, colorblind).")
	var ui_scale: float = get_setting("Settings", "ui_scale", 1.0) as float
	get_window().content_scale_factor = ui_scale

	if Events:
		var saved_font: int = get_setting("Settings", "font_mode", 0) as int
		if saved_font >= 0 and saved_font < FONT_MAP.size():
			Events.font_changed.emit(FONT_MAP[saved_font])

		var saved_cb: int = get_setting("Settings", "colorblind_mode", 0) as int
		Events.colorblind_mode_changed.emit(saved_cb)


## Overwrites the default Godot [InputMap] with any saved keybind overrides.
func _apply_input_mappings() -> void:
	print("System: Applying saved input mappings to Godot InputMap.")
	if not config.has_section("Controls"):
		return

	var saved_actions: PackedStringArray = config.get_section_keys("Controls")
	for action: String in saved_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

		var saved_data: Variant = config.get_value("Controls", action)

		if saved_data is Array:
			InputMap.action_erase_events(action)
			for event: Variant in saved_data:
				if event is InputEvent:
					InputMap.action_add_event(action, event)
		elif saved_data is InputEvent:
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, saved_data)


## Writes a specific setting to the config and immediately saves the file to disk.
## [param category] The section name within the config file.
## [param key] The identifier for the setting.
## [param value] The generic value to save.
func save_setting(category: String, key: String, value: Variant) -> void:
	print("System: Player saved setting -> [", category, "] ", key, ": ", value)
	config.set_value(category, key, value)
	config.save(SAVE_PATH)


## Retrieves a specific setting from the cached config file.
## [param category] The section name within the config file.
## [param key] The identifier for the setting.
## [param default_value] The fallback value returned if the key does not exist.
## Returns the stored [Variant] or the [param default_value].
func get_setting(category: String, key: String, default_value: Variant) -> Variant:
	if config.has_section_key(category, key):
		return config.get_value(category, key)
	return default_value
