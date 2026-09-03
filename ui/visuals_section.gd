## Controls post-processing, screen filters, brightness, contrast, and colorblind modes.
## Attached to the VisualsSection GridContainer.
class_name AccessibilityVisualsSection
extends GridContainer

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


## Lifecycle initialization method configuring options and slider listeners.
func _ready() -> void:
	print("UI: Initializing Visuals Section.")
	_populate_dropdowns()
	_connect_signals()


## Populates OptionButton items for screen filters and colorblind presets.
func _populate_dropdowns() -> void:
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


## Connects interactive controls and slider value adjustments.
func _connect_signals() -> void:
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


## Reads stored visual options from GlobalSettings into UI components.
func load_settings() -> void:
	print("UI: Loading Visuals settings.")
	if is_instance_valid(colorblind_option):
		colorblind_option.selected = int(
			GlobalSettings.get_setting("Settings", "colorblind_mode", DEFAULT_COLORBLIND_MODE)
		)
		_apply_colorblind_settings()

	if is_instance_valid(screen_filter_option):
		var initial_filter: int = int(
			GlobalSettings.get_setting("Settings", "screen_filter", DEFAULT_SCREEN_FILTER)
		)
		screen_filter_option.selected = initial_filter
		_on_screen_filter_selected(initial_filter)

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


## Connects companion slider and LineEdit pairs with instant clear and revert on defocus.
## [param slider] The [HSlider] instance.
## [param input_box] The [LineEdit] instance.
## [param key] The setting key identifier.
## [param min_val] The minimum value clamp.
## [param max_val] The maximum value clamp.
## [param section] Settings section category.
## [param is_int] Whether display text should format as integer.
## [param custom_cb] Optional callback invoked on value changes.
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
	if is_instance_valid(slider):
		slider.min_value = min_val
		slider.max_value = max_val
		slider.value_changed.connect(
			func(val: float) -> void:
				if is_instance_valid(input_box) and not input_box.has_focus():
					input_box.text = str(int(val)) if is_int else ("%.2f" % val)
				if custom_cb.is_valid():
					custom_cb.call(val)
				else:
					_apply_visual_settings()
		)
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					print("Player adjusted ", key, " to: ", slider.value)
					GlobalSettings.save_setting(section, key, slider.value)
		)

	if is_instance_valid(input_box):
		input_box.focus_entered.connect(
			func() -> void:
				input_box.set_meta("pre_focus_text", input_box.text)
				input_box.text = ""
		)
		input_box.text_submitted.connect(
			func(txt: String) -> void:
				var trimmed: String = txt.strip_edges()
				var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
				if trimmed == "" or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var new_val: float = clampf(trimmed.to_float(), min_val, max_val)
					input_box.text = str(int(new_val)) if is_int else ("%.2f" % new_val)
					if is_instance_valid(slider):
						slider.value = new_val
					print("Player manually typed ", key, " input: ", new_val)
					GlobalSettings.save_setting(section, key, new_val)
					if custom_cb.is_valid():
						custom_cb.call(new_val)
					else:
						_apply_visual_settings()
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				var trimmed: String = input_box.text.strip_edges()
				var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
				if trimmed == "" or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var new_val: float = clampf(trimmed.to_float(), min_val, max_val)
					input_box.text = str(int(new_val)) if is_int else ("%.2f" % new_val)
					if is_instance_valid(slider):
						slider.value = new_val
					print("Player committed ", key, " input on defocus: ", new_val)
					GlobalSettings.save_setting(section, key, new_val)
					if custom_cb.is_valid():
						custom_cb.call(new_val)
					else:
						_apply_visual_settings()
		)


## Reads a float setting and synchronizes slider and LineEdit representations.
## [param slider] The target [HSlider] node.
## [param input_box] The target [LineEdit] node.
## [param key] Setting key identifier.
## [param default_val] Fallback float value.
func _load_slider(slider: HSlider, input_box: LineEdit, key: String, default_val: float) -> void:
	if is_instance_valid(slider):
		var val: float = float(GlobalSettings.get_setting("Settings", key, default_val))
		slider.value = val
		if is_instance_valid(input_box):
			input_box.text = "%.2f" % val


## Handles user selection of colorblind dropdown options.
## [param index] Selected mode index.
func _on_colorblind_selected(index: int) -> void:
	print("Player changed colorblind mode to index: ", index)
	GlobalSettings.save_setting("Settings", "colorblind_mode", index)
	_apply_colorblind_settings()


