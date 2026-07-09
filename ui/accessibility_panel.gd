extends Panel

const DEFAULT_BRIGHTNESS: float = 1.0
const DEFAULT_CONTRAST: float = 1.0
const DEFAULT_SATURATION: float = 1.0
const DEFAULT_FOV: float = 75.0
const DEFAULT_DISABLE_SPRINT_FOV: bool = false
const DEFAULT_SENSITIVITY: float = 0.5

# New Default Constants
const DEFAULT_UI_SCALE: float = 1.0
const DEFAULT_COLORBLIND_MODE: int = 0
const DEFAULT_FONT_MODE: int = 0

@onready var brightness_slider: HSlider = %BrightnessSlider
@onready var brightness_input: LineEdit = %BrightnessLine
@onready var contrast_slider: HSlider = %ContrastSlider
@onready var contrast_input: LineEdit = %ContrastLine
@onready var saturation_slider: HSlider = %SaturationSlider
@onready var saturation_input: LineEdit = %SaturationLine

@onready var fov_slider: HSlider = %FOVSlider
@onready var fov_input: LineEdit = %FOVLine
@onready var sprint_fov_checkbox: CheckBox = %SprintFovCheckbox

@onready var sens_slider: HSlider = %MouseSensitivitySlider
@onready var sens_input: LineEdit = %MouseSensitivityLine

# New UI Elements
@onready var ui_scale_slider: HSlider = %UIScaleSlider
@onready var ui_scale_input: LineEdit = %UIScaleLine
@onready var colorblind_option: OptionButton = %ColorblindOption
@onready var font_option: OptionButton = %FontOption


func _ready() -> void:
	print("UI: Accessibility Panel initialized.")
	
	_populate_dropdowns()

	_connect_adjustment_signals(brightness_slider, brightness_input, "brightness")
	_connect_adjustment_signals(contrast_slider, contrast_input, "contrast")
	_connect_adjustment_signals(saturation_slider, saturation_input, "saturation")
	
	# Connecting new UI Scale slider utilizing the same helper
	_connect_adjustment_signals(ui_scale_slider, ui_scale_input, "ui_scale")

	fov_slider.value_changed.connect(_on_fov_changed)
	fov_slider.drag_ended.connect(_on_fov_drag_ended)
	fov_input.text_submitted.connect(_on_fov_input_submitted)
	fov_input.focus_entered.connect(_on_fov_focus_entered)
	fov_input.focus_exited.connect(_on_fov_focus_exited)
	sprint_fov_checkbox.toggled.connect(_on_sprint_fov_toggled)

	sens_slider.value_changed.connect(_on_sensitivity_changed)
	sens_slider.drag_ended.connect(_on_sensitivity_drag_ended)
	sens_input.text_submitted.connect(_on_sensitivity_input_submitted)
	sens_input.focus_entered.connect(_on_sensitivity_focus_entered)
	sens_input.focus_exited.connect(_on_sensitivity_focus_exited)
	
	colorblind_option.item_selected.connect(_on_colorblind_selected)
	font_option.item_selected.connect(_on_font_selected)

	_load_accessibility_settings()


func _load_accessibility_settings() -> void:
	print("UI: Loading accessibility data from GlobalSettings.")
	
	brightness_slider.value = GlobalSettings.get_setting(
		"Settings", "brightness", DEFAULT_BRIGHTNESS
	) as float
	contrast_slider.value = GlobalSettings.get_setting(
		"Settings", "contrast", DEFAULT_CONTRAST
	) as float
	saturation_slider.value = GlobalSettings.get_setting(
		"Settings", "saturation", DEFAULT_SATURATION
	) as float

	brightness_input.text = "%.2f" % brightness_slider.value
	contrast_input.text = "%.2f" % contrast_slider.value
	saturation_input.text = "%.2f" % saturation_slider.value
	_apply_visual_settings()

	fov_slider.value = GlobalSettings.get_setting("Settings", "base_fov", DEFAULT_FOV) as float
	fov_input.text = str(int(fov_slider.value))
	sprint_fov_checkbox.button_pressed = GlobalSettings.get_setting(
		"Settings", "disable_sprint_fov", DEFAULT_DISABLE_SPRINT_FOV
	) as bool
	_apply_fov_settings()

	var saved_sens: float = GlobalSettings.get_setting(
		"Settings", "mouse_sensitivity", DEFAULT_SENSITIVITY
	) as float
	
	sens_slider.value = saved_sens
	sens_input.text = "%.2f" % saved_sens
	_apply_sensitivity_settings()

	# Load New Settings
	ui_scale_slider.value = GlobalSettings.get_setting(
		"Settings", "ui_scale", DEFAULT_UI_SCALE
	) as float
	ui_scale_input.text = "%.2f" % ui_scale_slider.value
	_apply_ui_scale_settings()

	colorblind_option.selected = GlobalSettings.get_setting(
		"Settings", "colorblind_mode", DEFAULT_COLORBLIND_MODE
	) as int
	_apply_colorblind_settings()

	font_option.selected = GlobalSettings.get_setting(
		"Settings", "font_mode", DEFAULT_FONT_MODE
	) as int
	_apply_font_settings()


