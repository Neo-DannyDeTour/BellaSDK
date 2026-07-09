extends Node # Ensure this is at the very top

const SAVE_PATH: String = "user://settings.cfg"
var config: ConfigFile = ConfigFile.new()
const FONT_MAP: Array[String] = ["default", "dyslexic", "papyrus", "comic"]

func _ready() -> void:
	# process_mode is a property of Node
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_all_settings()
	call_deferred("_apply_boot_settings")


func _load_all_settings() -> void:
	print("System: Loading global settings from disk.")
	var err: Error = config.load(SAVE_PATH)
	if err != OK:
		print("System: No save file found or error loading. Code: ", err)


func _apply_boot_settings() -> void:
	# get_window() is available to all Nodes
	var ui_scale: float = get_setting("Settings", "ui_scale", 1.0) as float
	get_window().content_scale_factor = ui_scale

	# Use GlobalSettings to safely access Events
	# Do not call get_node("/root/Events") directly if you can avoid it.
	# Instead, use the autoload name directly.
	if Events: 
		var saved_font: int = get_setting("Settings", "font_mode", 0) as int
		if saved_font >= 0 and saved_font < FONT_MAP.size():
			Events.font_changed.emit(FONT_MAP[saved_font])
			
		var saved_cb: int = get_setting("Settings", "colorblind_mode", 0) as int
		Events.colorblind_mode_changed.emit(saved_cb)


func save_setting(category: String, key: String, value: Variant) -> void:
	print("System: Player saved setting -> [", category, "] ", key, ": ", value)
	config.set_value(category, key, value)
	config.save(SAVE_PATH)


func get_setting(category: String, key: String, default_value: Variant) -> Variant:
	if config.has_section_key(category, key):
		return config.get_value(category, key)
	return default_value
