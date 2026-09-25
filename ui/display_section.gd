## Controls window mode, resolution, monitors, and framerate limits.
class_name DisplaySection
extends VBoxContainer

## Emitted when display settings change to trigger renderer pipeline updates.
signal display_settings_changed

## Reference to the exclusive fullscreen toggle [Button].
@onready var fullscreen_button: Button = %FullscreenButton
## Reference to the borderless windowed toggle [Button].
@onready var borderless_button: Button = %BorderlessButton
## Reference to the windowed mode toggle [Button].
@onready var windowed_button: Button = %WindowedButton
## Reference to the active monitor [OptionButton].
@onready var monitor_options: OptionButton = %MonitorOptionButton
## Reference to the resolution [OptionButton].
@onready var resolution_options: OptionButton = %ResolutionOptionButton
## Reference to the framerate limit cap [OptionButton].
@onready var fps_options: OptionButton = %FPSOptionButton
## Reference to the VSync disabled toggle [Button].
@onready var vsync_disabled_button: Button = %VSyncDisabledButton
## Reference to the VSync enabled toggle [Button].
@onready var vsync_enabled_button: Button = %VSyncEnabledButton
## Reference to the VSync adaptive toggle [Button].
@onready var vsync_adaptive_button: Button = %VSyncAdaptiveButton


## Lifecycle method initializing options, button groups, and signal hooks.
func _ready() -> void:
	print("DisplaySection: Initializing display settings UI.")
	_setup_button_groups()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Configures radio toggle button groups for display and VSync options.
func _setup_button_groups() -> void:
	print("DisplaySection: Setting up button toggle groups.")
	var display_group: ButtonGroup = ButtonGroup.new()
	fullscreen_button.button_group = display_group
	borderless_button.button_group = display_group
	windowed_button.button_group = display_group

	var vsync_group: ButtonGroup = ButtonGroup.new()
	vsync_disabled_button.button_group = vsync_group
	vsync_enabled_button.button_group = vsync_group
	vsync_adaptive_button.button_group = vsync_group


## Populates monitor and dropdown configuration options.
func _populate_dropdowns() -> void:
	print("DisplaySection: Populating display dropdowns.")
	_fill_dropdown(resolution_options, VideoConfig.RESOLUTIONS)
	_fill_dropdown(fps_options, VideoConfig.FPS_LIMITS)

	monitor_options.clear()
	var screen_count: int = DisplayServer.get_screen_count()
	for i: int in range(screen_count):
		monitor_options.add_item("Monitor " + str(i + 1))

	_check_adaptive_vsync_support()


