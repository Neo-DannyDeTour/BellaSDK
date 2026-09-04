## Controls window mode, resolution, monitors, and framerate synchronization.
class_name DisplaySection
extends VBoxContainer

## Emitted when a display setting changes to trigger renderer pipeline updates.
signal display_settings_changed

## Reference to the display mode [OptionButton].
@onready var display_options: OptionButton = %DisplayOptionButton
## Reference to the active monitor [OptionButton].
@onready var monitor_options: OptionButton = %MonitorOptionButton
## Reference to the resolution [OptionButton].
@onready var resolution_options: OptionButton = %ResolutionOptionButton
## Reference to the framerate limit cap [OptionButton].
@onready var fps_options: OptionButton = %FPSOptionButton
## Reference to the VSync mode [OptionButton].
@onready var vsync_options: OptionButton = %VSyncOptionButton


## Connects UI signals and loads current display settings.
func _ready() -> void:
	print("DisplaySection: Initializing display settings UI.")
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Populates monitor list and configuration dropdown options.
func _populate_dropdowns() -> void:
	print("DisplaySection: Populating display dropdowns.")
	_fill_dropdown(display_options, VideoConfig.DISPLAY_MODES)
	_fill_dropdown(resolution_options, VideoConfig.RESOLUTIONS)
	_fill_dropdown(fps_options, VideoConfig.FPS_LIMITS)
	_fill_dropdown(vsync_options, VideoConfig.VSYNC_MODES)

	monitor_options.clear()
	var screen_count: int = DisplayServer.get_screen_count()
	for i: int in range(screen_count):
		monitor_options.add_item("Monitor " + str(i + 1))


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("DisplaySection: Connecting UI signals.")
	display_options.item_selected.connect(_on_display_selected)
	monitor_options.item_selected.connect(_on_monitor_selected)
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)
	vsync_options.item_selected.connect(_on_vsync_selected)


## Loads display configuration from disk and synchronizes widget states.
func load_settings() -> void:
	print("DisplaySection: Loading display settings from disk.")
	_sync_dropdown(
		display_options, VideoConfig.DISPLAY_MODES, "display_mode", VideoConfig.DEFAULT_DISPLAY
	)
	_sync_dropdown(fps_options, VideoConfig.FPS_LIMITS, "fps_limit", VideoConfig.DEFAULT_FPS)
	_sync_dropdown(vsync_options, VideoConfig.VSYNC_MODES, "vsync_mode", VideoConfig.DEFAULT_VSYNC)

	var saved_screen: int = GlobalSettings.get_setting("Settings", "screen_index", 0) as int
	if saved_screen < monitor_options.get_item_count():
		monitor_options.select(saved_screen)

	var res_x: int = GlobalSettings.get_setting("Settings", "resolution_x", 1920) as int
	var res_y: int = GlobalSettings.get_setting("Settings", "resolution_y", 1080) as int
	_select_dropdown_text(resolution_options, str(res_x) + " x " + str(res_y))


## Populates a single dropdown menu with keys from a dictionary.
## [param dropdown] The target [OptionButton] to fill.
## [param data_dict] Source dictionary holding option keys.
func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("DisplaySection: Populating dropdown entries.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


## Selects a dropdown item matching target label text.
## [param dropdown] The target [OptionButton].
## [param target_text] String label to find and select.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	print("DisplaySection: Selecting dropdown item by label: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Matches a saved value to an item in [param dropdown] using [param dict].
## [param dropdown] The option button to update.
## [param dict] Key-value dictionary associated with the option button.
## [param key] The config setting key identifier.
## [param default_val] Default fallback value if setting does not exist.
func _sync_dropdown(
	dropdown: OptionButton, dict: Dictionary, key: String, default_val: Variant
) -> void:
	print("DisplaySection: Syncing dropdown option with config key: ", key)
	var saved_val: Variant = GlobalSettings.get_setting("Settings", key, default_val)
	var saved_str: String = str(saved_val)

	for i: int in range(dropdown.get_item_count()):
		var item_text: String = dropdown.get_item_text(i)
		if item_text == saved_str:
			dropdown.select(i)
			return
		if dict.has(item_text) and str(dict[item_text]) == saved_str:
			dropdown.select(i)
			return


## Handles display window mode changes.
## [param index] Item index selected.
func _on_display_selected(index: int) -> void:
	print("DisplaySection: Display mode changed: ", index)
	var text: String = display_options.get_item_text(index)
	var mode: int = VideoConfig.DISPLAY_MODES[text] as int
	GlobalSettings.save_setting("Settings", "display_mode", mode)
	display_settings_changed.emit()


## Handles target monitor screen changes.
## [param index] Item index selected.
func _on_monitor_selected(index: int) -> void:
	print("DisplaySection: Monitor changed: ", index)
	GlobalSettings.save_setting("Settings", "screen_index", index)
	display_settings_changed.emit()


## Handles window resolution changes.
## [param index] Item index selected.
func _on_resolution_selected(index: int) -> void:
	print("DisplaySection: Resolution changed: ", index)
	var text: String = resolution_options.get_item_text(index)
	var res: Vector2i = VideoConfig.RESOLUTIONS[text] as Vector2i
	GlobalSettings.save_setting("Settings", "resolution_x", res.x)
	GlobalSettings.save_setting("Settings", "resolution_y", res.y)
	display_settings_changed.emit()


## Handles engine framerate cap limit changes.
## [param index] Item index selected.
func _on_fps_selected(index: int) -> void:
	print("DisplaySection: FPS limit changed: ", index)
	var limit: int = VideoConfig.FPS_LIMITS[fps_options.get_item_text(index)] as int
	GlobalSettings.save_setting("Settings", "fps_limit", limit)
	display_settings_changed.emit()


## Handles VSync mode selection.
## [param index] Item index selected.
func _on_vsync_selected(index: int) -> void:
	print("DisplaySection: VSync mode changed: ", index)
	var text: String = vsync_options.get_item_text(index)
	var mode: int = VideoConfig.VSYNC_MODES[text] as int
	GlobalSettings.save_setting("Settings", "vsync_mode", mode)
	display_settings_changed.emit()
