## Controls mouse look, key toggle behaviors, gamepad vibration, and aim assistance.
## Attached to the ControlsSection GridContainer.
class_name AccessibilityControlsSection
extends GridContainer

## Default constant value for mouse sensitivity.
const DEFAULT_MOUSE_SENSITIVITY: float = 1.0

## Default constant value for motion sickness reduction.
const DEFAULT_REDUCE_MOTION: bool = false

## Default constant value for gamepad vibration strength.
const DEFAULT_VIBRATION: float = 1.0

## Default constant value for aim assistance strength.
const DEFAULT_AIM_ASSIST_AMOUNT: float = 0.5

## Default constant value for aim assistance toggle.
const DEFAULT_AIM_ASSIST: bool = true

## Default constant value for vertical camera look inversion.
const DEFAULT_INVERT_Y: bool = false

## Default constant value for crouch toggle mode.
const DEFAULT_TOGGLE_CROUCH: bool = false

## Default constant value for sprint toggle mode.
const DEFAULT_TOGGLE_SPRINT: bool = false

## Default constant value for canceling crouch on jump.
const DEFAULT_CANCEL_CROUCH_ON_JUMP: bool = true

## Slider for adjusting mouse sensitivity.
@onready var mouse_sens_slider: HSlider = get_node_or_null("%MouseSensitivitySlider")

## Text input for manual mouse sensitivity entry.
@onready var mouse_sens_input: LineEdit = get_node_or_null("%MouseSensitivityLine")

## Toggle switch for vertical camera axis inversion.
@onready var invert_y_toggle: CheckButton = get_node_or_null("%InvertYToggle")

## Toggle switch for crouch key toggle behavior.
@onready var toggle_crouch_button: CheckButton = get_node_or_null("%ToggleCrouchButton")

## Toggle switch for sprint key toggle behavior.
@onready var toggle_sprint_button: CheckButton = get_node_or_null("%ToggleSprintButton")

## Toggle switch for canceling crouch when jumping.
@onready var cancel_crouch_jump_button: CheckButton = get_node_or_null("%CancelCrouchOnJumpButton")

## Toggle switch for aim assistance enabling.
@onready var aim_assist_toggle: CheckButton = get_node_or_null("%AimAssistToggle")

## Slider for adjusting aim assistance strength.
@onready var aim_assist_slider: HSlider = get_node_or_null("%AimAssistSlider")

## Text input for manual aim assistance strength entry.
@onready var aim_assist_input: LineEdit = get_node_or_null("%AimAssistLine")

## Slider for adjusting vibration strength.
@onready var vibration_slider: HSlider = get_node_or_null("%VibrationSlider")

## Text input for manual vibration strength entry.
@onready var vibration_input: LineEdit = get_node_or_null("%VibrationLine")

## Toggle switch for camera motion and screenshake reduction.
@onready var reduce_motion_toggle: CheckButton = get_node_or_null("%ReduceMotionToggle")


## Lifecycle initialization method connecting controls inputs.
func _ready() -> void:
	print("UI: Initializing Controls Section.")
	_connect_signals()


## Connects interactive controls inputs and sliders.
func _connect_signals() -> void:
	_connect_slider(
		mouse_sens_slider,
		mouse_sens_input,
		"mouse_sensitivity",
		0.05,
		5.0,
		"Controls",
		_apply_mouse_sensitivity
	)
	_connect_slider(
		aim_assist_slider, aim_assist_input, "aim_assist_amount", 0.0, 1.0, "Gameplay", Callable()
	)
	_connect_slider(
		vibration_slider, vibration_input, "vibration_strength", 0.0, 2.0, "Gameplay", Callable()
	)

	if is_instance_valid(invert_y_toggle):
		invert_y_toggle.toggled.connect(_on_invert_y_toggled)
	if is_instance_valid(toggle_crouch_button):
		toggle_crouch_button.toggled.connect(_on_toggle_crouch_toggled)
	if is_instance_valid(toggle_sprint_button):
		toggle_sprint_button.toggled.connect(_on_toggle_sprint_toggled)
	if is_instance_valid(cancel_crouch_jump_button):
		cancel_crouch_jump_button.toggled.connect(_on_cancel_crouch_jump_toggled)
	if is_instance_valid(aim_assist_toggle):
		aim_assist_toggle.toggled.connect(_on_aim_assist_toggled)
	if is_instance_valid(reduce_motion_toggle):
		reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)


