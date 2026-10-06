## Controls mouse look, key toggles, vibration, and aim assistance.
class_name AccessibilityControlsSection
extends GridContainer

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Default constant value for mouse look sensitivity.
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

## Default constant value for crouch toggle behavior.
const DEFAULT_TOGGLE_CROUCH: bool = false

## Default constant value for sprint toggle behavior.
const DEFAULT_TOGGLE_SPRINT: bool = false

## Default constant value for canceling crouch on jump.
const DEFAULT_CANCEL_CROUCH_ON_JUMP: bool = true

## Default constant value for infinite swim accessibility toggle.
const DEFAULT_INFINITE_SWIM: bool = false

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Slider for adjusting mouse look sensitivity.
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

## Toggle switch for screen motion and shake reduction.
@onready var reduce_motion_toggle: CheckButton = get_node_or_null("%ReduceMotionToggle")

## Toggle switch for unlimited underwater oxygen.
@onready var infinite_swim_toggle: CheckButton = _resolve_swim_toggle()


## Lifecycle initialization method connecting controls inputs and loading preferences.
func _ready() -> void:
	print("UI: Initializing Controls Section.")
	_connect_signals()
	load_settings()


## Resolves the infinite swim CheckButton with fallback searching.
func _resolve_swim_toggle() -> CheckButton:
	var btn: CheckButton = get_node_or_null("%InfiniteSwimToggle") as CheckButton
	if not is_instance_valid(btn):
		btn = find_child("InfiniteSwimToggle", true, false) as CheckButton
	if not is_instance_valid(btn):
		push_error("AccessibilityControlsSection: Could not find InfiniteSwimToggle node!")
	return btn


## Connects interactive controls inputs and slider listeners.
func _connect_signals() -> void:
	print("UI: Binding controls section input signals.")
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
	if is_instance_valid(infinite_swim_toggle):
		if not infinite_swim_toggle.toggled.is_connected(_on_infinite_swim_toggled):
			infinite_swim_toggle.toggled.connect(_on_infinite_swim_toggled)


## Loads stored control preferences from [GlobalSettings] silently.
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
		var invert: bool = bool(
			GlobalSettings.get_setting("Controls", "invert_y", DEFAULT_INVERT_Y)
		)
		invert_y_toggle.set_pressed_no_signal(invert)

	if is_instance_valid(toggle_crouch_button):
		var crouch: bool = bool(
			GlobalSettings.get_setting("Controls", "toggle_crouch", DEFAULT_TOGGLE_CROUCH)
		)
		toggle_crouch_button.set_pressed_no_signal(crouch)

	if is_instance_valid(toggle_sprint_button):
		var sprint: bool = bool(
			GlobalSettings.get_setting("Controls", "toggle_sprint", DEFAULT_TOGGLE_SPRINT)
		)
		toggle_sprint_button.set_pressed_no_signal(sprint)

	if is_instance_valid(cancel_crouch_jump_button):
		var cancel_jump: bool = bool(
			GlobalSettings.get_setting(
				"Gameplay", "cancel_crouch_on_jump", DEFAULT_CANCEL_CROUCH_ON_JUMP
			)
		)
		cancel_crouch_jump_button.set_pressed_no_signal(cancel_jump)

	if is_instance_valid(aim_assist_toggle):
		var aim: bool = bool(
			GlobalSettings.get_setting("Gameplay", "aim_assist", DEFAULT_AIM_ASSIST)
		)
		aim_assist_toggle.set_pressed_no_signal(aim)

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
		var reduce: bool = bool(
			GlobalSettings.get_setting("Accessibility", "reduce_motion", DEFAULT_REDUCE_MOTION)
		)
		reduce_motion_toggle.set_pressed_no_signal(reduce)

	if is_instance_valid(infinite_swim_toggle):
		var inf_swim: bool = bool(
			GlobalSettings.get_setting("Accessibility", "infinite_swim", DEFAULT_INFINITE_SWIM)
		)
		infinite_swim_toggle.set_pressed_no_signal(inf_swim)


## Connects slider and [LineEdit] pairs with throttled commit logic.
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
				if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					_commit_control_slider_val(key, val, section, apply_cb)
		)
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					print("Player adjusted ", key, " to: ", slider.value)
					_commit_control_slider_val(key, slider.value, section, apply_cb)
		)

	if is_instance_valid(input_box):
		input_box.focus_entered.connect(
			func() -> void:
				input_box.set_meta("pre_focus_text", input_box.text)
				input_box.text = ""
		)
		input_box.text_submitted.connect(
			func(_txt: String) -> void:
				_commit_control_line_edit(
					slider, input_box, key, min_val, max_val, section, apply_cb
				)
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				_commit_control_line_edit(
					slider, input_box, key, min_val, max_val, section, apply_cb
				)
		)


