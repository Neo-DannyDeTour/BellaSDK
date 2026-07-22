extends Panel
class_name AccessibilityPanel

const DEFAULT_BRIGHTNESS: float = 1.0
const DEFAULT_CONTRAST: float = 1.0
const DEFAULT_SATURATION: float = 1.0
const DEFAULT_FOV: float = 75.0
const DEFAULT_DISABLE_SPRINT_FOV: bool = false
const DEFAULT_UI_SCALE: float = 1.0
const DEFAULT_COLORBLIND_MODE: int = 0
const DEFAULT_FONT_MODE: int = 0

const DEFAULT_HIGH_CONTRAST: bool = false
const DEFAULT_REDUCE_MOTION: bool = false
const DEFAULT_SUB_SIZE: int = 1
const DEFAULT_SUB_BG_OPACITY: float = 0.5
const DEFAULT_SUB_COLORS: bool = true
const DEFAULT_FILM_GRAIN: float = 0.0

## Controls the overall brightness of the game world environment.
@onready var brightness_slider: HSlider = %BrightnessSlider
## Displays and accepts manual text input for the brightness value.
@onready var brightness_input: LineEdit = %BrightnessLine

## Controls the overall contrast of the game world environment.
@onready var contrast_slider: HSlider = %ContrastSlider
## Displays and accepts manual text input for the contrast value.
@onready var contrast_input: LineEdit = %ContrastLine

## Controls the overall color saturation of the game world environment.
@onready var saturation_slider: HSlider = %SaturationSlider
## Displays and accepts manual text input for the saturation value.
@onready var saturation_input: LineEdit = %SaturationLine

## Controls the base Field of View for the player's camera.
@onready var fov_slider: HSlider = %FOVSlider
## Displays and accepts manual text input for the FOV value.
@onready var fov_input: LineEdit = %FOVLine
## Toggles whether FOV changes dynamically when the player sprints.
@onready var sprint_fov_checkbox: CheckBox = %SprintFovCheckbox

## Controls the scale factor of the user interface elements.
@onready var ui_scale_slider: HSlider = %UIScaleSlider
## Displays and accepts manual text input for the UI scale factor.
@onready var ui_scale_input: LineEdit = %UIScaleLine

## Dropdown menu for selecting various colorblind filters.
@onready var colorblind_option: OptionButton = %ColorblindOption
## Dropdown menu for overriding the global game font (e.g., Dyslexic font).
@onready var font_option: OptionButton = %FontOption

# --- NEW ACCESSIBILITY VARIABLES ---

## Toggles a stark, high-contrast background behind text elements to improve reading visibility.
@onready var high_contrast_toggle: CheckButton = %HighContrastToggle
## Toggles the reduction of screen shake and motion blur to assist players with motion sickness.
@onready var reduce_motion_toggle: CheckButton = %ReduceMotionToggle
## Dropdown menu for selecting the size of subtitle text (Small, Medium, Large).
@onready var sub_size_option: OptionButton = %SubSizeOption
## Slider to control how opaque the black background behind subtitles is.
@onready var sub_bg_opacity_slider: HSlider = %SubBgOpacitySlider
## Toggles whether different character names are rendered in distinct colors in subtitles.
@onready var sub_colors_toggle: CheckButton = %SubColorsToggle
## Slider to adjust the visual intensity of the film grain post-processing effect.
@onready var film_grain_slider: HSlider = %FilmGrainSlider


func _ready() -> void:
	print("UI: Accessibility Panel initialized.")
	_populate_dropdowns()
	_connect_signals()
	_load_accessibility_settings()


