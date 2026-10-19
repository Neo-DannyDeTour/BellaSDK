## Controls window mode, active monitor, screen resolution, VSync, and framerate cap.
class_name DisplaySection
extends VBoxContainer

## Emitted when any display or window setting is modified by the player.
@warning_ignore("unused_signal")
signal display_settings_changed

## Reference to the exclusive fullscreen toggle [Button].
@onready var fullscreen_button: Button = %FullscreenButton

## Reference to the borderless windowed toggle [Button].
@onready var borderless_button: Button = %BorderlessButton

## Reference to the windowed mode toggle [Button].
@onready var windowed_button: Button = %WindowedButton

## Reference to the active monitor selection [OptionButton].
@onready var monitor_options: OptionButton = %MonitorOptionButton

## Reference to the screen resolution selection [OptionButton].
@onready var resolution_options: OptionButton = %ResolutionOptionButton

## Reference to the framerate cap selection [OptionButton].
@onready var fps_options: OptionButton = %FPSOptionButton

## Reference to the VSync disabled toggle [Button].
@onready var vsync_disabled_button: Button = %VSyncDisabledButton

## Reference to the VSync enabled toggle [Button].
@onready var vsync_enabled_button: Button = %VSyncEnabledButton

## Reference to the VSync adaptive toggle [Button].
@onready var vsync_adaptive_button: Button = %VSyncAdaptiveButton


## Initializes display widgets, button groups, and signal listeners.
func _ready() -> void:
	print("DisplaySection: Initializing display settings UI.")
	set_process(false)
	set_physics_process(false)
	_setup_button_groups()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Synchronizes all display UI controls with the active configuration in [GraphicsManager].
func load_settings() -> void:
	print("DisplaySection: Synchronizing display UI with active configuration.")
	var display_mode: int = GlobalSettings.get_setting_int(
		"Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY
	)
	_update_display_mode_buttons(display_mode)

	var vsync_mode: int = GlobalSettings.get_setting_int(
		"Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC
	)
	_update_vsync_buttons(vsync_mode, display_mode)

	var fps_cap: int = GlobalSettings.get_setting_int(
		"Settings", "fps_limit", VideoConfig.DEFAULT_FPS
	)
	_select_fps_option(fps_cap)

	var screen_idx: int = GlobalSettings.get_setting_int("Settings", "screen_index", 0)
	if screen_idx >= 0 and screen_idx < monitor_options.get_item_count():
		monitor_options.select(screen_idx)

	var res_x: int = GlobalSettings.get_setting_int(
		"Settings", "resolution_x", VideoConfig.DEFAULT_RES_X
	)
	var res_y: int = GlobalSettings.get_setting_int(
		"Settings", "resolution_y", VideoConfig.DEFAULT_RES_Y
	)
	_select_dropdown_text(resolution_options, str(res_x) + " x " + str(res_y))


## Configures unified [ButtonGroup] and pressed visual styles for display and VSync buttons.
func _setup_button_groups() -> void:
	var display_btns: Array[Button] = [
		fullscreen_button,
		borderless_button,
		windowed_button,
	]
	_configure_toggle_group(display_btns)

	var vsync_btns: Array[Button] = [
		vsync_disabled_button,
		vsync_enabled_button,
		vsync_adaptive_button,
	]
	_configure_toggle_group(vsync_btns)


## Applies [ButtonGroup] and consistent pressed styleboxes to a row of buttons.
func _configure_toggle_group(buttons: Array[Button]) -> void:
	var group: ButtonGroup = ButtonGroup.new()
	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	pressed_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(3)

	for btn: Button in buttons:
		if not is_instance_valid(btn):
			continue
		btn.toggle_mode = true
		btn.button_group = group
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("hover_pressed", pressed_style)
		btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7, 1.0))


## Populates resolution, framerate cap, and monitor dropdown selectors.
func _populate_dropdowns() -> void:
	resolution_options.clear()
	for res_label: String in VideoConfig.RESOLUTIONS.keys():
		resolution_options.add_item(res_label)

	fps_options.clear()
	for fps_label: String in VideoConfig.FPS_LIMITS.keys():
		fps_options.add_item(fps_label)

	monitor_options.clear()
	var screen_count: int = maxi(DisplayServer.get_screen_count(), 1)
	for idx: int in range(screen_count):
		monitor_options.add_item("Monitor " + str(idx + 1))


