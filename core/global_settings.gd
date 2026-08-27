## Global autoload managing the persistent save state of user preferences.
##
## [GlobalSettings] reads and writes values to a `.cfg` file on disk. It handles
## applying startup configurations like window scales, inputs, screen filters, and colorblind modes.
extends Node

## The file path where user preferences are saved locally on the player's disk.
const SAVE_PATH: String = "user://settings.cfg"

## The configuration object used to read, cache, and write save file data.
var config: ConfigFile = ConfigFile.new()

## Single source of truth for all typography font assets and metadata.
const FONT_REGISTRY: Array[Dictionary] = [
	{"id": "default", "name": "Default", "path": ""},
	{
		"id": "dyslexic",
		"name": "Dyslexic",
		"path": "res://assets/fonts/opendyslexic-0.92/OpenDyslexic-Regular.otf"
	},
	{"id": "papyrus", "name": "Papyrus", "path": "res://assets/fonts/papyrus-font/papyrus.ttf"},
	{"id": "comic", "name": "Comic Sans", "path": "res://assets/fonts/Comic Sans MS.ttf"},
	{"id": "kramola", "name": "Kramola", "path": "res://assets/fonts/kramola/Kramola.otf"},
	{
		"id": "futura",
		"name": "Futura Handwritten",
		"path": "res://assets/fonts/FuturaHandwritten.ttf"
	},
	{"id": "help_me", "name": "Help Me", "path": "res://assets/fonts/HelpMe.ttf"},
	{"id": "olde_english", "name": "Olde English", "path": "res://assets/fonts/OldeEnglish.ttf"},
	{
		"id": "stalinist",
		"name": "Stalinist One",
		"path": "res://assets/fonts/StalinistOne-Regular.ttf"
	},
	{"id": "super_funky", "name": "Super Funky", "path": "res://assets/fonts/Super Funky.ttf"}
]

## Single source of truth for all post-process screen filters and metadata.
const SCREEN_FILTER_REGISTRY: Array[Dictionary] = [
	{"id": "off", "name": "Off", "index": 0, "path": ""},
	{"id": "crt", "name": "CRT", "index": 1, "path": "res://vfx/crt.gdshader"},
	{"id": "vhs", "name": "VHS", "index": 2, "path": "res://vfx/vhs.gdshader"},
	{"id": "pixelate", "name": "Pixelate", "index": 3, "path": "res://vfx/pixelate.gdshader"},
	{"id": "toon", "name": "Toon", "index": 4, "path": "res://vfx/toon.gdshader"},
	{"id": "gameboy", "name": "Gameboy", "index": 5, "path": "res://vfx/gameboy.gdshader"},
	{"id": "glitch", "name": "Glitch", "index": 6, "path": "res://vfx/glitch.gdshader"},
	{"id": "grain", "name": "Grain", "index": 7, "path": "res://environment/grain.gdshader"},
	{"id": "halftone", "name": "Halftone", "index": 8, "path": "res://vfx/halftone.gdshader"},
	{
		"id": "nightvision",
		"name": "Nightvision",
		"index": 9,
		"path": "res://vfx/nightvision.gdshader"
	},
	{"id": "kuwahara", "name": "Kuwahara", "index": 10, "path": "res://vfx/kuwahara.gdshader"},
	{"id": "ascii", "name": "ASCII", "index": 11, "path": "res://vfx/ascii.gdshader"},
	{"id": "90anime", "name": "90Anime", "index": 12, "path": "res://vfx/90anime.gdshader"},
	{"id": "manga", "name": "Manga", "index": 13, "path": "res://vfx/manga.gdshader"},
	{"id": "handdrawn", "name": "Handdrawn", "index": 14, "path": "res://vfx/handdrawn.gdshader"},
	{"id": "moebius", "name": "Moebius", "index": 15, "path": "res://vfx/moebius.gdshader"},
	{"id": "obra", "name": "Obra", "index": 16, "path": "res://vfx/obra.gdshader"},
	{
		"id": "psychedelic",
		"name": "Psychedelic",
		"index": 17,
		"path": "res://vfx/psychedelic.gdshader"
	},
	{"id": "botw", "name": "BotW", "index": 18, "path": "res://vfx/botw.gdshader"},
	{"id": "ghibli", "name": "Ghibli", "index": 19, "path": "res://vfx/ghibli.gdshader"},
	{"id": "reaction", "name": "Reaction", "index": 20, "path": "res://vfx/reaction.gdshader"},
	{"id": "software", "name": "Software", "index": 21, "path": "res://vfx/software.gdshader"},
	{"id": "swirl", "name": "Swirl", "index": 22, "path": "res://vfx/swirl.gdshader"},
	{
		"id": "mandelbrot",
		"name": "Mandelbrot",
		"index": 23,
		"path": "res://vfx/mandelbrot.gdshader"
	},
	{"id": "80sfantasy", "name": "80sFantasy", "index": 24, "path": "res://vfx/80sfantasy.gdshader"}
]


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
	print("System: Applying boot settings (UI scale, fonts, colorblind, screen filters, prompts).")
	var ui_scale: float = get_setting("Settings", "ui_scale", 1.0) as float
	get_window().content_scale_factor = ui_scale

	if Events:
		var saved_font_idx: int = get_setting("Settings", "font_mode", 0) as int
		if saved_font_idx >= 0 and saved_font_idx < FONT_REGISTRY.size():
			var font_id: String = FONT_REGISTRY[saved_font_idx]["id"] as String
			Events.font_changed.emit(font_id)

		var saved_cb: int = get_setting("Settings", "colorblind_mode", 0) as int
		Events.colorblind_mode_changed.emit(saved_cb)

		var saved_filter_idx: int = get_setting("Settings", "screen_filter", 0) as int
		var filter_ids: Array[String] = get_screen_filter_ids()
		if saved_filter_idx >= 0 and saved_filter_idx < filter_ids.size():
			Events.screen_filter_changed.emit(filter_ids[saved_filter_idx])

		if Events.has_signal("item_prompts_toggled"):
			var show_prompts: bool = get_setting("Gameplay", "show_item_prompts", true) as bool
			Events.item_prompts_toggled.emit(show_prompts)


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