## Broadcasts selected colorblind mode to global event bus.
func _apply_colorblind_settings() -> void:
	if not is_instance_valid(colorblind_option):
		return
	var mode: int = colorblind_option.selected
	print("Engine: Applying Colorblind shader mode: ", mode)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("colorblind_mode_changed"):
			events.emit_signal("colorblind_mode_changed", mode)


## Handles screen filter dropdown selections.
## [param index] Selected screen filter index.
func _on_screen_filter_selected(index: int) -> void:
	var filter_ids: Array[String] = GlobalSettings.get_screen_filter_ids()
	if index < 0 or index >= filter_ids.size():
		return
	var filter_name: String = filter_ids[index]
	print("Player selected Screen Filter: ", filter_name)
	GlobalSettings.save_setting("Settings", "screen_filter", index)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("screen_filter_changed"):
			events.screen_filter_changed.emit(filter_name)


## Broadcasts film grain intensity value updates.
## [param val] Post-process film grain intensity.
func _apply_film_grain(val: float) -> void:
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("film_grain_changed"):
			events.film_grain_changed.emit(val)


## Handles photosensitivity safe mode toggling.
## [param toggled_on] Enabled state.
func _on_photosensitivity_toggled(toggled_on: bool) -> void:
	print("Player toggled Photosensitivity Mode to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "photosensitivity", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("photosensitivity_mode_toggled"):
			events.photosensitivity_mode_toggled.emit(toggled_on)


## Handles high contrast mode toggling.
## [param toggled_on] Enabled state.
func _on_high_contrast_toggled(toggled_on: bool) -> void:
	print("Player toggled High Contrast UI to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "high_contrast_ui", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("high_contrast_toggled"):
			events.high_contrast_toggled.emit(toggled_on)


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


## Updates the [Environment] adjustment color correction gradient using a gamma power curve.
## [param gamma_val] The target gamma exponent value.
## [param env] The target [Environment] resource to update.
func _apply_gamma_to_environment(gamma_val: float, env: Environment) -> void:
	if not is_instance_valid(env):
		return

	print("Engine: Updating Environment gamma curve to: ", gamma_val)
	var curve: Curve = Curve.new()
	var sample_points: int = 16
	for i: int in range(sample_points + 1):
		var t: float = float(i) / float(sample_points)
		var val: float = pow(t, 1.0 / maxf(gamma_val, 0.001))
		curve.add_point(Vector2(t, val))

	var curve_tex: CurveTexture = CurveTexture.new()
	curve_tex.curve = curve
	env.adjustment_color_correction = curve_tex


## Finds the active WorldEnvironment node in the tree with fallbacks.
## [return] The [WorldEnvironment] node if located, otherwise `null`.
func _find_world_environment() -> WorldEnvironment:
	var env_nodes: Array[Node] = get_tree().get_nodes_in_group("world_environment")
	if not env_nodes.is_empty():
		return env_nodes[0] as WorldEnvironment

	var root: Node = get_tree().current_scene
	if not root:
		root = get_tree().root
	return _find_first_child_of_type(root, "WorldEnvironment") as WorldEnvironment


## Recursively searches a subtree for the first node matching a type name.
## [param parent] Starting parent [Node].
## [param type_str] String name of the target node class.
## [return] The matching [Node] instance or `null`.
func _find_first_child_of_type(parent: Node, type_str: String) -> Node:
	if not parent:
		return null
	if parent.is_class(type_str) or parent.get_class() == type_str:
		return parent
	for child: Node in parent.get_children():
		var found: Node = _find_first_child_of_type(child, type_str)
		if found:
			return found
	return null


## Synchronizes colorblind mode dropdown selection from external events.
## [param mode] External colorblind mode index.
func sync_external_colorblind(mode: int) -> void:
	if is_instance_valid(colorblind_option) and colorblind_option.selected != mode:
		colorblind_option.selected = mode


## Synchronizes high contrast button toggle from external events.
## [param active] External state.
func sync_external_high_contrast(active: bool) -> void:
	if is_instance_valid(high_contrast_toggle) and high_contrast_toggle.button_pressed != active:
		high_contrast_toggle.set_pressed_no_signal(active)


## Synchronizes photosensitivity button toggle from external events.
## [param active] External state.
func sync_external_photosensitivity(active: bool) -> void:
	if (
		is_instance_valid(photosensitivity_toggle)
		and photosensitivity_toggle.button_pressed != active
	):
		photosensitivity_toggle.set_pressed_no_signal(active)