## Commits control slider value to settings and triggers callback if modified.
func _commit_control_slider_val(
	key: String, val: float, section: String, apply_cb: Callable
) -> void:
	var current: float = float(GlobalSettings.get_setting(section, key, -999.0))
	if not is_equal_approx(current, val):
		GlobalSettings.save_setting(section, key, val)
		if apply_cb.is_valid():
			apply_cb.call(val)


## Commits LineEdit input to control slider and storage safely.
func _commit_control_line_edit(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	apply_cb: Callable
) -> void:
	var trimmed: String = input_box.text.strip_edges()
	var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		input_box.text = fallback
		return

	var clamped_val: float = clampf(trimmed.to_float(), min_val, max_val)
	var formatted: String = "%.2f" % clamped_val
	input_box.text = formatted
	input_box.set_meta("pre_focus_text", formatted)

	if is_instance_valid(slider):
		slider.set_value_no_signal(clamped_val)

	_commit_control_slider_val(key, clamped_val, section, apply_cb)


## Reads a float setting and synchronizes slider without signals.
func _load_slider(
	slider: HSlider, input_box: LineEdit, key: String, default_val: float, section: String
) -> void:
	if is_instance_valid(slider):
		var val: float = float(GlobalSettings.get_setting(section, key, default_val))
		slider.set_value_no_signal(val)
		if is_instance_valid(input_box):
			input_box.text = "%.2f" % val


## Retrieves the active [CameraController] node from the player group safely.
func _get_camera_controller() -> CameraController:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if not is_instance_valid(player):
		return null
	var controller_val: Variant = player.get(&"camera_controller")
	if controller_val is CameraController and is_instance_valid(controller_val):
		return controller_val as CameraController
	return null


## Applies mouse sensitivity settings to player camera controller.
func _apply_mouse_sensitivity(sens: float) -> void:
	print("Engine: Applying Mouse Sensitivity: ", sens)
	var controller: CameraController = _get_camera_controller()
	if is_instance_valid(controller):
		controller.set_mouse_sensitivity(sens)


## Handles vertical axis inversion toggling.
func _on_invert_y_toggled(toggled_on: bool) -> void:
	var current: bool = bool(GlobalSettings.get_setting("Controls", "invert_y", DEFAULT_INVERT_Y))
	if current == toggled_on:
		return

	print("Player toggled Invert Y to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "invert_y", toggled_on)
	var controller: CameraController = _get_camera_controller()
	if is_instance_valid(controller):
		controller.invert_y = toggled_on


## Handles toggle crouch button mode setting.
func _on_toggle_crouch_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Controls", "toggle_crouch", DEFAULT_TOGGLE_CROUCH)
	)
	if current == toggled_on:
		return

	print("Player toggled Toggle Crouch to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "toggle_crouch", toggled_on)


## Handles toggle sprint button mode setting.
func _on_toggle_sprint_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Controls", "toggle_sprint", DEFAULT_TOGGLE_SPRINT)
	)
	if current == toggled_on:
		return

	print("Player toggled Toggle Sprint to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "toggle_sprint", toggled_on)


## Handles cancel crouch on jump setting.
func _on_cancel_crouch_jump_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting(
			"Gameplay", "cancel_crouch_on_jump", DEFAULT_CANCEL_CROUCH_ON_JUMP
		)
	)
	if current == toggled_on:
		return

	print("Player toggled Cancel Crouch On Jump to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "cancel_crouch_on_jump", toggled_on)


## Handles aim assistance system toggling.
func _on_aim_assist_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Gameplay", "aim_assist", DEFAULT_AIM_ASSIST)
	)
	if current == toggled_on:
		return

	print("Player toggled Aim Assist to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "aim_assist", toggled_on)


## Handles motion reduction toggle updates.
func _on_reduce_motion_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "reduce_motion", DEFAULT_REDUCE_MOTION)
	)
	if current == toggled_on:
		return

	print("Player toggled Reduce Motion to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "reduce_motion", toggled_on)
	var controller: CameraController = _get_camera_controller()
	if is_instance_valid(controller):
		controller.reduce_motion = toggled_on


## Handles infinite swim toggle updates and broadcasts state changes.
func _on_infinite_swim_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "infinite_swim", DEFAULT_INFINITE_SWIM)
	)
	if current == toggled_on:
		return

	print("Player toggled Infinite Swim to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "infinite_swim", toggled_on, true)
	Events.infinite_swim_toggled.emit(toggled_on)
