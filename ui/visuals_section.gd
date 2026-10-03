## Controls post-processing, screen filters, brightness, contrast, and colorblind modes.
class_name AccessibilityVisualsSection
extends VBoxContainer

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Default constant value for world environment brightness.
const DEFAULT_BRIGHTNESS: float = 1.0

## Default constant value for world environment contrast.
const DEFAULT_CONTRAST: float = 1.0

## Default constant value for world environment saturation.
const DEFAULT_SATURATION: float = 1.0

## Default constant index for active colorblind shader correction filter.
const DEFAULT_COLORBLIND_MODE: int = 0

## Default constant value for high contrast UI mode.
const DEFAULT_HIGH_CONTRAST: bool = false

## Default constant value for post-process film grain effect intensity.
const DEFAULT_FILM_GRAIN: float = 0.0

## Default constant value for photosensitivity safe mode.
const DEFAULT_PHOTOSENSITIVITY: bool = false

## Default constant index for screen filters.
const DEFAULT_SCREEN_FILTER: int = 0

## Default constant value for world environment gamma.
const DEFAULT_GAMMA: float = 1.0

## Default constant index for interactable outline highlight visibility mode.
const DEFAULT_OUTLINE_MODE: int = 2

## Available palette color names for target outline highlights.
const OUTLINE_COLOR_NAMES: Array[String] = [
	"Green", "Cyan", "Yellow", "Orange", "Red", "Magenta", "White"
]

## Color values corresponding to outline palette selection names.
const OUTLINE_COLOR_VALUES: Array[Color] = [
	Color(0.0, 1.0, 0.5, 1.0),
	Color(0.0, 0.8, 1.0, 1.0),
	Color(1.0, 0.9, 0.1, 1.0),
	Color(1.0, 0.5, 0.0, 1.0),
	Color(1.0, 0.2, 0.2, 1.0),
	Color(1.0, 0.1, 0.8, 1.0),
	Color(1.0, 1.0, 1.0, 1.0)
]

## Default constant index for outline highlight color.
const DEFAULT_OUTLINE_COLOR_INDEX: int = 0

## Default constant value for outline blink speed oscillation.
const DEFAULT_OUTLINE_BLINK_SPEED: float = 8.0

## Default constant value for outline minimum pulse intensity.
const DEFAULT_OUTLINE_MIN_INTENSITY: float = 0.2

## Default constant value for outline maximum pulse intensity.
const DEFAULT_OUTLINE_MAX_INTENSITY: float = 1.0

## Color modulation applied to the active outline mode button.
const ACTIVE_BUTTON_COLOR: Color = Color(0.25, 0.75, 1.0, 1.0)

## Color modulation applied to inactive outline mode buttons.
const INACTIVE_BUTTON_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Dropdown menu for selecting colorblind shader correction filters.
@onready var colorblind_option: OptionButton = get_node_or_null("%ColorblindOption")

## Dropdown menu for selecting post-process screen filters.
@onready var screen_filter_option: OptionButton = get_node_or_null("%ScreenFilterOption")

## Slider for adjusting world brightness.
@onready var brightness_slider: HSlider = get_node_or_null("%BrightnessSlider")

## Text input for manual brightness entry.
@onready var brightness_input: LineEdit = get_node_or_null("%BrightnessLine")

## Slider for adjusting world contrast.
@onready var contrast_slider: HSlider = get_node_or_null("%ContrastSlider")

## Text input for manual contrast entry.
@onready var contrast_input: LineEdit = get_node_or_null("%ContrastLine")

## Slider for adjusting world color saturation.
@onready var saturation_slider: HSlider = get_node_or_null("%SaturationSlider")

## Text input for manual saturation entry.
@onready var saturation_input: LineEdit = get_node_or_null("%SaturationLine")

## Slider for adjusting film grain intensity.
@onready var film_grain_slider: HSlider = get_node_or_null("%FilmGrainSlider")

## Text input for manual film grain intensity entry.
@onready var film_grain_input: LineEdit = get_node_or_null("%FilmGrainEdit")