func _connect_signals() -> void:
	print("UI: Connecting accessibility signals.")
	_connect_adjustment_signals(brightness_slider, brightness_input, "brightness")
	_connect_adjustment_signals(contrast_slider, contrast_input, "contrast")
	_connect_adjustment_signals(saturation_slider, saturation_input, "saturation")
	_connect_adjustment_signals(ui_scale_slider, ui_scale_input, "ui_scale")

	if fov_slider and fov_input:
		fov_slider.value_changed.connect(_on_fov_changed)
		fov_slider.drag_ended.connect(_on_fov_drag_ended)
		fov_input.text_submitted.connect(_on_fov_input_submitted)
		fov_input.focus_entered.connect(_on_fov_focus_entered)
		fov_input.focus_exited.connect(_on_fov_focus_exited)

	if sprint_fov_checkbox:
		sprint_fov_checkbox.toggled.connect(_on_sprint_fov_toggled)

	if colorblind_option:
		colorblind_option.item_selected.connect(_on_colorblind_selected)
	if font_option:
		font_option.item_selected.connect(_on_font_selected)

	# New signal connections
	if high_contrast_toggle:
		high_contrast_toggle.toggled.connect(_on_high_contrast_toggled)
	if reduce_motion_toggle:
		reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)
	if sub_size_option:
		sub_size_option.item_selected.connect(_on_sub_size_selected)
	if sub_colors_toggle:
		sub_colors_toggle.toggled.connect(_on_sub_colors_toggled)

	_connect_adjustment_signals(sub_bg_opacity_slider, null, "subtitle_bg_opacity")
	_connect_adjustment_signals(film_grain_slider, null, "film_grain_intensity")


func _load_accessibility_settings() -> void:
	print("UI: Loading accessibility data from GlobalSettings.")

	_load_slider_setting(brightness_slider, brightness_input, "brightness", DEFAULT_BRIGHTNESS)
	_load_slider_setting(contrast_slider, contrast_input, "contrast", DEFAULT_CONTRAST)
	_load_slider_setting(saturation_slider, saturation_input, "saturation", DEFAULT_SATURATION)
	_apply_visual_settings()

	_load_slider_setting(fov_slider, fov_input, "base_fov", DEFAULT_FOV, true)
	if sprint_fov_checkbox:
		sprint_fov_checkbox.button_pressed = (
			GlobalSettings.get_setting("Settings", "disable_sprint_fov", DEFAULT_DISABLE_SPRINT_FOV)
			as bool
		)
	_apply_fov_settings()

	_load_slider_setting(ui_scale_slider, ui_scale_input, "ui_scale", DEFAULT_UI_SCALE)
	_apply_ui_scale_settings()

	if colorblind_option:
		colorblind_option.selected = (
			GlobalSettings.get_setting("Settings", "colorblind_mode", DEFAULT_COLORBLIND_MODE)
			as int
		)
		_apply_colorblind_settings()

	if font_option:
		font_option.selected = (
			GlobalSettings.get_setting("Settings", "font_mode", DEFAULT_FONT_MODE) as int
		)
		_apply_font_settings()

	# Load new settings
	if high_contrast_toggle:
		high_contrast_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting(
					"Accessibility", "high_contrast_ui", DEFAULT_HIGH_CONTRAST
				)
				as bool
			)
		)
	if reduce_motion_toggle:
		reduce_motion_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting("Accessibility", "reduce_motion", DEFAULT_REDUCE_MOTION)
				as bool
			)
		)
	if sub_size_option:
		sub_size_option.selected = (
			GlobalSettings.get_setting("Accessibility", "subtitle_size", DEFAULT_SUB_SIZE) as int
		)
	if sub_colors_toggle:
		sub_colors_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting("Accessibility", "subtitle_colors", DEFAULT_SUB_COLORS)
				as bool
			)
		)

	_load_slider_setting(sub_bg_opacity_slider, null, "subtitle_bg_opacity", DEFAULT_SUB_BG_OPACITY)
	_load_slider_setting(film_grain_slider, null, "film_grain_intensity", DEFAULT_FILM_GRAIN)


func _load_slider_setting(
	slider: HSlider, input_box: LineEdit, key: String, default_val: float, is_int: bool = false
) -> void:
	if slider:
		var val: float = GlobalSettings.get_setting("Settings", key, default_val) as float
		slider.value = val
		if input_box:
			input_box.text = str(int(val)) if is_int else ("%.2f" % val)