## Returns an array of all font internal ID keys.
## [return] [Array] of lowercase font identifier strings.
func get_font_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in FONT_REGISTRY:
		ids.append(entry["id"] as String)
	return ids


## Returns an array of all UI display names for fonts.
## [return] [Array] of formatted font names.
func get_font_display_names() -> Array[String]:
	var names: Array[String] = []
	for entry: Dictionary in FONT_REGISTRY:
		names.append(entry["name"] as String)
	return names


## Resolves a font index by its internal key.
## [param font_id] Target font key string.
## [return] [Array] index matching the ID, or `0` if not found.
func get_font_index(font_id: String) -> int:
	for i: int in range(FONT_REGISTRY.size()):
		if FONT_REGISTRY[i]["id"] == font_id:
			return i
	return 0


## Returns the list of UI display names for screen filters.
## [return] [Array] of formatted filter strings.
func get_screen_filter_display_names() -> Array[String]:
	print("GlobalSettings: Fetching screen filter display names.")
	var names: Array[String] = []
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		names.append(item.get("name", "") as String)
	return names


## Returns the list of string IDs for console and bus arguments.
## [return] [Array] of lowercase ID strings.
func get_screen_filter_ids() -> Array[String]:
	print("GlobalSettings: Fetching screen filter IDs.")
	var ids: Array[String] = []
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		ids.append(item.get("id", "") as String)
	return ids


## Resolves the diorama shader mode integer from a filter ID.
## [param filter_id] Target filter identifier string.
## [return] Corresponding integer index for the shader.
func get_screen_filter_index(filter_id: String) -> int:
	var clean_id: String = filter_id.to_lower()
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		if (item.get("id", "") as String) == clean_id:
			return item.get("index", 0) as int
	return 0


## Resolves the shader file resource path from a filter ID.
## [param filter_id] Target filter identifier string.
## [return] Resource file path string.
func get_screen_filter_path(filter_id: String) -> String:
	var clean_id: String = filter_id.to_lower()
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		if (item.get("id", "") as String) == clean_id:
			return item.get("path", "") as String
	return ""
