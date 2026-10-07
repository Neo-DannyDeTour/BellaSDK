## Controls typography fonts, font scaling, UI scale factor, and field of view.
class_name AccessibilityDisplayUISection
extends GridContainer

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Base font sizes cached to prevent compounding scale factors.
const BASE_FONT_SIZES: Dictionary[String, int] = {
	"Button": 16,
	"CheckButton": 14,
	"Label": 16,
	"LineEdit": 14,
	"OptionButton": 14,
	"default": 16,
}

## Default constant value for camera base field of view.
const DEFAULT_FOV: float = 75.0

## Default constant value for dynamic sprint FOV expansion toggle.
const DEFAULT_DISABLE_SPRINT_FOV: bool = false

## Default constant value for user interface scale factor.
const DEFAULT_UI_SCALE: float = 1.0

## Default constant index for typography font mode.
const DEFAULT_FONT_MODE: int = 0

## Default constant value for typography font scaling multiplier.
const DEFAULT_FONT_SCALE: float = 1.0

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Slider for adjusting camera field of view.
@onready var fov_slider: HSlider = get_node_or_null("%FOVSlider")

## Text input for manual FOV entry.
@onready var fov_input: LineEdit = get_node_or_null("%FOVLine")

## Checkbox toggle for disabling sprint camera FOV adjustments.
@onready var sprint_fov_checkbox: CheckButton = get_node_or_null("%SprintFovCheckbox")

## Slider for adjusting UI scaling factor.
@onready var ui_scale_slider: HSlider = get_node_or_null("%UIScaleSlider")

## Text input for manual UI scaling factor entry.
@onready var ui_scale_input: LineEdit = get_node_or_null("%UIScaleLine")

## Dropdown menu for typography font mode override.
@onready var font_option: OptionButton = get_node_or_null("%FontOption")

## Slider for adjusting typography font scaling factor.
@onready var font_scale_slider: HSlider = get_node_or_null("%Font_ScaleSlider")

## Text input for manual typography font scaling factor entry.
@onready var font_scale_input: LineEdit = get_node_or_null("%Font_ScaleLine")


## Lifecycle initialization registering typography options and bindings.
func _ready() -> void:
	print("UI: Initializing Display & UI Section.")
	_populate_dropdowns()
	_connect_signals()


## Populates [OptionButton] items for typography fonts.
func _populate_dropdowns() -> void:
	print("UI: Populating font options dropdown.")
	if is_instance_valid(font_option):
		font_option.clear()
		for font_name: String in GlobalSettings.get_font_display_names():
			font_option.add_item(font_name)


## Connects UI input signals for display scaling and typography.
func _connect_signals() -> void:
	print("UI: Binding Display & UI input signals.")
	_connect_slider(
		fov_slider, fov_input, "base_fov", 60.0, 120.0, "Settings", true, _on_fov_adjusted
	)

	if is_instance_valid(sprint_fov_checkbox):
		sprint_fov_checkbox.toggled.connect(_on_sprint_fov_toggled)

	_connect_slider(
		ui_scale_slider, ui_scale_input, "ui_scale", 0.5, 2.5, "Settings", false, _apply_ui_scale
	)
	_connect_slider(
		font_scale_slider,
		font_scale_input,
		"font_scale",
		0.75,
		2.0,
		"Settings",
		false,
		_apply_font_scale_settings
	)

	if is_instance_valid(font_option):
		font_option.item_selected.connect(_on_font_selected)