func _connect_adjustment_signals(
	slider: HSlider, input_box: LineEdit, setting_name: String
) -> void:
	if slider:
		slider.value_changed.connect(_on_adjustment_changed.bind(input_box, setting_name))
		slider.drag_ended.connect(_on_adjustment_drag_ended.bind(setting_name, slider))
	if input_box:
		input_box.text_submitted.connect(_on_adjustment_input_submitted.bind(setting_name, slider))
		input_box.focus_entered.connect(_on_adjustment_focus_entered.bind(input_box))
		input_box.focus_exited.connect(
			_on_adjustment_focus_exited.bind(input_box, slider, setting_name)
		)


func _on_adjustment_changed(value: float, input_node: LineEdit, setting_name: String) -> void:
	print("UI: Adjustment changed for ", setting_name, " to ", value)
	if input_node and not input_node.has_focus():
		input_node.text = "%.2f" % value

	if setting_name == "ui_scale":
		_apply_ui_scale_settings()
	elif setting_name == "subtitle_bg_opacity" or setting_name == "film_grain_intensity":
		pass  # Handle real-time updates for these specific shaders/UI elements here if needed
	else:
		_apply_visual_settings()


func _on_adjustment_drag_ended(
	value_changed: bool, setting_name: String, slider_node: HSlider
) -> void:
	if value_changed:
		print("Player adjusted ", setting_name, " slider to: ", slider_node.value)
		GlobalSettings.save_setting("Settings", setting_name, slider_node.value)


func _on_adjustment_input_submitted(
	new_text: String, setting_name: String, slider_node: HSlider
) -> void:
	var new_val: float = clamp(new_text.to_float(), 0.0, 3.0)
	slider_node.value = new_val
	slider_node.release_focus()
	print("Player manually typed ", setting_name, " input: ", new_val)
	GlobalSettings.save_setting("Settings", setting_name, new_val)


func _on_adjustment_focus_entered(input_node: LineEdit) -> void:
	print("UI: Player editing LineEdit input.")
	input_node.text = ""


func _on_adjustment_focus_exited(
	input_node: LineEdit, slider_node: HSlider, setting_name: String
) -> void:
	var current_text: String = input_node.text.strip_edges()
	if current_text == "":
		input_node.text = "%.2f" % slider_node.value
	else:
		_on_adjustment_input_submitted(current_text, setting_name, slider_node)


func _apply_visual_settings() -> void:
	print("Engine: Applying visual adjustments to WorldEnvironment.")
	var env_nodes: Array[Node] = get_tree().get_nodes_in_group("world_environment")

	if not env_nodes.is_empty():
		var env_node: WorldEnvironment = env_nodes[0] as WorldEnvironment
		if env_node and env_node.environment:
			env_node.environment.adjustment_enabled = true
			env_node.environment.adjustment_brightness = brightness_slider.value
			env_node.environment.adjustment_contrast = contrast_slider.value
			env_node.environment.adjustment_saturation = saturation_slider.value


func _apply_ui_scale_settings() -> void:
	var current_scale: float = ui_scale_slider.value
	print("Engine: Applying UI Scale adjustments: ", current_scale)
	get_window().content_scale_factor = current_scale


func _on_colorblind_selected(index: int) -> void:
	print("Player changed colorblind mode to index: ", index)
	GlobalSettings.save_setting("Settings", "colorblind_mode", index)
	_apply_colorblind_settings()


func _apply_colorblind_settings() -> void:
	var mode: int = colorblind_option.selected
	print("Engine: Applying Colorblind shader mode: ", mode)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("colorblind_mode_changed"):
			events.emit_signal("colorblind_mode_changed", mode)


func _on_font_selected(index: int) -> void:
	print("Player changed font mode to index: ", index)
	GlobalSettings.save_setting("Settings", "font_mode", index)
	_apply_font_settings()


func _apply_font_settings() -> void:
	var mode: int = font_option.selected
	print("Engine: Applying Font Override mode: ", mode)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("font_changed"):
			var font_strings: Array[String] = ["default", "dyslexic", "papyrus", "comic"]
			if mode >= 0 and mode < font_strings.size():
				events.emit_signal("font_changed", font_strings[mode])


