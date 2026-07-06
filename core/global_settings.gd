extends Node

const SAVE_PATH: String = "user://settings.cfg"
var config: ConfigFile = ConfigFile.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_all_settings()

func _load_all_settings() -> void:
	print("System: Loading global settings from disk.")
	config.load(SAVE_PATH)

func save_setting(category: String, key: String, value: Variant) -> void:
	print("System: Player saved setting -> [", category, "] ", key, ": ", value)
	config.set_value(category, key, value)
	config.save(SAVE_PATH)

func get_setting(category: String, key: String, default_value: Variant) -> Variant:
	if config.has_section_key(category, key):
		return config.get_value(category, key)
	return default_value