## Reads display, UI, and FOV preferences from [GlobalSettings] silently.
func load_settings() -> void:
	print("UI: Loading Display and UI settings.")
	_load_slider(fov_slider, fov_input, "base_fov", DEFAULT_FOV, "Settings", true)
	if is_instance_valid(sprint_fov_checkbox):
		var raw_sprint: Variant = GlobalSettings.get_setting(
			"Settings", "disable_sprint_fov", DEFAULT_DISABLE_SPRINT_FOV
		)
		var disable_sprint: bool = bool(raw_sprint)
		sprint_fov_checkbox.set_pressed_no_signal(disable_sprint)
	apply_current_fov_to_preview()

	_load_slider(ui_scale_slider, ui_scale_input, "ui_scale", DEFAULT_UI_SCALE, "Settings")
	_load_slider(font_scale_slider, font_scale_input, "font_scale", DEFAULT_FONT_SCALE, "Settings")

	if is_instance_valid(font_option):
		var raw_font: Variant = GlobalSettings.get_setting(
			"Settings", "font_mode", DEFAULT_FONT_MODE
		)
		font_option.selected = int(raw_font)


## Connects companion slider and LineEdit pairs with throttled commit logic.
func _connect_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	is_int: bool,
	apply_cb: Callable
) -> void:
	if is_instance_valid(slider):
		slider.min_value = min_val
		slider.max_value = max_val
		slider.value_changed.connect(
			func(val: float) -> void:
				if is_instance_valid(input_box) and not input_box.has_focus():
					input_box.text = (str(int(val)) if is_int else ("%.2f" % val))
				if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					_commit_display_slider_val(key, val, section, apply_cb)
		)
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					print("Player adjusted ", key, " to: ", slider.value)
					_commit_display_slider_val(key, slider.value, section, apply_cb)
		)

	if is_instance_valid(input_box):
		input_box.focus_entered.connect(
			func() -> void:
				input_box.set_meta("pre_focus_text", input_box.text)
				input_box.text = ""
		)
		input_box.text_submitted.connect(
			func(_txt: String) -> void:
				_commit_display_line_edit(
					slider, input_box, key, min_val, max_val, section, is_int, apply_cb
				)
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				_commit_display_line_edit(
					slider, input_box, key, min_val, max_val, section, is_int, apply_cb
				)
		)


## Commits slider value and triggers callback if modified.
func _commit_display_slider_val(
	key: String, val: float, section: String, apply_cb: Callable
) -> void:
	var raw_val: Variant = GlobalSettings.get_setting(section, key, -999.0)
	var current: float = float(raw_val)
	if not is_equal_approx(current, val):
		GlobalSettings.save_setting(section, key, val)
		if apply_cb.is_valid():
			apply_cb.call(val)


## Commits LineEdit input to slider and storage safely.
func _commit_display_line_edit(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	is_int: bool,
	apply_cb: Callable
) -> void:
	var trimmed: String = input_box.text.strip_edges()
	var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		input_box.text = fallback
		return

	var clamped_val: float = clampf(trimmed.to_float(), min_val, max_val)
	var formatted: String = str(int(clamped_val)) if is_int else ("%.2f" % clamped_val)
	input_box.text = formatted
	input_box.set_meta("pre_focus_text", formatted)

	if is_instance_valid(slider):
		slider.set_value_no_signal(clamped_val)

	_commit_display_slider_val(key, clamped_val, section, apply_cb)


## Reads a float setting and synchronizes slider and LineEdit values.
func _load_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	default_val: float,
	section: String,
	is_int: bool = false
) -> void:
	if is_instance_valid(slider):
		var raw_val: Variant = GlobalSettings.get_setting(section, key, default_val)
		var val: float = float(raw_val)
		slider.set_value_no_signal(val)
		if is_instance_valid(input_box):
			input_box.text = str(int(val)) if is_int else ("%.2f" % val)


## Handles slider and typed FOV adjustments.
func _on_fov_adjusted(_val: float) -> void:
	_apply_fov_settings()


## Handles toggling of dynamic sprint FOV expansion.
func _on_sprint_fov_toggled(toggled_on: bool) -> void:
	var raw_sprint: Variant = GlobalSettings.get_setting(
		"Settings", "disable_sprint_fov", DEFAULT_DISABLE_SPRINT_FOV
	)
	var current: bool = bool(raw_sprint)
	if current == toggled_on:
		return

	print("Player toggled Sprint FOV to: ", toggled_on)
	GlobalSettings.save_setting("Settings", "disable_sprint_fov", toggled_on)
	_apply_fov_settings()