func _connect_adjustment_signals(
	slider: HSlider, input_box: LineEdit, setting_name: String
) -> void:
	slider.value_changed.connect(_on_adjustment_changed.bind(input_box, setting_name))
	slider.drag_ended.connect(_on_adjustment_drag_ended.bind(setting_name, slider))
	input_box.text_submitted.connect(_on_adjustment_input_submitted.bind(setting_name, slider))
	input_box.focus_entered.connect(_on_adjustment_focus_entered.bind(input_box))
	input_box.focus_exited.connect(
		_on_adjustment_focus_exited.bind(input_box, slider, setting_name)
	)


func _on_adjustment_changed(
	value: float, input_node: LineEdit, setting_name: String
) -> void:
	if not input_node.has_focus():
		input_node.text = "%.2f" % value
		
	# Route the application based on what changed to remain optimized
	if setting_name == "ui_scale":
		_apply_ui_scale_settings()
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
	# OPTIMIZED: Replaced the slow find_child() with a group check.
	var env_nodes: Array[Node] = get_tree().get_nodes_in_group("world_environment")
	
	if not env_nodes.is_empty():
		var env_node: WorldEnvironment = env_nodes[0] as WorldEnvironment
		if env_node and env_node.environment:
			env_node.environment.adjustment_enabled = true
			env_node.environment.adjustment_brightness = brightness_slider.value
			env_node.environment.adjustment_contrast = contrast_slider.value
			env_node.environment.adjustment_saturation = saturation_slider.value


# --- NEW APPLY FUNCTIONS ---

func _apply_ui_scale_settings() -> void:
	var current_scale: float = ui_scale_slider.value
	print("Engine: Applying UI Scale adjustments: ", current_scale)
	# Using window content scale is the most optimized method in Godot 4
	get_window().content_scale_factor = current_scale


func _on_colorblind_selected(index: int) -> void:
	print("Player changed colorblind mode to index: ", index)
	GlobalSettings.save_setting("Settings", "colorblind_mode", index)
	_apply_colorblind_settings()


func _apply_colorblind_settings() -> void:
	var mode: int = colorblind_option.selected
	print("Engine: Applying Colorblind shader mode: ", mode)
	
	# Broadcast to the Events bus so the filter layer can intercept it
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
	
	# Map the dropdown integer to the exact strings your Events bus expects
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("font_changed"):
			var font_strings: Array[String] = ["default", "dyslexic", "papyrus", "comic"]
			if mode >= 0 and mode < font_strings.size():
				events.emit_signal("font_changed", font_strings[mode])


# --- FOV & SENSITIVITY ---

func _on_fov_changed(value: float) -> void:
	if not fov_input.has_focus():
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


func _on_sensitivity_changed(value: float) -> void:
	if not sens_input.has_focus():
		sens_input.text = "%.2f" % value
	_apply_sensitivity_settings()


func _on_sensitivity_drag_ended(value_changed: bool) -> void:
	if value_changed:
		print("Player adjusted mouse sensitivity to: ", sens_slider.value)
		GlobalSettings.save_setting("Settings", "mouse_sensitivity", sens_slider.value)


func _on_sensitivity_input_submitted(new_text: String) -> void:
	var new_val: float = clamp(new_text.to_float(), 0.01, 1.0)
	sens_slider.value = new_val
	sens_input.release_focus()
	print("Player manually typed sensitivity: ", new_val)
	GlobalSettings.save_setting("Settings", "mouse_sensitivity", new_val)


func _on_sensitivity_focus_entered() -> void:
	sens_input.text = ""


func _on_sensitivity_focus_exited() -> void:
	var current_text: String = sens_input.text.strip_edges()
	if current_text == "":
		sens_input.text = "%.2f" % sens_slider.value
	else:
		_on_sensitivity_input_submitted(current_text)


func _apply_sensitivity_settings() -> void:
	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		print("Engine: Applying mouse sensitivity settings to Player Camera.")
		player.camera_controller.mouse_sensitivity_base = sens_slider.value
		player.camera_controller.mouse_sensitivity = sens_slider.value


func _get_player() -> Node:
	var player_node: Node = get_tree().get_first_node_in_group("player")
	if player_node:
		return player_node
		
	# Removed the push_warning. It is completely normal for the player to be 
	# null if this panel is loaded during the Main Menu or transition screens.
	return null


func _populate_dropdowns() -> void:
	print("UI: Populating OptionButton dropdowns with available modes.")
	
	colorblind_option.clear()
	font_option.clear()
	
	var colorblind_modes: Array[String] = [
		"Normal", 
		"Protanopia", 
		"Deuteranopia", 
		"Tritanopia", 
        "Achromatopsia"
	]
	
	for mode: String in colorblind_modes:
		colorblind_option.add_item(mode)
		
	var font_modes: Array[String] = [
		"Default", 
		"Dyslexic", 
		"Papyrus", 
        "Comic"
	]
	
	for font: String in font_modes:
		font_option.add_item(font)
