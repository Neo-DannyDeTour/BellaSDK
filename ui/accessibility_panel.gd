extends Panel

const DEFAULT_BRIGHTNESS: float = 1.0
const DEFAULT_CONTRAST: float = 1.0
const DEFAULT_SATURATION: float = 1.0
const DEFAULT_FOV: float = 75.0
const DEFAULT_DISABLE_SPRINT_FOV: bool = false
const DEFAULT_SENSITIVITY: float = 0.5

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


func _ready() -> void:
	print("UI: Accessibility Panel initialized.")

	_connect_adjustment_signals(brightness_slider, brightness_input, "brightness")
	_connect_adjustment_signals(contrast_slider, contrast_input, "contrast")
	_connect_adjustment_signals(saturation_slider, saturation_input, "saturation")

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

	# FIXED: Added explicit 'as float' cast to prevent strict typing assignment crash.
	var saved_sens: float = GlobalSettings.get_setting(
		"Settings", "mouse_sensitivity", DEFAULT_SENSITIVITY
	) as float
	
	sens_slider.value = saved_sens
	sens_input.text = "%.2f" % saved_sens
	
	# FIXED: Actually apply the setting to the player on load
	_apply_sensitivity_settings()


func _connect_adjustment_signals(
	slider: HSlider, input_box: LineEdit, setting_name: String
) -> void:
	slider.value_changed.connect(_on_adjustment_changed.bind(input_box))
	slider.drag_ended.connect(_on_adjustment_drag_ended.bind(setting_name, slider))
	input_box.text_submitted.connect(_on_adjustment_input_submitted.bind(setting_name, slider))
	input_box.focus_entered.connect(_on_adjustment_focus_entered.bind(input_box))
	input_box.focus_exited.connect(
		_on_adjustment_focus_exited.bind(input_box, slider, setting_name)
	)


func _on_adjustment_changed(value: float, input_node: LineEdit) -> void:
	if not input_node.has_focus():
		input_node.text = "%.2f" % value
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
	var env_node: WorldEnvironment = get_tree().root.find_child("WorldEnvironment", true, false)
	if env_node and env_node.environment:
		env_node.environment.adjustment_enabled = true
		env_node.environment.adjustment_brightness = brightness_slider.value
		env_node.environment.adjustment_contrast = contrast_slider.value
		env_node.environment.adjustment_saturation = saturation_slider.value


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
		print("UI: Successfully located player node via group.")
		return player_node
		
	push_warning("UI: Player node not found in scene tree.")
	return null