## Applies current base FOV and sprint toggle to player and preview cameras.
func _apply_fov_settings() -> void:
	if not is_instance_valid(fov_slider):
		return
	var current_fov: float = fov_slider.value
	print("Engine: Applying FOV settings -> ", current_fov)

	apply_current_fov_to_preview()

	var player: Node = get_tree().get_first_node_in_group(&"player")
	if is_instance_valid(player):
		var cam_ctrl: Object = (
			player.get("camera_controller") if player.get("camera_controller") is Object else null
		)
		if is_instance_valid(cam_ctrl):
			cam_ctrl.set("base_fov", current_fov)
			if is_instance_valid(sprint_fov_checkbox):
				cam_ctrl.set("disable_sprint_fov", sprint_fov_checkbox.button_pressed)


## Applies current slider FOV directly to the docked diorama camera.
func apply_current_fov_to_preview() -> void:
	if not is_instance_valid(fov_slider):
		return
	var socket: Control = get_node_or_null("%AccessibilityDioramaSocket")
	if not is_instance_valid(socket):
		return
	var cams: Array[Node] = socket.find_children("*", "Camera3D", true, false)
	for node: Node in cams:
		var cam: Camera3D = node if node is Camera3D else null
		if is_instance_valid(cam):
			cam.fov = fov_slider.value


## Adjusts window content scaling factor for user interface elements.
func _apply_ui_scale(scale_val: float) -> void:
	print("Engine: Applying UI Scale adjustments: ", scale_val)
	get_window().content_scale_factor = scale_val


## Handles font override selection changes from the dropdown menu.
func _on_font_selected(index: int) -> void:
	var raw_font: Variant = GlobalSettings.get_setting("Settings", "font_mode", DEFAULT_FONT_MODE)
	var current: int = int(raw_font)
	if current == index:
		return

	print("UI: Player selected font dropdown index: ", index)
	GlobalSettings.save_setting("Settings", "font_mode", index)
	_apply_font_settings()


## Broadcasts font override mode changes across the [Events] bus.
func _apply_font_settings() -> void:
	if not is_instance_valid(font_option):
		return
	var mode: int = font_option.selected
	var font_ids: Array[String] = GlobalSettings.get_font_ids()
	if mode < 0 or mode >= font_ids.size():
		push_warning("UI: Selected font index out of range: " + str(mode))
		return
	var target_font_id: String = font_ids[mode]
	print("UI: Broadcasting font change to: '", target_font_id, "'.")
	Events.font_changed.emit(target_font_id)


## Broadcasts typography font scale factor changes across the [Events] bus.
func _apply_font_scale_settings(scale_val: float) -> void:
	print("Engine: Applying Font Scale adjustments: ", scale_val)
	Events.font_scale_changed.emit(scale_val)


## Updates the font sizes across common [Control] types using active theme.
func apply_font_scale_to_theme(scale_factor: float) -> void:
	print("UI: Rescaling base theme font sizes with factor: ", scale_factor)
	var target_theme: Theme = theme
	if not is_instance_valid(target_theme):
		target_theme = ThemeDB.get_project_theme()
	if not is_instance_valid(target_theme):
		target_theme = ThemeDB.get_default_theme()
	if not is_instance_valid(target_theme):
		push_warning("UI: No valid Theme found to scale.")
		return

	var base_default: float = float(BASE_FONT_SIZES["default"])
	var def_size: int = int(round(base_default * scale_factor))
	target_theme.default_font_size = def_size

	for type_name: String in BASE_FONT_SIZES:
		if type_name == "default":
			continue
		var base_size: float = float(BASE_FONT_SIZES[type_name])
		var new_size: int = int(round(base_size * scale_factor))
		target_theme.set_font_size("font_size", type_name, new_size)