## Loads stored control preferences from GlobalSettings.
func load_settings() -> void:
	print("UI: Loading Controls settings.")
	_load_slider(
		mouse_sens_slider,
		mouse_sens_input,
		"mouse_sensitivity",
		DEFAULT_MOUSE_SENSITIVITY,
		"Controls"
	)
	_apply_mouse_sensitivity(
		(
			mouse_sens_slider.value
			if is_instance_valid(mouse_sens_slider)
			else DEFAULT_MOUSE_SENSITIVITY
		)
	)

	if is_instance_valid(invert_y_toggle):
		invert_y_toggle.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Controls", "invert_y", DEFAULT_INVERT_Y))
		)
	if is_instance_valid(toggle_crouch_button):
		toggle_crouch_button.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Controls", "toggle_crouch", DEFAULT_TOGGLE_CROUCH))
		)
	if is_instance_valid(toggle_sprint_button):
		toggle_sprint_button.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Controls", "toggle_sprint", DEFAULT_TOGGLE_SPRINT))
		)
	if is_instance_valid(cancel_crouch_jump_button):
		cancel_crouch_jump_button.set_pressed_no_signal(
			bool(
				GlobalSettings.get_setting(
					"Gameplay", "cancel_crouch_on_jump", DEFAULT_CANCEL_CROUCH_ON_JUMP
				)
			)
		)
	if is_instance_valid(aim_assist_toggle):
		aim_assist_toggle.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Gameplay", "aim_assist", DEFAULT_AIM_ASSIST))
		)

	_load_slider(
		aim_assist_slider,
		aim_assist_input,
		"aim_assist_amount",
		DEFAULT_AIM_ASSIST_AMOUNT,
		"Gameplay"
	)
	_load_slider(
		vibration_slider, vibration_input, "vibration_strength", DEFAULT_VIBRATION, "Gameplay"
	)

	if is_instance_valid(reduce_motion_toggle):
		reduce_motion_toggle.set_pressed_no_signal(
			bool(
				GlobalSettings.get_setting("Accessibility", "reduce_motion", DEFAULT_REDUCE_MOTION)
			)
		)


## Connects companion slider and LineEdit pairs with instant clear and revert on defocus.
## [param slider] The [HSlider] instance.
## [param input_box] The [LineEdit] instance.
## [param key] Setting key identifier.
## [param min_val] Minimum clamp limit.
## [param max_val] Maximum clamp limit.
## [param section] GlobalSettings section category.
## [param apply_cb] Optional callable triggered on numeric change.
func _connect_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	apply_cb: Callable = Callable()
) -> void:
	if is_instance_valid(slider):
		slider.min_value = min_val
		slider.max_value = max_val
		slider.value_changed.connect(
			func(val: float) -> void:
				if is_instance_valid(input_box) and not input_box.has_focus():
					input_box.text = "%.2f" % val
				if apply_cb.is_valid():
					apply_cb.call(val)
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
					var clamped_val: float = clampf(trimmed.to_float(), min_val, max_val)
					input_box.text = "%.2f" % clamped_val
					if is_instance_valid(slider):
						slider.value = clamped_val
					print("Player manually typed ", key, " input: ", clamped_val)
					GlobalSettings.save_setting(section, key, clamped_val)
					if apply_cb.is_valid():
						apply_cb.call(clamped_val)
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				var trimmed: String = input_box.text.strip_edges()
				var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
				if trimmed == "" or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var clamped_val: float = clampf(trimmed.to_float(), min_val, max_val)
					input_box.text = "%.2f" % clamped_val
					if is_instance_valid(slider):
						slider.value = clamped_val
					print("Player committed ", key, " input on defocus: ", clamped_val)
					GlobalSettings.save_setting(section, key, clamped_val)
					if apply_cb.is_valid():
						apply_cb.call(clamped_val)
		)


## Reads a float setting and synchronizes slider and LineEdit representations.
## [param slider] The target [HSlider] node.
## [param input_box] The target [LineEdit] node.
## [param key] Setting key identifier.
## [param default_val] Fallback float value.
## [param section] GlobalSettings category section.
func _load_slider(
	slider: HSlider, input_box: LineEdit, key: String, default_val: float, section: String
) -> void:
	if is_instance_valid(slider):
		var val: float = float(GlobalSettings.get_setting(section, key, default_val))
		slider.value = val
		if is_instance_valid(input_box):
			input_box.text = "%.2f" % val


## Applies mouse sensitivity settings to the player's camera controller.
## [param sens] Mouse sensitivity value.
func _apply_mouse_sensitivity(sens: float) -> void:
	print("Engine: Applying Mouse Sensitivity: ", sens)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and "camera_controller" in player and is_instance_valid(player.camera_controller):
		if player.camera_controller.has_method("set_mouse_sensitivity"):
			player.camera_controller.set_mouse_sensitivity(sens)
		else:
			player.camera_controller.mouse_sensitivity_base = sens
			player.camera_controller.mouse_sensitivity = sens


## Handles vertical axis inversion toggling.
## [param toggled_on] Enabled state.
func _on_invert_y_toggled(toggled_on: bool) -> void:
	print("Player toggled Invert Y to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "invert_y", toggled_on)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.invert_y = toggled_on


## Handles toggle crouch button mode setting.
## [param toggled_on] Enabled state.
func _on_toggle_crouch_toggled(toggled_on: bool) -> void:
	print("Player toggled Toggle Crouch to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "toggle_crouch", toggled_on)


## Handles toggle sprint button mode setting.
## [param toggled_on] Enabled state.
func _on_toggle_sprint_toggled(toggled_on: bool) -> void:
	print("Player toggled Toggle Sprint to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "toggle_sprint", toggled_on)


## Handles cancel crouch on jump setting.
## [param toggled_on] Enabled state.
func _on_cancel_crouch_jump_toggled(toggled_on: bool) -> void:
	print("Player toggled Cancel Crouch On Jump to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "cancel_crouch_on_jump", toggled_on)


## Handles aim assistance system toggling.
## [param toggled_on] Enabled state.
func _on_aim_assist_toggled(toggled_on: bool) -> void:
	print("Player toggled Aim Assist to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "aim_assist", toggled_on)


## Handles motion reduction toggle updates.
## [param toggled_on] Enabled state.
func _on_reduce_motion_toggled(toggled_on: bool) -> void:
	print("Player toggled Reduce Motion to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "reduce_motion", toggled_on)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.reduce_motion = toggled_on
