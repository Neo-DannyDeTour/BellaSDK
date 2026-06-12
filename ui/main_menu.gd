extends CanvasLayer

const DEFAULT_FOV: float = 75.0
const DEFAULT_DISABLE_SPRINT_FOV: bool = false

const RESOLUTIONS: Dictionary = {
	"1920 x 1080": Vector2i(1920, 1080),
	"1600 x 900": Vector2i(1600, 900),
	"1366 x 768": Vector2i(1366, 768),
	"1280 x 720": Vector2i(1280, 720),
	"1024 x 768": Vector2i(1024, 768),
	"800 x 600": Vector2i(800, 600),
	"640 x 480": Vector2i(640, 480)
}

const SAVE_PATH: String = "user://settings.cfg"
const DEFAULT_SENSITIVITY: float = 0.05

# --- NEW: ACCESSIBILITY DEFAULTS ---
const DEFAULT_BRIGHTNESS: float = 1.0
const DEFAULT_CONTRAST: float = 1.0
const DEFAULT_SATURATION: float = 1.0

const CHAPTER_SCREEN: PackedScene = preload("res://ui/chapter_screen.tscn")

const FPS_LIMITS: Dictionary = {
	"30 FPS": 30,
	"40 FPS": 40,
	"60 FPS": 60,
	"90 FPS": 90,
	"120 FPS": 120,
	"144 FPS": 144,
	"Unlimited": 0
}

const DEFAULT_FPS: int = 60

const VSYNC_MODES: Dictionary = {
	"Enabled": DisplayServer.VSYNC_ENABLED,
	"Disabled": DisplayServer.VSYNC_DISABLED,
	"Adaptive": DisplayServer.VSYNC_ADAPTIVE
}

const DEFAULT_VSYNC: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED

# --- NEW CONSTANTS FOR FSR ---
const FSR_MODES: Dictionary = {
	"Disabled (Native)": 1.0, 
	"Quality": 0.77, 
	"Balanced": 0.59, 
	"Performance": 0.50
}
const DEFAULT_FSR_MODE: String = "Disabled (Native)"