## Connects UI widget signals using typed Callables.
func _connect_signals() -> void:
	fullscreen_button.pressed.connect(
		_on_display_mode_selected.bind(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	)
	borderless_button.pressed.connect(
		_on_display_mode_selected.bind(DisplayServer.WINDOW_MODE_FULLSCREEN)
	)
	windowed_button.pressed.connect(
		_on_display_mode_selected.bind(DisplayServer.WINDOW_MODE_WINDOWED)
	)

	vsync_disabled_button.pressed.connect(
		_on_vsync_mode_selected.bind(DisplayServer.VSYNC_DISABLED)
	)
	vsync_enabled_button.pressed.connect(_on_vsync_mode_selected.bind(DisplayServer.VSYNC_ENABLED))
	vsync_adaptive_button.pressed.connect(
		_on_vsync_mode_selected.bind(DisplayServer.VSYNC_ADAPTIVE)
	)

	monitor_options.item_selected.connect(_on_monitor_selected)
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)


## Updates display mode toggle button states without emitting signals.
func _update_display_mode_buttons(active_mode: int) -> void:
	fullscreen_button.set_pressed_no_signal(
		active_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	borderless_button.set_pressed_no_signal(active_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)
	windowed_button.set_pressed_no_signal(active_mode == DisplayServer.WINDOW_MODE_WINDOWED)


## Updates VSync toggle button states without emitting signals.
func _update_vsync_buttons(active_vsync: int, display_mode: int) -> void:
	var is_exclusive: bool = display_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	vsync_adaptive_button.disabled = not is_exclusive

	if not is_exclusive and active_vsync == DisplayServer.VSYNC_ADAPTIVE:
		active_vsync = DisplayServer.VSYNC_ENABLED
		GraphicsManager.set_setting("vsync_mode", active_vsync, false)

	vsync_disabled_button.set_pressed_no_signal(active_vsync == DisplayServer.VSYNC_DISABLED)
	vsync_enabled_button.set_pressed_no_signal(active_vsync == DisplayServer.VSYNC_ENABLED)
	vsync_adaptive_button.set_pressed_no_signal(active_vsync == DisplayServer.VSYNC_ADAPTIVE)


## Selects the dropdown entry matching [param fps_cap].
func _select_fps_option(fps_cap: int) -> void:
	for idx: int in range(fps_options.get_item_count()):
		var label: String = fps_options.get_item_text(idx)
		if VideoConfig.FPS_LIMITS.get(label, -1) == fps_cap:
			fps_options.select(idx)
			return


## Selects the dropdown item matching [param target_text].
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	for idx: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(idx) == target_text:
			dropdown.select(idx)
			return


## Handles display mode button selection and updates [GraphicsManager].
func _on_display_mode_selected(mode: int) -> void:
	print("DisplaySection: Player selected display mode -> ", mode)
	_update_display_mode_buttons(mode)
	var cur_vsync: int = GlobalSettings.get_setting_int(
		"Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC
	)
	_update_vsync_buttons(cur_vsync, mode)
	GraphicsManager.set_setting("display_mode", mode)
	display_settings_changed.emit()


## Handles VSync mode button selection and updates [GraphicsManager].
func _on_vsync_mode_selected(mode: int) -> void:
	print("DisplaySection: Player selected VSync mode -> ", mode)
	var cur_display: int = GlobalSettings.get_setting_int(
		"Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY
	)
	_update_vsync_buttons(mode, cur_display)
	GraphicsManager.set_setting("vsync_mode", mode)
	display_settings_changed.emit()


## Handles target monitor selection and updates [GraphicsManager].
func _on_monitor_selected(index: int) -> void:
	print("DisplaySection: Player selected monitor index -> ", index)
	GraphicsManager.set_setting("screen_index", index)
	display_settings_changed.emit()


## Handles screen resolution selection and updates [GraphicsManager].
func _on_resolution_selected(index: int) -> void:
	var label: String = resolution_options.get_item_text(index)
	var res: Vector2i = VideoConfig.RESOLUTIONS.get(label, Vector2i(1920, 1080))
	print("DisplaySection: Player selected resolution -> ", res)
	GraphicsManager.set_setting("resolution_x", res.x, false)
	GraphicsManager.set_setting("resolution_y", res.y, true)
	display_settings_changed.emit()


## Handles framerate limit selection and updates [GraphicsManager].
func _on_fps_selected(index: int) -> void:
	var label: String = fps_options.get_item_text(index)
	var limit: int = VideoConfig.FPS_LIMITS.get(label, VideoConfig.DEFAULT_FPS)
	print("DisplaySection: Player selected FPS cap -> ", limit)
	GraphicsManager.set_setting("fps_limit", limit)
	display_settings_changed.emit()