func _on_fov_changed(value: float) -> void:
	print("UI: FOV adjusted to ", value)
	if fov_input and not fov_input.has_focus():
		fov_input.text = str(int(value))
	_apply_fov_settings()


func _on_fov_drag_ended(value_changed: bool) -> void:
	if value_changed:
		print("Player adjusted FOV slider to: ", fov_slider.value)
		GlobalSettings.save_setting("Settings", "base_fov", fov_slider.value)


func _on_fov_input_submitted(new_text: String) -> void:
	var new_val: float = clamp(new_text.to_float(), 60.0, 120.0)
	fov_slider.value = new_val
	fov_input.release_focus()
	print("Player manually typed FOV input: ", new_val)
	GlobalSettings.save_setting("Settings", "base_fov", new_val)


func _on_fov_focus_entered() -> void:
	print("UI: Player editing FOV LineEdit.")
	fov_input.text = ""


func _on_fov_focus_exited() -> void:
	var current_text: String = fov_input.text.strip_edges()
	if current_text == "":
		fov_input.text = str(int(fov_slider.value))
	else:
		_on_fov_input_submitted(current_text)


func _on_sprint_fov_toggled(toggled_on: bool) -> void:
	print("Player toggled Sprint FOV to: ", toggled_on)
	GlobalSettings.save_setting("Settings", "disable_sprint_fov", toggled_on)
	_apply_fov_settings()


func _apply_fov_settings() -> void:
	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		print("Engine: Applying FOV settings to Player Camera.")
		player.camera_controller.base_fov = fov_slider.value
		player.camera_controller.disable_sprint_fov = sprint_fov_checkbox.button_pressed


# --- NEW ACCESSIBILITY TOGGLE CALLBACKS ---


func _on_high_contrast_toggled(toggled_on: bool) -> void:
	print("Player toggled High Contrast UI to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "high_contrast_ui", toggled_on)
	if has_node("/root/Events") and get_node("/root/Events").has_signal("high_contrast_changed"):
		get_node("/root/Events").emit_signal("high_contrast_changed", toggled_on)


func _on_reduce_motion_toggled(toggled_on: bool) -> void:
	print("Player toggled Reduce Motion to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "reduce_motion", toggled_on)
	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.reduce_motion = toggled_on


func _on_sub_size_selected(index: int) -> void:
	print("Player selected Subtitle Size index: ", index)
	GlobalSettings.save_setting("Accessibility", "subtitle_size", index)
	if has_node("/root/Events") and get_node("/root/Events").has_signal("subtitle_size_changed"):
		get_node("/root/Events").emit_signal("subtitle_size_changed", index)


func _on_sub_colors_toggled(toggled_on: bool) -> void:
	print("Player toggled Subtitle Speaker Colors to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "subtitle_colors", toggled_on)
	if has_node("/root/Events") and get_node("/root/Events").has_signal("subtitle_colors_changed"):
		get_node("/root/Events").emit_signal("subtitle_colors_changed", toggled_on)


func _get_player() -> Node:
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node:
		return player_node
	return null


func _populate_dropdowns() -> void:
	print("UI: Populating OptionButton dropdowns with available modes.")

	if colorblind_option:
		colorblind_option.clear()
		var colorblind_modes: Array[String] = [
			"Normal", "Protanopia", "Deuteranopia", "Tritanopia", "Achromatopsia"
		]
		for mode: String in colorblind_modes:
			colorblind_option.add_item(mode)

	if font_option:
		font_option.clear()
		var font_modes: Array[String] = ["Default", "Dyslexic", "Papyrus", "Comic"]
		for font: String in font_modes:
			font_option.add_item(font)

	if sub_size_option:
		sub_size_option.clear()
		var size_modes: Array[String] = ["Small", "Medium", "Large"]
		for size_mode: String in size_modes:
			sub_size_option.add_item(size_mode)
