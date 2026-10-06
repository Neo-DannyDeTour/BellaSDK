## Global autoload managing the persistent save state of user preferences.
#class_name GlobalSettings
extends Node

## The file path where user preferences are saved locally on the player's disk.
const SAVE_PATH: String = "user://settings.cfg"

## Debounce duration in seconds before flushing dirty config changes to disk.
const SAVE_DEBOUNCE_DELAY: float = 0.35

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
	{"id": "oldphoto", "name": "OldPhoto", "index": 25, "path": "res://vfx/old_photo.gdshader"},
	{"id": "80sfantasy", "name": "80sFantasy", "index": 24, "path": "res://vfx/80sfantasy.gdshader"}
]

## The configuration object used to read, cache, and write save file data.
var config: ConfigFile = ConfigFile.new()

## Internal timer managing debounced disk flushes to avoid main-thread lag.
var _save_debounce_timer: Timer

## Tracks whether in-memory settings diverge from the saved file on disk.
var _is_dirty: bool = false


## Populates the internal [ConfigFile] before other autoloads read from it.
func _init() -> void:
	print("System: GlobalSettings initialized.")
	_load_all_settings()


## Sets process mode, hooks up timer, and applies boot configurations.
func _ready() -> void:
	print("System: GlobalSettings Autoload initialized.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_debounce_timer()
	_ensure_default_weapon_actions()
	_apply_input_mappings()
	call_deferred("_apply_boot_settings")


## Intercepts termination requests to guarantee dirty settings are saved.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		print("System: Application termination requested. Flushing settings.")
		flush_to_disk()


## Writes setting to memory and queues debounced disk write.
func save_setting(category: String, key: String, value: Variant, immediate: bool = false) -> void:
	print("System: Player saved setting -> [", category, "] ", key, ": ", value)
	config.set_value(category, key, value)
	_is_dirty = true

	if immediate:
		flush_to_disk()
	else:
		_queue_debounced_save()


## Saves an entire dictionary of settings under a category and queues a flush.
func save_settings_bulk(category: String, data: Dictionary, immediate: bool = false) -> void:
	print("System: Bulk saving ", data.size(), " settings under [", category, "].")
	for key: Variant in data.keys():
		var key_str: String = str(key)
		config.set_value(category, key_str, data[key])
	_is_dirty = true

	if immediate:
		flush_to_disk()
	else:
		_queue_debounced_save()


## Flushes all pending in-memory configuration modifications directly to disk.
func flush_to_disk() -> void:
	if not _is_dirty:
		return

	if is_instance_valid(_save_debounce_timer) and not _save_debounce_timer.is_stopped():
		_save_debounce_timer.stop()

	print("System: Flushing dirty preferences cache to disk -> ", SAVE_PATH)
	var err: Error = config.save(SAVE_PATH)
	if err == OK:
		_is_dirty = false
	else:
		push_error("GlobalSettings: Failed to flush preferences to disk. Error: " + str(err))


## Retrieves a specific setting from the cached config file.
func get_setting(category: String, key: String, default_value: Variant) -> Variant:
	if config.has_section_key(category, key):
		return config.get_value(category, key)
	return default_value


## Returns an array of all font internal ID keys.
func get_font_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in FONT_REGISTRY:
		ids.append(str(entry.get("id", "")))
	return ids


## Returns an array of all UI display names for fonts.
func get_font_display_names() -> Array[String]:
	var names: Array[String] = []
	for entry: Dictionary in FONT_REGISTRY:
		names.append(str(entry.get("name", "")))
	return names


## Resolves a font index by its internal key.
func get_font_index(font_id: String) -> int:
	for i: int in range(FONT_REGISTRY.size()):
		if str(FONT_REGISTRY[i].get("id", "")) == font_id:
			return i
	return 0


## Returns the list of UI display names for screen filters.
func get_screen_filter_display_names() -> Array[String]:
	print("GlobalSettings: Fetching screen filter display names.")
	var names: Array[String] = []
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		names.append(str(item.get("name", "")))
	return names


## Returns the list of string IDs for console and bus arguments.
func get_screen_filter_ids() -> Array[String]:
	print("GlobalSettings: Fetching screen filter IDs.")
	var ids: Array[String] = []
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		ids.append(str(item.get("id", "")))
	return ids


## Resolves the diorama shader mode integer from a filter ID.
func get_screen_filter_index(filter_id: String) -> int:
	var clean_id: String = filter_id.to_lower()
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		if str(item.get("id", "")) == clean_id:
			var filter_idx: int = item.get("index", 0)
			return filter_idx
	return 0


## Resolves the shader file resource path from a filter ID.
func get_screen_filter_path(filter_id: String) -> String:
	var clean_id: String = filter_id.to_lower()
	for item: Dictionary in SCREEN_FILTER_REGISTRY:
		if str(item.get("id", "")) == clean_id:
			return str(item.get("path", ""))
	return ""


## Resolves the font asset file path matching a specified font identifier.
func get_font_path(font_id: String) -> String:
	for entry: Dictionary in FONT_REGISTRY:
		if str(entry.get("id", "")) == font_id:
			return str(entry.get("path", ""))
	return ""


## Loads and returns the [Font] resource for the given font identifier.
func get_font_resource(font_id: String) -> Font:
	print("GlobalSettings: Loading font resource for -> ", font_id)
	var path: String = get_font_path(font_id)
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as Font
	push_warning("GlobalSettings: Font resource path not found: " + path)
	return null


## Initializes the internal debounce timer node for lazy disk persistence.
func _setup_debounce_timer() -> void:
	print("GlobalSettings: Setting up debounce timer.")
	_save_debounce_timer = Timer.new()
	_save_debounce_timer.name = "SaveDebounceTimer"
	_save_debounce_timer.one_shot = true
	_save_debounce_timer.wait_time = SAVE_DEBOUNCE_DELAY
	_save_debounce_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_debounce_timer.timeout.connect(flush_to_disk)
	add_child(_save_debounce_timer)


## Attempts to load the config settings file from disk into [member config].
func _load_all_settings() -> void:
	print("System: Loading global settings from disk.")
	var err: Error = config.load(SAVE_PATH)
	if err != OK:
		print("System: No save file found or error loading. Code: ", err)


## Broadcasts signals and sets global variables for visual boot configurations.
func _apply_boot_settings() -> void:
	print("System: Applying boot settings (Window, VSync, UI scale, fonts).")
	var win: Window = get_window()
	var mode_val: int = get_setting("Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY)
	var mode: DisplayServer.WindowMode = mode_val as DisplayServer.WindowMode
	var screen_idx: int = get_setting("Settings", "screen_index", 0)
	var res_x: int = get_setting("Settings", "resolution_x", 1920)
	var res_y: int = get_setting("Settings", "resolution_y", 1080)
	var res: Vector2i = Vector2i(res_x, res_y)
	VideoApplier.apply_window_settings(win, mode, screen_idx, res)

	var vsync_val: int = get_setting("Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC)
	var vsync: DisplayServer.VSyncMode = vsync_val as DisplayServer.VSyncMode
	var fps_cap: int = get_setting("Settings", "fps_limit", VideoConfig.DEFAULT_FPS)
	VideoApplier.apply_engine_limits(vsync, fps_cap)

	var ui_scale: float = get_setting("Settings", "ui_scale", 1.0)
	win.content_scale_factor = ui_scale

	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events):
		var saved_font_idx: int = get_setting("Settings", "font_mode", 0)
		if saved_font_idx >= 0 and saved_font_idx < FONT_REGISTRY.size():
			var font_id: String = str(FONT_REGISTRY[saved_font_idx].get("id", ""))
			if events.has_signal("font_changed"):
				events.emit_signal("font_changed", font_id)

		var saved_cb: int = get_setting("Settings", "colorblind_mode", 0)
		if events.has_signal("colorblind_mode_changed"):
			events.emit_signal("colorblind_mode_changed", saved_cb)

		var saved_filter_idx: int = get_setting("Settings", "screen_filter", 0)
		var filter_ids: Array[String] = get_screen_filter_ids()
		if saved_filter_idx >= 0 and saved_filter_idx < filter_ids.size():
			if events.has_signal("screen_filter_changed"):
				events.emit_signal("screen_filter_changed", filter_ids[saved_filter_idx])

		if events.has_signal("item_prompts_toggled"):
			var show_prompts: bool = get_setting("Gameplay", "show_item_prompts", true)
			events.emit_signal("item_prompts_toggled", show_prompts)

		if events.has_signal("infinite_swim_toggled"):
			var inf_swim_raw: Variant = get_setting("Accessibility", "infinite_swim", false)
			var inf_swim: bool = inf_swim_raw == true
			events.emit_signal("infinite_swim_toggled", inf_swim)


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
			var event_list: Array = saved_data
			for raw_event: Variant in event_list:
				if raw_event is InputEvent:
					var event: InputEvent = raw_event
					InputMap.action_add_event(action, event)
		elif saved_data is InputEvent:
			InputMap.action_erase_events(action)
			var single_event: InputEvent = saved_data
			InputMap.action_add_event(action, single_event)


## Restarts the save debounce countdown to bundle closely timed writes together.
func _queue_debounced_save() -> void:
	print("System: Queued debounced save.")
	if is_instance_valid(_save_debounce_timer):
		_save_debounce_timer.start(SAVE_DEBOUNCE_DELAY)


## Ensures weapon slot bindings exist in [InputMap] on boot.
func _ensure_default_weapon_actions() -> void:
	print("System: Registering default weapon slot actions.")
	var defaults: Dictionary[String, Key] = {
		"weapon_slot_1": KEY_1,
		"weapon_slot_2": KEY_2,
		"weapon_slot_3": KEY_3,
		"weapon_slot_4": KEY_4,
		"weapon_slot_5": KEY_5,
		"last_weapon": KEY_X,
	}

	for action: String in defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key_ev: InputEventKey = InputEventKey.new()
			var key_val: Key = defaults[action]
			key_ev.keycode = key_val
			key_ev.physical_keycode = key_val
			InputMap.action_add_event(action, key_ev)