## Toggle switch for photosensitivity safety mode.
@onready var photosensitivity_toggle: CheckButton = get_node_or_null("%PhotosensitivityToggle")

## Slider for adjusting world gamma.
@onready var gamma_slider: HSlider = get_node_or_null("%GammaSlider")

## Text input for manual gamma entry.
@onready var gamma_input: LineEdit = get_node_or_null("%GammaLine")

## Toggle switch for high-contrast UI mode.
@onready var high_contrast_toggle: CheckButton = get_node_or_null("%HighContrastToggle")

## Button switching interactable outline highlight to off.
@onready var outline_off_button: Button = get_node_or_null("%OutlineOffButton")

## Button switching interactable outline highlight to always visible.
@onready var outline_always_button: Button = get_node_or_null("%OutlineAlwaysButton")

## Button switching interactable outline highlight to focus-only visibility.
@onready var outline_focus_button: Button = get_node_or_null("%OutlineFocusButton")

## Dropdown menu for selecting outline highlight color.
@onready var outline_color_option: OptionButton = get_node_or_null("%OutlineColorOption")

## Slider for adjusting outline blink pulse speed.
@onready var outline_blink_slider: HSlider = get_node_or_null("%OutlineBlinkSpeedSlider")

## Text input for manual outline blink pulse speed entry.
@onready var outline_blink_input: LineEdit = get_node_or_null("%OutlineBlinkSpeedLine")

## Slider for adjusting outline minimum pulse intensity.
@onready var outline_min_slider: HSlider = get_node_or_null("%OutlineMinIntensitySlider")

## Text input for manual outline minimum pulse intensity entry.
@onready var outline_min_input: LineEdit = get_node_or_null("%OutlineMinIntensityLine")

## Slider for adjusting outline maximum pulse intensity.
@onready var outline_max_slider: HSlider = get_node_or_null("%OutlineMaxIntensitySlider")

## Text input for manual outline maximum pulse intensity entry.
@onready var outline_max_input: LineEdit = get_node_or_null("%OutlineMaxIntensityLine")

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Cached [Curve] resource for gamma adjustments.
var _gamma_curve: Curve = Curve.new()

## Cached [CurveTexture] resource for tonemap color correction.
var _gamma_texture: CurveTexture = CurveTexture.new()


## Lifecycle initialization configuring options and slider listeners.
func _ready() -> void:
	print("UI: Initializing Visuals Section.")
	_gamma_texture.curve = _gamma_curve
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Populates [OptionButton] items for filters, colorblind, and outlines.
func _populate_dropdowns() -> void:
	print("UI: Populating visuals dropdown options.")
	if is_instance_valid(screen_filter_option):
		screen_filter_option.clear()
		for filter_name: String in GlobalSettings.get_screen_filter_display_names():
			screen_filter_option.add_item(filter_name)

	if is_instance_valid(colorblind_option):
		colorblind_option.clear()
		var colorblind_modes: Array[String] = [
			"Normal", "Protanopia", "Deuteranopia", "Tritanopia", "Achromatopsia"
		]
		for mode: String in colorblind_modes:
			colorblind_option.add_item(mode)

	if is_instance_valid(outline_color_option):
		outline_color_option.clear()
		for col_name: String in OUTLINE_COLOR_NAMES:
			outline_color_option.add_item(col_name)