# --- UNIFIED ANTI-ALIASING SYSTEM ---
const AA_MODES: Dictionary = {
	"Disabled": {
		"msaa": Viewport.MSAA_DISABLED, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"FXAA (Fast)": {
		"msaa": Viewport.MSAA_DISABLED, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_FXAA
	},
	"TAA (Smooth)": {
		"msaa": Viewport.MSAA_DISABLED, 
		"taa": true, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 2x": {
		"msaa": Viewport.MSAA_2X, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 4x": {
		"msaa": Viewport.MSAA_4X, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 8x (Heavy)": {
		"msaa": Viewport.MSAA_8X, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 2x + TAA (High)": {
		"msaa": Viewport.MSAA_2X, 
		"taa": true, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	}
}
const DEFAULT_AA_MODE: String = "Disabled"

# --- AUTOMATED REMAPPING ---
var is_remapping: bool = false
var action_to_remap: String = ""
var remapping_button: Button = null

# --- NEW SWAP VARIABLES ---
var pending_swap_event: InputEvent = null
var pending_conflict_action: String = ""

# List every action exactly as it appears in your Project Settings > Input Map
var my_actions: Array[String] = [
	"forward",
	"backward",
	"left",
	"right",
	"jump",
	"crouch",
	"interact",
	"flashlight",
	"zoom",
	"noclip",
	"console"
]

# --- AUTO-CALIBRATION VARIABLES ---
var max_mouse_speed: float = 0.0
var has_calibrated: bool = false

@onready var main_buttons: VBoxContainer = $MarginContainer/MainButtons
@onready var options: Panel = $Options
@onready var controls_panel: Panel = $ControlsPanel

# --- NEW: ACCESSIBILITY ---
@onready var accessibility_panel: Panel = $AccessibilityPanel
@onready var brightness_slider: HSlider = %BrightnessSlider
@onready var brightness_input: LineEdit = %BrightnessLine
@onready var contrast_slider: HSlider = %ContrastSlider
@onready var contrast_input: LineEdit = %ContrastLine
@onready var saturation_slider: HSlider = %SaturationSlider
@onready var saturation_input: LineEdit = %SaturationLine

@onready var continue_button: Button = %Continue
@onready var new_game_button: Button = %NewGame
@onready var restart_button: Button = %RestartGame

# --- EXPLICIT UI REFERENCES ---
@onready var sens_slider: HSlider = %MouseSensitivitySlider
@onready var sens_label: Label = %MouseSensitivityLabel
@onready var sens_input: LineEdit = %MouseSensitivityLine

# --- RESOLUTION VARIABLES ---
@onready var resolution_options: OptionButton = %ResolutionOptionButton

@onready var accessibility_button: Button = (
	$Options/MarginContainer/OptionsButtons/HBoxContainer/AccessibilityButton
)
@onready var options_content: VBoxContainer = $Options/VBoxContainer
@onready var back_accessibility_button: Button = %BackAccessibilityButton

# --- NEW: FOV SETTINGS ---
@onready var fov_slider: HSlider = %FOVSlider
@onready var fov_input: LineEdit = %FOVLine
@onready var sprint_fov_checkbox: CheckBox = %SprintFovCheckbox
@onready var fps_options: OptionButton = %FPSOptionButton
@onready var vsync_options: OptionButton = %VSyncOptionButton

# --- FSR REFERENCE ---
@onready var fsr_options: OptionButton = %FSROptionButton

# --- AA REFERENCE ---
@onready var aa_options: OptionButton = %AAOptionButton

# --- SAVE/LOAD PANEL REFERENCES ---
@onready var save_load_panel: Panel = $SaveLoadPanel
@onready var save_load_title: Label = %SaveLoadTitle
@onready var close_save_menu_button: Button = %CloseSaveMenuButton
@onready var create_new_save_button: Button = %CreateNewSaveButton
@onready var save_list_container: VBoxContainer = %SaveListContainer
@onready var save_button: Button = %SaveGame
@onready var load_button: Button = %LoadGame

const SAVE_SLOT_SCENE: PackedScene = preload("res://core/save_slot.tscn")

var is_currently_saving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_populate_resolution_dropdown()
	resolution_options.item_selected.connect(_on_resolution_selected)

	# --- NEW: Setup FPS Dropdown ---
	_populate_fps_dropdown()
	fps_options.item_selected.connect(_on_fps_selected)

	# VSYNC
	_populate_vsync_dropdown()
	vsync_options.item_selected.connect(_on_vsync_selected)

	_populate_fsr_dropdown()
	fsr_options.item_selected.connect(_on_fsr_selected)

	_populate_aa_dropdown()
	aa_options.item_selected.connect(_on_aa_selected)

	# 1. Connect signals FIRST
	sens_slider.value_changed.connect(_on_sensitivity_changed)
	sens_slider.drag_ended.connect(_on_sensitivity_drag_ended)

	if has_node("%MouseSensitivityLine"):
		sens_input.text_submitted.connect(_on_sensitivity_input_submitted)
		sens_input.focus_entered.connect(_on_sensitivity_focus_entered)
		sens_input.focus_exited.connect(_on_sensitivity_focus_exited)

	continue_button.pressed.connect(_on_resume_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	back_accessibility_button.pressed.connect(_on_back_accessibility_pressed)

	fov_slider.value_changed.connect(_on_fov_changed)
	fov_slider.drag_ended.connect(_on_fov_drag_ended)
	fov_input.text_submitted.connect(_on_fov_input_submitted)
	fov_input.focus_entered.connect(_on_fov_focus_entered)
	fov_input.focus_exited.connect(_on_fov_focus_exited)

	sprint_fov_checkbox.toggled.connect(_on_sprint_fov_toggled)
	
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	close_save_menu_button.pressed.connect(_on_close_save_menu)
	create_new_save_button.pressed.connect(_on_create_new_save)

	# --- NEW: ACCESSIBILITY SIGNAL BINDING ---
	_connect_adjustment_signals(brightness_slider, brightness_input, "brightness")
	_connect_adjustment_signals(contrast_slider, contrast_input, "contrast")
	_connect_adjustment_signals(saturation_slider, saturation_input, "saturation")

	# 2. Load from file
	load_controls()

	# 3. CONTEXT CHECK: Are we at the Title Screen or in the Game?
	var saves_exist: bool = SaveManager.has_saves()
	load_button.visible = saves_exist

	if get_parent().has_method("toggle_pause"):
		# We are IN-GAME
		continue_button.show()
		restart_button.show()
		save_button.show()
		new_game_button.text = "" 
	else:
		# We are at the TITLE SCREEN
		continue_button.hide()
		restart_button.hide()
		save_button.hide()

	# 4. Set up the UI visibility
	_return_to_main_buttons()
	create_control_list()

	# Connect the new button
	accessibility_button.pressed.connect(_on_accessibility_pressed)


# --- NEW: ACCESSIBILITY HELPER ---
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


func create_control_list() -> void:
	var container: VBoxContainer = $ControlsPanel/VBoxContainer
	var template: Button = $ControlsPanel/VBoxContainer/RemapButtonTemplate

	for action: String in my_actions:
		var new_button: Button = template.duplicate() as Button
		new_button.show()
		container.add_child(new_button)
		new_button.set_meta("action", action)
		update_button_text(new_button, action)
		new_button.toggled.connect(_on_any_remap_button_toggled.bind(new_button))


func _on_any_remap_button_toggled(toggled_on: bool, button: Button) -> void:
	if toggled_on:
		is_remapping = true
		remapping_button = button
		action_to_remap = button.get_meta("action")
		button.text = "Press any key..."
	else:
		is_remapping = false
		pending_swap_event = null
		update_button_text(button, button.get_meta("action"))


func update_button_text(button: Button, action: String) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var key_name: String = "Unassigned"

	if events.size() > 0:
		var raw_text: String = events[0].as_text()
		key_name = (
			raw_text
			. replace(" (Physical)", "")
			. replace(" - Physical", "")
			. replace(" (Physics)", "")
			. replace(" - Physics", "")
			. strip_edges()
		)

	button.text = action.capitalize() + ": " + key_name


func _on_new_game_pressed() -> void:
	if not has_calibrated:
		_apply_bucket_calibration()

	main_buttons.hide()
	var chapter_window: Node = CHAPTER_SCREEN.instantiate()
	add_child(chapter_window)


func _on_start_game_pressed() -> void:
	if not has_calibrated:
		_apply_bucket_calibration()

	get_tree().paused = false

	if get_parent().has_method("toggle_pause"):
		get_tree().reload_current_scene()


func _apply_bucket_calibration() -> void:
	has_calibrated = true
	var auto_sens: float = DEFAULT_SENSITIVITY

	# 7-TIER BUCKET SYSTEM (0.05 to 0.70)
	if max_mouse_speed > 6500.0:
		auto_sens = 0.70
		print("Calibrated: TIER 7 - Extreme (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 5000.0:
		auto_sens = 0.50
		print("Calibrated: TIER 6 - Fast (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 4000.0:
		auto_sens = 0.40
		print("Calibrated: TIER 5 - Moderately Fast (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 3000.0:
		auto_sens = 0.30
		print("Calibrated: TIER 4 - Average (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 2000.0:
		auto_sens = 0.20
		print("Calibrated: TIER 3 - Moderately Low (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 1000.0:
		auto_sens = 0.10
		print("Calibrated: TIER 2 - Low (Speed: ", max_mouse_speed, ")")
	else:
		auto_sens = 0.05
		print("Calibrated: TIER 1 - Precise/Arm Aimer (Speed: ", max_mouse_speed, ")")

	sens_slider.value = auto_sens
	_save_setting_to_disk("mouse_sensitivity", auto_sens)


func _on_exit_pressed() -> void:
	get_tree().quit()


# --- UPDATED: PANEL ROUTING ---

# Helper function to clear duplicated linter warnings for resetting UI panels
func _return_to_main_buttons() -> void:
	main_buttons.visible = true
	options.visible = false
	controls_panel.visible = false
	if accessibility_panel:
		accessibility_panel.visible = false


func _on_options_pressed() -> void:
	main_buttons.visible = false
	options.visible = true
	options_content.visible = true
	controls_panel.visible = false
	accessibility_panel.visible = false


func _on_back_pressed() -> void:
	_return_to_main_buttons()


func _on_contols_pressed() -> void:
	options_content.visible = false
	controls_panel.visible = true


func _on_back_controls_pressed() -> void:
	options_content.visible = true
	controls_panel.visible = false


func _on_accessibility_pressed() -> void:
	options_content.visible = false
	accessibility_panel.visible = true


func _on_back_accessibility_pressed() -> void:
	options_content.visible = true
	accessibility_panel.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not self.visible:
			return

		if is_remapping:
			is_remapping = false
			pending_swap_event = null
			remapping_button.button_pressed = false
			update_button_text(remapping_button, action_to_remap)
			if has_node("%ConflictPanel"):
				%ConflictPanel.hide()
			get_viewport().set_input_as_handled()
			return

		if controls_panel.visible:
			_on_back_controls_pressed()
			get_viewport().set_input_as_handled()
		elif accessibility_panel.visible:
			_on_back_accessibility_pressed()
			get_viewport().set_input_as_handled()
		elif options.visible:
			_on_back_pressed()
			get_viewport().set_input_as_handled()
		elif main_buttons.visible and get_parent().has_method("toggle_pause"):
			_on_resume_pressed()
			get_viewport().set_input_as_handled()

	if is_remapping:
		if event is InputEventKey or event is InputEventMouseButton:
			if event.is_pressed():
				if pending_swap_event != null and event.as_text() == pending_swap_event.as_text():
					execute_swap(event)
					return

				var conflicting_action: String = get_action_with_event(event)

				if conflicting_action != "" and conflicting_action != action_to_remap:
					pending_swap_event = event
					pending_conflict_action = conflicting_action

					var key_name: String = event.as_text().split("(")[0].strip_edges()
					%ConflictLabel.text = (
						action_to_remap.capitalize()
						+ " and "
						+ conflicting_action.capitalize()
						+ " use the same key. \nPress ["
						+ key_name
						+ "] again to switch, or press a different key."
					)
					%ConflictPanel.show()

					get_tree().create_timer(4.0).timeout.connect(
						func() -> void: %ConflictPanel.hide()
					)
					get_viewport().set_input_as_handled()
					return

				InputMap.action_erase_events(action_to_remap)
				InputMap.action_add_event(action_to_remap, event)

				save_controls()

				is_remapping = false
				pending_swap_event = null
				remapping_button.button_pressed = false
				update_button_text(remapping_button, action_to_remap)

				%ConflictPanel.hide()
				get_viewport().set_input_as_handled()

	if not has_calibrated and event is InputEventMouseMotion:
		var current_speed: float = event.velocity.length()
		if current_speed > max_mouse_speed:
			max_mouse_speed = current_speed


func _on_reset_button_pressed() -> void:
	InputMap.load_from_project_settings()

	var dir: DirAccess = DirAccess.open("user://")
	if dir and dir.file_exists("settings.cfg"):
		dir.remove("settings.cfg")

	sens_slider.value = DEFAULT_SENSITIVITY

	brightness_slider.value = DEFAULT_BRIGHTNESS
	contrast_slider.value = DEFAULT_CONTRAST
	saturation_slider.value = DEFAULT_SATURATION
	_apply_visual_settings()

	has_calibrated = false
	max_mouse_speed = 0.0

	refresh_all_button_labels()

	fov_slider.value = DEFAULT_FOV
	sprint_fov_checkbox.button_pressed = DEFAULT_DISABLE_SPRINT_FOV

	Engine.max_fps = DEFAULT_FPS
	for i: int in range(fps_options.get_item_count()):
		var key: String = fps_options.get_item_text(i)
		if FPS_LIMITS[key] == DEFAULT_FPS:
			fps_options.select(i)
			break
	_save_setting_to_disk("fps_limit", DEFAULT_FPS)

	DisplayServer.window_set_vsync_mode(DEFAULT_VSYNC)
	for i: int in range(vsync_options.get_item_count()):
		var key: String = vsync_options.get_item_text(i)
		if VSYNC_MODES[key] == DEFAULT_VSYNC:
			vsync_options.select(i)
			break
	_save_setting_to_disk("vsync_mode", DEFAULT_VSYNC)

	_apply_aa(DEFAULT_AA_MODE)
	for i: int in range(aa_options.get_item_count()):
		if aa_options.get_item_text(i) == DEFAULT_AA_MODE:
			aa_options.select(i)
			break
	_save_setting_to_disk("aa_mode", DEFAULT_AA_MODE)


func refresh_all_button_labels() -> void:
	var container: VBoxContainer = $ControlsPanel/VBoxContainer
	for child: Node in container.get_children():
		if child is Button and child.has_meta("action"):
			var action_name: String = child.get_meta("action")
			update_button_text(child, action_name)


func save_controls() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)

	for action: String in my_actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.size() > 0:
			config.set_value("Controls", action, events[0])

	config.save(SAVE_PATH)
	print("Controls saved to: ", OS.get_user_data_dir())


func load_controls() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(SAVE_PATH)

	if err != OK:
		sens_slider.value = DEFAULT_SENSITIVITY
		brightness_slider.value = DEFAULT_BRIGHTNESS
		contrast_slider.value = DEFAULT_CONTRAST
		saturation_slider.value = DEFAULT_SATURATION
		_apply_visual_settings()
		return

	for action: String in my_actions:
		if config.has_section_key("Controls", action):
			var event: InputEvent = config.get_value("Controls", action) as InputEvent
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)

	if config.has_section_key("Settings", "mouse_sensitivity"):
		var saved_sens: float = config.get_value("Settings", "mouse_sensitivity")
		sens_slider.value = saved_sens
		has_calibrated = true

	brightness_slider.value = config.get_value("Settings", "brightness", DEFAULT_BRIGHTNESS)
	contrast_slider.value = config.get_value("Settings", "contrast", DEFAULT_CONTRAST)
	saturation_slider.value = config.get_value("Settings", "saturation", DEFAULT_SATURATION)
	_apply_visual_settings()
	brightness_input.text = "%.2f" % brightness_slider.value
	contrast_input.text = "%.2f" % contrast_slider.value
	saturation_input.text = "%.2f" % saturation_slider.value

	if (
		config.has_section_key("Settings", "resolution_x")
		and config.has_section_key("Settings", "resolution_y")
	):
		var res_x: int = config.get_value("Settings", "resolution_x")
		var res_y: int = config.get_value("Settings", "resolution_y")
		var saved_res: Vector2i = Vector2i(res_x, res_y)

		get_window().content_scale_size = saved_res

		var is_fullscreen: bool = (
			get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN
			or get_window().mode == Window.MODE_FULLSCREEN
		)
		if not is_fullscreen:
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = saved_res
			_center_window(saved_res)

		var res_string: String = str(res_x) + " x " + str(res_y)
		for i: int in range(resolution_options.get_item_count()):
			if resolution_options.get_item_text(i) == res_string:
				resolution_options.select(i)
				break

	fov_slider.value = config.get_value("Settings", "base_fov", DEFAULT_FOV)
	sprint_fov_checkbox.button_pressed = config.get_value(
		"Settings", "disable_sprint_fov", DEFAULT_DISABLE_SPRINT_FOV
	)
	fov_input.text = str(int(fov_slider.value))

	await get_tree().process_frame

	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.base_fov = fov_slider.value
		player.camera_controller.disable_sprint_fov = sprint_fov_checkbox.button_pressed

		player.camera_controller.mouse_sensitivity_base = sens_slider.value
		player.camera_controller.mouse_sensitivity = sens_slider.value

	var saved_fps: int = config.get_value("Settings", "fps_limit", DEFAULT_FPS)

	for i: int in range(fps_options.get_item_count()):
		var key: String = fps_options.get_item_text(i)
		if FPS_LIMITS[key] == saved_fps:
			fps_options.select(i)
			break

	var saved_vsync: int = config.get_value("Settings", "vsync_mode", DEFAULT_VSYNC)
	DisplayServer.window_set_vsync_mode(saved_vsync as DisplayServer.VSyncMode)

	for i: int in range(vsync_options.get_item_count()):
		var key: String = vsync_options.get_item_text(i)
		if VSYNC_MODES[key] == saved_vsync:
			vsync_options.select(i)
			break

	var saved_fsr: String = config.get_value("Settings", "fsr_mode", DEFAULT_FSR_MODE)
	_apply_fsr(saved_fsr)

	for i: int in range(fsr_options.get_item_count()):
		if fsr_options.get_item_text(i) == saved_fsr:
			fsr_options.select(i)
			break

	var saved_aa: String = config.get_value("Settings", "aa_mode", DEFAULT_AA_MODE)
	_apply_aa(saved_aa)

	for i: int in range(aa_options.get_item_count()):
		if aa_options.get_item_text(i) == saved_aa:
			aa_options.select(i)
			break


func get_action_with_event(new_event: InputEvent) -> String:
	for action: String in my_actions:
		if InputMap.action_has_event(action, new_event):
			return action
	return ""


func execute_swap(new_event: InputEvent) -> void:
	var old_events: Array[InputEvent] = InputMap.action_get_events(action_to_remap)
	var old_event: InputEvent = old_events[0] if old_events.size() > 0 else null

	InputMap.action_erase_events(action_to_remap)
	InputMap.action_erase_events(pending_conflict_action)
	InputMap.action_add_event(action_to_remap, new_event)

	if old_event:
		InputMap.action_add_event(pending_conflict_action, old_event)

	save_controls()

	is_remapping = false
	pending_swap_event = null
	pending_conflict_action = ""
	remapping_button.button_pressed = false

	refresh_all_button_labels()

	%ConflictLabel.text = "Keys swapped successfully!"
	%ConflictPanel.show()
	get_tree().create_timer(2.0).timeout.connect(func() -> void: %ConflictPanel.hide())
	get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	var parent: Node = get_parent()
	if parent and parent.has_method("toggle_pause"):
		parent.toggle_pause()


func _save_setting_to_disk(key: String, value: Variant) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value("Settings", key, value)
	config.save(SAVE_PATH)


func _on_sensitivity_changed(value: float) -> void:
	sens_label.text = "Mouse Sensitivity: "
	if not sens_input.has_focus():
		sens_input.text = "%.2f" % value

	var player: Node = _get_player()

	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.mouse_sensitivity_base = value
		player.camera_controller.mouse_sensitivity = value


func _on_sensitivity_drag_ended(value_changed: bool) -> void:
	if value_changed:
		_save_setting_to_disk("mouse_sensitivity", sens_slider.value)


func _on_sensitivity_input_submitted(new_text: String) -> void:
	var new_val: float = clamp(new_text.to_float(), 0.01, 1.0)
	sens_slider.value = new_val
	sens_input.release_focus()
	_save_setting_to_disk("mouse_sensitivity", new_val)


func _on_sensitivity_focus_entered() -> void:
	sens_input.text = ""


func _on_sensitivity_focus_exited() -> void:
	var current_text: String = sens_input.text.strip_edges()
	if current_text == "":
		sens_input.text = "%.2f" % sens_slider.value
	else:
		_on_sensitivity_input_submitted(current_text)


func _on_adjustment_changed(value: float, input_node: LineEdit) -> void:
	if not input_node.has_focus():
		input_node.text = "%.2f" % value
	_apply_visual_settings()


func _on_adjustment_drag_ended(
	value_changed: bool, setting_name: String, slider_node: HSlider
) -> void:
	if value_changed:
		_save_setting_to_disk(setting_name, slider_node.value)


func _on_adjustment_input_submitted(
	new_text: String, setting_name: String, slider_node: HSlider
) -> void:
	var new_val: float = clamp(new_text.to_float(), 0.0, 3.0)
	slider_node.value = new_val
	slider_node.release_focus()
	_save_setting_to_disk(setting_name, new_val)


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
	var env_node: WorldEnvironment = get_tree().root.find_child("WorldEnvironment", true, false)
	if env_node and env_node.environment:
		env_node.environment.adjustment_enabled = true
		env_node.environment.adjustment_brightness = brightness_slider.value
		env_node.environment.adjustment_contrast = contrast_slider.value
		env_node.environment.adjustment_saturation = saturation_slider.value


func _populate_resolution_dropdown() -> void:
	resolution_options.clear()
	for res_string: String in RESOLUTIONS.keys():
		resolution_options.add_item(res_string)


func _on_resolution_selected(index: int) -> void:
	var key: String = resolution_options.get_item_text(index)
	var new_size: Vector2i = RESOLUTIONS[key]

	get_window().content_scale_size = new_size

	var is_fullscreen: bool = (
		get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		or get_window().mode == Window.MODE_FULLSCREEN
	)

	if not is_fullscreen:
		get_window().size = new_size
		_center_window(new_size)

	_save_setting_to_disk("resolution_x", new_size.x)
	_save_setting_to_disk("resolution_y", new_size.y)


func _center_window(new_size: Vector2i) -> void:
	var current_screen: int = get_window().current_screen

	@warning_ignore("integer_division")
	var screen_center: Vector2i = (
		DisplayServer.screen_get_position(current_screen)
		+ DisplayServer.screen_get_size(current_screen) / 2
	)

	@warning_ignore("integer_division")
	var window_position: Vector2i = screen_center - new_size / 2

	get_window().position = window_position


func _on_fov_changed(value: float) -> void:
	if not fov_input.has_focus():
		fov_input.text = str(int(value))

	var player: Node = _get_player() 
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.base_fov = value


func _on_fov_drag_ended(value_changed: bool) -> void:
	if value_changed:
		_save_setting_to_disk("base_fov", fov_slider.value)


func _on_fov_input_submitted(new_text: String) -> void:
	var new_val: float = clamp(new_text.to_float(), 60.0, 120.0)
	fov_slider.value = new_val
	fov_input.release_focus()
	_save_setting_to_disk("base_fov", new_val)


func _on_fov_focus_entered() -> void:
	fov_input.text = ""


func _on_fov_focus_exited() -> void:
	var current_text: String = fov_input.text.strip_edges()
	if current_text == "":
		fov_input.text = str(int(fov_slider.value))
	else:
		_on_fov_input_submitted(current_text)


func _on_sprint_fov_toggled(toggled_on: bool) -> void:
	_save_setting_to_disk("disable_sprint_fov", toggled_on)

	var player: Node = _get_player() 
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.disable_sprint_fov = toggled_on


func _populate_fps_dropdown() -> void:
	fps_options.clear()
	for fps_string: String in FPS_LIMITS.keys():
		fps_options.add_item(fps_string)


func _on_fps_selected(index: int) -> void:
	var key: String = fps_options.get_item_text(index)
	var limit: int = FPS_LIMITS[key]

	Engine.max_fps = limit
	_save_setting_to_disk("fps_limit", limit)


func _populate_vsync_dropdown() -> void:
	vsync_options.clear()
	for vsync_string: String in VSYNC_MODES.keys():
		vsync_options.add_item(vsync_string)


func _on_vsync_selected(index: int) -> void:
	var key: String = vsync_options.get_item_text(index)
	var mode: DisplayServer.VSyncMode = VSYNC_MODES[key]

	DisplayServer.window_set_vsync_mode(mode)
	_save_setting_to_disk("vsync_mode", mode)


func _populate_fsr_dropdown() -> void:
	fsr_options.clear()
	for mode_string: String in FSR_MODES.keys():
		fsr_options.add_item(mode_string)


func _on_fsr_selected(index: int) -> void:
	var key: String = fsr_options.get_item_text(index)
	_apply_fsr(key)
	_save_setting_to_disk("fsr_mode", key)


func _apply_fsr(mode_key: String) -> void:
	var fsr_scale: float = FSR_MODES[mode_key]
	var current_viewport: Viewport = get_viewport()

	if fsr_scale >= 1.0:
		current_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		var current_aa_key: String = aa_options.get_item_text(aa_options.selected)
		_apply_aa(current_aa_key)
	else:
		current_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		current_viewport.use_taa = false

	current_viewport.scaling_3d_scale = fsr_scale


func _populate_aa_dropdown() -> void:
	aa_options.clear()
	for mode_string: String in AA_MODES.keys():
		aa_options.add_item(mode_string)


func _on_aa_selected(index: int) -> void:
	var key: String = aa_options.get_item_text(index)
	_apply_aa(key)
	_save_setting_to_disk("aa_mode", key)


func _apply_aa(mode_key: String) -> void:
	if not AA_MODES.has(mode_key):
		mode_key = DEFAULT_AA_MODE

	var settings: Dictionary = AA_MODES[mode_key]
	var current_viewport: Viewport = get_viewport()

	current_viewport.msaa_3d = settings["msaa"] as Viewport.MSAA
	current_viewport.screen_space_aa = settings["fxaa"] as Viewport.ScreenSpaceAA

	if current_viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2:
		current_viewport.use_taa = false
	else:
		current_viewport.use_taa = settings["taa"] as bool


func _get_player() -> Node:
	var parent: Node = get_parent()
	if parent and "player_body" in parent:
		return parent.player_body
	return parent


func _on_save_pressed() -> void:
	is_currently_saving = true
	_open_save_load_panel()


func _on_load_pressed() -> void:
	is_currently_saving = false
	_open_save_load_panel()


func _open_save_load_panel() -> void:
	main_buttons.visible = false
	options.visible = false
	controls_panel.visible = false
	accessibility_panel.visible = false
	
	save_load_panel.visible = true
	
	save_load_title.text = "SAVE GAME" if is_currently_saving else "LOAD GAME"
	create_new_save_button.visible = is_currently_saving
	
	_populate_save_list()


func _on_close_save_menu() -> void:
	save_load_panel.visible = false
	main_buttons.visible = true


func _on_create_new_save() -> void:
	save_load_panel.visible = false
	
	SaveManager.create_save()
	await SaveManager.save_completed
	
	_populate_save_list()
	save_load_panel.visible = true


func _populate_save_list() -> void:
	for child: Node in save_list_container.get_children():
		child.queue_free()
		
	var saves: Array = SaveManager.get_all_saves()
	print("[UI] Building save list. Found files: ", saves.size())
	
	for save_data: Dictionary in saves:
		var slot: Node = SAVE_SLOT_SCENE.instantiate()
		save_list_container.add_child(slot)
		
		if slot.has_method("setup"):
			slot.setup(save_data, is_currently_saving)
		
		if slot.has_signal("action_pressed"):
			slot.action_pressed.connect(_on_slot_action_pressed)
		if slot.has_signal("meta_updated"):
			slot.meta_updated.connect(_on_slot_meta_updated)
		if slot.has_signal("delete_pressed"):
			slot.delete_pressed.connect(_on_slot_delete_pressed)


func _on_slot_action_pressed(base_path: String) -> void:
	if is_currently_saving:
		pass 
	else:
		save_load_panel.visible = false
		main_buttons.visible = true 
		
		await SaveManager.load_save_game(base_path)
		
		if is_inside_tree():
			_on_resume_pressed()


func _on_slot_meta_updated(save_id: String, new_name: String, is_favorite: bool) -> void:
	SaveManager.update_save_meta(save_id, new_name, is_favorite)


func _on_slot_delete_pressed(save_id: String, base_path: String) -> void:
	var meta_path: String = base_path + ".meta"
	var dat_path: String = base_path + ".dat"
	var img_path: String = base_path + ".webp"
	
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)
	if FileAccess.file_exists(dat_path):
		DirAccess.remove_absolute(dat_path)
	if FileAccess.file_exists(img_path):
		DirAccess.remove_absolute(img_path)
		
	print("[SaveManager] Deleted save: ", save_id)
	
	_populate_save_list()
