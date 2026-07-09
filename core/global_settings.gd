extends Node

## The file path where user preferences are saved locally on the player's disk.
const SAVE_PATH: String = "user://settings.cfg"

## The configuration object used to read, cache, and write save file data.
var config: ConfigFile = ConfigFile.new()

## List of available font types to cycle through for accessibility options.
const FONT_MAP: Array[String] = ["default", "dyslexic", "papyrus", "comic"]


func _init() -> void:
	# LOAD FIRST: We load data the moment this class is instanced, guaranteeing 
	# the config is populated before other Autoloads attempt to save to it.
	_load_all_settings()


func _ready() -> void:
	print("System: GlobalSettings Autoload initialized.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_input_mappings()
	call_deferred("_apply_boot_settings")


func _load_all_settings() -> void:
	print("System: Loading global settings from disk.")
	var err: Error = config.load(SAVE_PATH)
	if err != OK:
		print("System: No save file found or error loading. Code: ", err)


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


func _apply_input_mappings() -> void:
	print("System: Applying saved input mappings to Godot InputMap.")
	if config.has_section("Controls"):
		var saved_actions: PackedStringArray = config.get_section_keys("Controls")
		for action: String in saved_actions:
			var event: Variant = config.get_value("Controls", action)
			if event is InputEvent:
				InputMap.action_erase_events(action)
				InputMap.action_add_event(action, event)


func save_setting(category: String, key: String, value: Variant) -> void:
	print("System: Player saved setting -> [", category, "] ", key, ": ", value)
	config.set_value(category, key, value)
	config.save(SAVE_PATH)


func get_setting(category: String, key: String, default_value: Variant) -> Variant:
	if config.has_section_key(category, key):
		return config.get_value(category, key)
	return default_value