## Connects interactive controls and slider value adjustments.
func _connect_signals() -> void:
	print("UI: Binding visual slider and toggle signals.")
	if is_instance_valid(colorblind_option):
		colorblind_option.item_selected.connect(_on_colorblind_selected)
	if is_instance_valid(screen_filter_option):
		screen_filter_option.item_selected.connect(_on_screen_filter_selected)

	_connect_slider(brightness_slider, brightness_input, "brightness", 0.0, 3.0, "Settings", false)
	_connect_slider(contrast_slider, contrast_input, "contrast", 0.0, 3.0, "Settings", false)
	_connect_slider(saturation_slider, saturation_input, "saturation", 0.0, 3.0, "Settings", false)
	_connect_slider(gamma_slider, gamma_input, "gamma", 0.0, 3.0, "Settings", false)
	_connect_slider(
		film_grain_slider,
		film_grain_input,
		"film_grain_intensity",
		0.0,
		20.0,
		"Settings",
		false,
		_apply_film_grain
	)

	if is_instance_valid(photosensitivity_toggle):
		photosensitivity_toggle.toggled.connect(_on_photosensitivity_toggled)
	if is_instance_valid(high_contrast_toggle):
		high_contrast_toggle.toggled.connect(_on_high_contrast_toggled)

	_connect_outline_controls()


## Connects input signals for outline highlight mode buttons.
func _connect_outline_controls() -> void:
	print("UI: Binding outline controls.")
	if is_instance_valid(outline_off_button):
		outline_off_button.pressed.connect(func() -> void: _on_outline_mode_selected(0))
	if is_instance_valid(outline_always_button):
		outline_always_button.pressed.connect(func() -> void: _on_outline_mode_selected(1))
	if is_instance_valid(outline_focus_button):
		outline_focus_button.pressed.connect(func() -> void: _on_outline_mode_selected(2))

	if is_instance_valid(outline_color_option):
		outline_color_option.item_selected.connect(_on_outline_color_selected)

	_connect_slider(
		outline_blink_slider,
		outline_blink_input,
		"outline_blink_speed",
		0.0,
		20.0,
		"Accessibility",
		false,
		_apply_outline_blink_speed
	)
	_connect_slider(
		outline_min_slider,
		outline_min_input,
		"outline_min_intensity",
		0.0,
		1.0,
		"Accessibility",
		false,
		_apply_outline_min_intensity
	)
	_connect_slider(
		outline_max_slider,
		outline_max_input,
		"outline_max_intensity",
		0.0,
		5.0,
		"Accessibility",
		false,
		_apply_outline_max_intensity
	)


## Reads stored visual options from [GlobalSettings] into UI without bus flood.
func load_settings() -> void:
	print("UI: Loading Visuals settings.")
	if is_instance_valid(colorblind_option):
		colorblind_option.selected = int(
			GlobalSettings.get_setting("Settings", "colorblind_mode", DEFAULT_COLORBLIND_MODE)
		)

	if is_instance_valid(screen_filter_option):
		screen_filter_option.selected = int(
			GlobalSettings.get_setting("Settings", "screen_filter", DEFAULT_SCREEN_FILTER)
		)

	_load_slider(brightness_slider, brightness_input, "brightness", DEFAULT_BRIGHTNESS)
	_load_slider(contrast_slider, contrast_input, "contrast", DEFAULT_CONTRAST)
	_load_slider(saturation_slider, saturation_input, "saturation", DEFAULT_SATURATION)
	_load_slider(gamma_slider, gamma_input, "gamma", DEFAULT_GAMMA)
	_load_slider(film_grain_slider, film_grain_input, "film_grain_intensity", DEFAULT_FILM_GRAIN)

	_apply_visual_settings()

	if is_instance_valid(photosensitivity_toggle):
		photosensitivity_toggle.set_pressed_no_signal(
			bool(
				GlobalSettings.get_setting(
					"Accessibility", "photosensitivity", DEFAULT_PHOTOSENSITIVITY
				)
			)
		)

	if is_instance_valid(high_contrast_toggle):
		high_contrast_toggle.set_pressed_no_signal(
			bool(
				GlobalSettings.get_setting(
					"Accessibility", "high_contrast_ui", DEFAULT_HIGH_CONTRAST
				)
			)
		)

	_load_outline_settings()


