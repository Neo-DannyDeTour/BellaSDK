## Controls window mode, resolution, monitors, and framerate limits.
class_name DisplaySection
extends VBoxContainer

## Emitted when display settings change to trigger renderer pipeline updates.
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


## Lifecycle method initializing dropdown options and connecting signals.
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


## Connects UI input signals to corresponding handler methods.
func _connect_signals() -> void:
	print("DisplaySection: Connecting UI signals.")
	display_options.item_selected.connect(_on_display_selected)
	monitor_options.item_selected.connect(_on_monitor_selected)
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)
	vsync_options.item_selected.connect(_on_vsync_selected)


## Loads display settings from storage and updates dropdown selections.
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


## Populates a single [OptionButton] with keys from a dictionary.
## [param dropdown] The target [OptionButton] to fill.
## [param data_dict] Source dictionary holding option keys.
func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("DisplaySection: Populating dropdown entries.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


## Selects an [OptionButton] item matching target label text.
## [param dropdown] The target [OptionButton].
## [param target_text] String label to find and select.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	print("DisplaySection: Selecting dropdown item by label: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Matches a saved setting value to an item in an [OptionButton].
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


## Handles window mode changes and notifies listeners if modified.
## [param index] Item index selected.
func _on_display_selected(index: int) -> void:
	print("DisplaySection: Display mode selected: ", index)
	var text: String = display_options.get_item_text(index)
	var mode: int = VideoConfig.DISPLAY_MODES[text] as int
	var current_mode: int = (
		GlobalSettings.get_setting("Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY) as int
	)

	if current_mode != mode:
		GlobalSettings.save_setting("Settings", "display_mode", mode)
		display_settings_changed.emit()


## Handles target monitor changes and notifies listeners if modified.
## [param index] Item index selected.
func _on_monitor_selected(index: int) -> void:
	print("DisplaySection: Monitor selected: ", index)
	var current_screen: int = GlobalSettings.get_setting("Settings", "screen_index", 0) as int

	if current_screen != index:
		GlobalSettings.save_setting("Settings", "screen_index", index)
		display_settings_changed.emit()


## Handles resolution changes and bulk-saves coordinates if modified.
## [param index] Item index selected.
func _on_resolution_selected(index: int) -> void:
	print("DisplaySection: Resolution selected: ", index)
	var text: String = resolution_options.get_item_text(index)
	var res: Vector2i = VideoConfig.RESOLUTIONS[text] as Vector2i
	var cur_x: int = GlobalSettings.get_setting("Settings", "resolution_x", 1920) as int
	var cur_y: int = GlobalSettings.get_setting("Settings", "resolution_y", 1080) as int

	if cur_x != res.x or cur_y != res.y:
		GlobalSettings.save_settings_bulk(
			"Settings", {"resolution_x": res.x, "resolution_y": res.y}
		)
		display_settings_changed.emit()


## Handles engine framerate cap limit changes.
## [param index] Item index selected.
func _on_fps_selected(index: int) -> void:
	print("DisplaySection: FPS limit selected: ", index)
	var text: String = fps_options.get_item_text(index)
	var limit: int = VideoConfig.FPS_LIMITS[text] as int
	var current_limit: int = (
		GlobalSettings.get_setting("Settings", "fps_limit", VideoConfig.DEFAULT_FPS) as int
	)

	if current_limit != limit:
		GlobalSettings.save_setting("Settings", "fps_limit", limit)
		display_settings_changed.emit()


## Handles VSync mode selection changes.
## [param index] Item index selected.
func _on_vsync_selected(index: int) -> void:
	print("DisplaySection: VSync mode selected: ", index)
	var text: String = vsync_options.get_item_text(index)
	var mode: int = VideoConfig.VSYNC_MODES[text] as int
	var current_mode: int = (
		GlobalSettings.get_setting("Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC) as int
	)

	if current_mode != mode:
		GlobalSettings.save_setting("Settings", "vsync_mode", mode)
		display_settings_changed.emit()