## Connects UI input signals to handler methods.
func _connect_signals() -> void:
	print("DisplaySection: Connecting UI signals.")
	fullscreen_button.pressed.connect(
		_on_display_mode_pressed.bind(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	)
	borderless_button.pressed.connect(
		_on_display_mode_pressed.bind(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	windowed_button.pressed.connect(
		_on_display_mode_pressed.bind(DisplayServer.WINDOW_MODE_WINDOWED)
	)

	vsync_disabled_button.pressed.connect(_on_vsync_mode_pressed.bind(DisplayServer.VSYNC_DISABLED))
	vsync_enabled_button.pressed.connect(_on_vsync_mode_pressed.bind(DisplayServer.VSYNC_ENABLED))
	vsync_adaptive_button.pressed.connect(_on_vsync_mode_pressed.bind(DisplayServer.VSYNC_ADAPTIVE))

	monitor_options.item_selected.connect(_on_monitor_selected)
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)


## Loads display settings from storage and updates UI widgets.
func load_settings() -> void:
	print("DisplaySection: Loading display settings from disk.")
	var saved_display: int = (
		GlobalSettings.get_setting("Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY) as int
	)
	_update_display_mode_ui(saved_display)

	var saved_vsync: int = (
		GlobalSettings.get_setting("Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC) as int
	)
	_update_vsync_ui(saved_vsync)

	_sync_dropdown(fps_options, VideoConfig.FPS_LIMITS, "fps_limit", VideoConfig.DEFAULT_FPS)

	var saved_screen: int = GlobalSettings.get_setting("Settings", "screen_index", 0) as int
	if saved_screen < monitor_options.get_item_count():
		monitor_options.select(saved_screen)

	var res_x: int = GlobalSettings.get_setting("Settings", "resolution_x", 1920) as int
	var res_y: int = GlobalSettings.get_setting("Settings", "resolution_y", 1080) as int
	_select_dropdown_text(resolution_options, str(res_x) + " x " + str(res_y))


## Synchronizes display mode button toggle states.
func _update_display_mode_ui(active_mode: int) -> void:
	print("DisplaySection: Updating display mode buttons for mode: ", active_mode)
	fullscreen_button.button_pressed = (
		active_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	borderless_button.button_pressed = (active_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)
	windowed_button.button_pressed = (active_mode == DisplayServer.WINDOW_MODE_WINDOWED)


## Synchronizes VSync button toggle states.
func _update_vsync_ui(active_mode: int) -> void:
	print("DisplaySection: Updating VSync buttons for mode: ", active_mode)
	var is_exclusive: bool = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	vsync_adaptive_button.disabled = not is_exclusive
	if not is_exclusive and active_mode == DisplayServer.VSYNC_ADAPTIVE:
		active_mode = DisplayServer.VSYNC_ENABLED
		GlobalSettings.save_setting("Settings", "vsync_mode", active_mode)

	vsync_disabled_button.button_pressed = (active_mode == DisplayServer.VSYNC_DISABLED)
	vsync_enabled_button.button_pressed = (active_mode == DisplayServer.VSYNC_ENABLED)
	vsync_adaptive_button.button_pressed = (active_mode == DisplayServer.VSYNC_ADAPTIVE)


## Handles window mode button selection.
func _on_display_mode_pressed(mode: int) -> void:
	print("DisplaySection: Display mode selected: ", mode)
	var current_mode: int = (
		GlobalSettings.get_setting("Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY) as int
	)
	_update_display_mode_ui(mode)
	if current_mode != mode:
		GlobalSettings.save_setting("Settings", "display_mode", mode)
		display_settings_changed.emit()


## Handles VSync mode button selection.
func _on_vsync_mode_pressed(mode: int) -> void:
	print("DisplaySection: VSync mode selected: ", mode)
	var current_mode: int = (
		GlobalSettings.get_setting("Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC) as int
	)
	_update_vsync_ui(mode)
	if current_mode != mode:
		GlobalSettings.save_setting("Settings", "vsync_mode", mode)
		display_settings_changed.emit()


## Populates a single [OptionButton] with keys from a dictionary.
func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("DisplaySection: Populating dropdown entries.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


## Selects an [OptionButton] item matching target label text.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	print("DisplaySection: Selecting dropdown item by label: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Matches a saved setting value to an item in an [OptionButton].
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


## Handles target monitor changes and notifies listeners if modified.
func _on_monitor_selected(index: int) -> void:
	print("DisplaySection: Monitor selected: ", index)
	var current_screen: int = GlobalSettings.get_setting("Settings", "screen_index", 0) as int

	if current_screen != index:
		GlobalSettings.save_setting("Settings", "screen_index", index)
		display_settings_changed.emit()


## Handles resolution changes and bulk-saves coordinates if modified.
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


## Tests and disables the Adaptive VSync button if unsupported.
func _check_adaptive_vsync_support() -> void:
	print("DisplaySection: Checking Adaptive VSync driver support.")
	# On many Vulkan drivers/compositors, adaptive is rejected.
	# If unsupported, disable the button to prevent invalid engine fallback calls:
	var test_mode: DisplayServer.VSyncMode = DisplayServer.VSYNC_ADAPTIVE
	DisplayServer.window_set_vsync_mode(test_mode)

	if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_ADAPTIVE:
		vsync_adaptive_button.disabled = true
		vsync_adaptive_button.tooltip_text = "Adaptive V-Sync is not supported by your GPU/driver."