## Loads outline highlight preferences into UI silently.
func _load_outline_settings() -> void:
	print("UI: Loading Outline Highlight settings.")
	var outline_mode: int = int(
		GlobalSettings.get_setting("Accessibility", "outline_mode", DEFAULT_OUTLINE_MODE)
	)
	_update_outline_buttons_ui(outline_mode)

	if is_instance_valid(outline_color_option):
		var col_idx: int = int(
			GlobalSettings.get_setting(
				"Accessibility", "outline_color_index", DEFAULT_OUTLINE_COLOR_INDEX
			)
		)
		outline_color_option.selected = col_idx

	_load_slider_custom(
		outline_blink_slider,
		outline_blink_input,
		"outline_blink_speed",
		DEFAULT_OUTLINE_BLINK_SPEED,
		"Accessibility"
	)
	_load_slider_custom(
		outline_min_slider,
		outline_min_input,
		"outline_min_intensity",
		DEFAULT_OUTLINE_MIN_INTENSITY,
		"Accessibility"
	)
	_load_slider_custom(
		outline_max_slider,
		outline_max_input,
		"outline_max_intensity",
		DEFAULT_OUTLINE_MAX_INTENSITY,
		"Accessibility"
	)


## Handles selection of an outline highlight mode by index.
func _on_outline_mode_selected(mode: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting("Accessibility", "outline_mode", DEFAULT_OUTLINE_MODE)
	)
	if current == mode:
		return

	print("Player selected Outline Mode: ", mode)
	GlobalSettings.save_setting("Accessibility", "outline_mode", mode)
	_update_outline_buttons_ui(mode)
	_apply_outline_mode(mode)


## Updates button states and active colors according to selected mode.
func _update_outline_buttons_ui(selected_mode: int) -> void:
	print("UI: Updating Outline Mode buttons display to: ", selected_mode)
	var buttons: Array[Button] = [outline_off_button, outline_always_button, outline_focus_button]
	for i: int in range(buttons.size()):
		var btn: Button = buttons[i]
		if not is_instance_valid(btn):
			continue
		var is_active: bool = i == selected_mode
		btn.button_pressed = is_active
		btn.self_modulate = ACTIVE_BUTTON_COLOR if is_active else INACTIVE_BUTTON_COLOR


## Broadcasts outline mode changes across global [Events] singleton.
func _apply_outline_mode(mode: int) -> void:
	print("Engine: Applying Outline Mode: ", mode)
	Events.outline_mode_changed.emit(mode)


## Handles outline color selection from dropdown menu.
func _on_outline_color_selected(index: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting(
			"Accessibility", "outline_color_index", DEFAULT_OUTLINE_COLOR_INDEX
		)
	)
	if current == index:
		return

	print("Player selected Outline Color index: ", index)
	GlobalSettings.save_setting("Accessibility", "outline_color_index", index)
	_apply_outline_color(index)


## Broadcasts target outline color changes across [Events].
func _apply_outline_color(index: int) -> void:
	if index < 0 or index >= OUTLINE_COLOR_VALUES.size():
		return
	var chosen_color: Color = OUTLINE_COLOR_VALUES[index]
	print("Engine: Applying Outline Color: ", chosen_color)
	Events.outline_color_changed.emit(chosen_color)


## Broadcasts target outline blink speed changes across [Events].
func _apply_outline_blink_speed(val: float) -> void:
	print("Engine: Applying Outline Blink Speed: ", val)
	Events.outline_blink_speed_changed.emit(val)


## Broadcasts target outline minimum intensity changes across [Events].
func _apply_outline_min_intensity(val: float) -> void:
	print("Engine: Applying Outline Min Intensity: ", val)
	Events.outline_min_intensity_changed.emit(val)


## Broadcasts target outline maximum intensity changes across [Events].
func _apply_outline_max_intensity(val: float) -> void:
	print("Engine: Applying Outline Max Intensity: ", val)
	Events.outline_max_intensity_changed.emit(val)


## Connects companion slider and LineEdit pairs with throttled commit logic.
func _connect_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String = "Settings",
	is_int: bool = false,
	custom_cb: Callable = Callable()
) -> void:
	print("UI: Binding slider for key: ", key)
	if is_instance_valid(slider):
		slider.min_value = min_val
		slider.max_value = max_val
		slider.value_changed.connect(
			func(val: float) -> void:
				if is_instance_valid(input_box) and not input_box.has_focus():
					input_box.text = str(int(val)) if is_int else ("%.2f" % val)
				if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					_commit_visual_slider_val(key, val, section, custom_cb)
		)
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					print("Player adjusted ", key, " to: ", slider.value)
					_commit_visual_slider_val(key, slider.value, section, custom_cb)
		)

	if is_instance_valid(input_box):
		input_box.focus_entered.connect(
			func() -> void:
				input_box.set_meta("pre_focus_text", input_box.text)
				input_box.text = ""
		)
		input_box.text_submitted.connect(
			func(_txt: String) -> void:
				_commit_visual_line_edit(
					slider, input_box, key, min_val, max_val, section, is_int, custom_cb
				)
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				_commit_visual_line_edit(
					slider, input_box, key, min_val, max_val, section, is_int, custom_cb
				)
		)


## Commits slider value to storage and triggers callback if changed.
func _commit_visual_slider_val(
	key: String, val: float, section: String, custom_cb: Callable
) -> void:
	var current: float = float(GlobalSettings.get_setting(section, key, -999.0))
	if not is_equal_approx(current, val):
		GlobalSettings.save_setting(section, key, val)
		if custom_cb.is_valid():
			custom_cb.call(val)
		else:
			_apply_visual_settings()


## Commits LineEdit input to visual slider and storage safely.
func _commit_visual_line_edit(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	is_int: bool,
	custom_cb: Callable
) -> void:
	var trimmed: String = input_box.text.strip_edges()
	var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		input_box.text = fallback
		return

	var new_val: float = clampf(trimmed.to_float(), min_val, max_val)
	var formatted: String = str(int(new_val)) if is_int else ("%.2f" % new_val)
	input_box.text = formatted
	input_box.set_meta("pre_focus_text", formatted)

	if is_instance_valid(slider):
		slider.set_value_no_signal(new_val)

	_commit_visual_slider_val(key, new_val, section, custom_cb)


## Reads a float setting and synchronizes slider and text box.
func _load_slider(slider: HSlider, input_box: LineEdit, key: String, default_val: float) -> void:
	_load_slider_custom(slider, input_box, key, default_val, "Settings")


## Reads a float setting from a specific section and synchronizes slider and text box.
func _load_slider_custom(
	slider: HSlider, input_box: LineEdit, key: String, default_val: float, section: String
) -> void:
	if is_instance_valid(slider):
		var val: float = float(GlobalSettings.get_setting(section, key, default_val))
		slider.set_value_no_signal(val)
		if is_instance_valid(input_box):
			input_box.text = "%.2f" % val


## Handles user selection of colorblind dropdown options.
func _on_colorblind_selected(index: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting("Settings", "colorblind_mode", DEFAULT_COLORBLIND_MODE)
	)
	if current == index:
		return

	print("Player changed colorblind mode to index: ", index)
	GlobalSettings.save_setting("Settings", "colorblind_mode", index)
	_apply_colorblind_settings()


## Broadcasts selected colorblind mode to global [Events] singleton.
func _apply_colorblind_settings() -> void:
	if not is_instance_valid(colorblind_option):
		return
	var mode: int = colorblind_option.selected
	print("Engine: Applying Colorblind shader mode: ", mode)
	Events.colorblind_mode_changed.emit(mode)


## Handles screen filter dropdown selections.
func _on_screen_filter_selected(index: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting("Settings", "screen_filter", DEFAULT_SCREEN_FILTER)
	)
	if current == index:
		return

	print("UI: Screen filter selected index: ", index)
	GlobalSettings.save_setting("Settings", "screen_filter", index)
	_apply_screen_filter(index)


## Applies selected screen filter without persisting it again.
func _apply_screen_filter(index: int) -> void:
	var filter_ids: Array[String] = GlobalSettings.get_screen_filter_ids()
	if index < 0 or index >= filter_ids.size():
		return
	var filter_name: String = filter_ids[index]
	print("Player selected Screen Filter: ", filter_name)
	Events.screen_filter_changed.emit(filter_name)


## Broadcasts film grain intensity value updates across [Events].
func _apply_film_grain(val: float) -> void:
	print("UI: Applying film grain intensity: ", val)
	Events.film_grain_changed.emit(val)


## Handles photosensitivity safe mode toggling.
func _on_photosensitivity_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "photosensitivity", DEFAULT_PHOTOSENSITIVITY)
	)
	if current == toggled_on:
		return

	print("Player toggled Photosensitivity Mode to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "photosensitivity", toggled_on)
	Events.photosensitivity_mode_toggled.emit(toggled_on)


## Handles high contrast mode toggling.
func _on_high_contrast_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "high_contrast_ui", DEFAULT_HIGH_CONTRAST)
	)
	if current == toggled_on:
		return

	print("Player toggled High Contrast UI to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "high_contrast_ui", toggled_on)
	Events.high_contrast_toggled.emit(toggled_on)


## Applies adjustments to the active [WorldEnvironment].
func _apply_visual_settings() -> void:
	if not brightness_slider or not contrast_slider or not saturation_slider or not gamma_slider:
		return
	print("Engine: Applying visual adjustments to WorldEnvironment.")
	var env_node: WorldEnvironment = _find_world_environment()
	if env_node and env_node.environment:
		env_node.environment.adjustment_enabled = true
		env_node.environment.adjustment_brightness = brightness_slider.value
		env_node.environment.adjustment_contrast = contrast_slider.value
		env_node.environment.adjustment_saturation = saturation_slider.value
		_apply_gamma_to_environment(gamma_slider.value, env_node.environment)


## Updates [Environment] adjustment color correction gradient via power curve.
func _apply_gamma_to_environment(gamma_val: float, env: Environment) -> void:
	if not is_instance_valid(env):
		return
	print("Engine: Updating Environment gamma curve to: ", gamma_val)
	_gamma_curve.clear_points()
	var sample_points: int = 16
	for i: int in range(sample_points + 1):
		var t: float = float(i) / float(sample_points)
		var val: float = pow(t, 1.0 / maxf(gamma_val, 0.001))
		_gamma_curve.add_point(Vector2(t, val))

	env.adjustment_color_correction = _gamma_texture


## Finds the active [WorldEnvironment] node using [NodeQuery].
func _find_world_environment() -> WorldEnvironment:
	var env_node: Node = NodeQuery.get_single_node_in_group(get_tree(), &"world_environment")
	if env_node is WorldEnvironment:
		return env_node as WorldEnvironment

	var curr_scene: Node = get_tree().current_scene
	if is_instance_valid(curr_scene):
		var direct: Node = NodeQuery.find_first_child_of_type(curr_scene, WorldEnvironment)
		if direct is WorldEnvironment:
			return direct as WorldEnvironment

	return null


## Synchronizes colorblind mode dropdown selection from external events.
func sync_external_colorblind(mode: int) -> void:
	print("UI: Syncing external colorblind mode index: ", mode)
	if is_instance_valid(colorblind_option) and colorblind_option.selected != mode:
		colorblind_option.selected = mode


## Synchronizes high contrast button toggle from external events.
func sync_external_high_contrast(active: bool) -> void:
	print("UI: Syncing external high contrast UI state: ", active)
	if is_instance_valid(high_contrast_toggle) and high_contrast_toggle.button_pressed != active:
		high_contrast_toggle.set_pressed_no_signal(active)


## Synchronizes photosensitivity button toggle from external events.
func sync_external_photosensitivity(active: bool) -> void:
	print("UI: Syncing external photosensitivity mode state: ", active)
	if (
		is_instance_valid(photosensitivity_toggle)
		and photosensitivity_toggle.button_pressed != active
	):
		photosensitivity_toggle.set_pressed_no_signal(active)
