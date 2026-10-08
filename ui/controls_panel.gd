## Manages key remapping, mouse look sensitivity, aim assist, and behavior modes.
class_name ControlsPanel
extends Panel

## Structure mapping categories to project input actions.
const ACTION_CATEGORIES: Dictionary = {
	"Movement": ["forward", "backward", "left", "right", "jump", "crouch", "sprint"],
	"Interactions & Combat":
	[
		"interact",
		"shoot",
		"reload",
		"flashlight",
		"zoom",
		"weapon_slot_1",
		"weapon_slot_2",
		"weapon_slot_3",
		"weapon_slot_4",
		"weapon_slot_5",
		"last_weapon",
		"sonar_ping",
		"ttsandy",
		"describe_surroundings",
		"grenade_throw"
	],
	"UI & Navigation": ["exit"],
	"Developer Stuff": ["noclip", "console", "debug_menu"]
}

## Directory path for Kenney prompt icons.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## Actions requiring continuous key holding.
const HOLD_ACTIONS: Array[String] = ["ttsandy", "describe_surroundings"]

## Minimum hold threshold duration in seconds.
const HOLD_TIME_THRESHOLD: float = 0.45

## Time gap allowed between consecutive taps.
const MULTI_TAP_TIME_WINDOW: float = 0.30

## Tap count required to register mashing.
const MASH_THRESHOLD_COUNT: int = 3

## Time window allowed to complete a chord.
const CHORD_COMPLETION_WINDOW: float = 0.25

## Display size for prompt textures inside buttons.
@export var prompt_icon_size: Vector2 = Vector2(36.0, 36.0)

## Slider for mouse look sensitivity.
@onready var mouse_sens_slider: HSlider = %MouseSensitivitySlider

## LineEdit input for mouse sensitivity.
@onready var mouse_sens_input: LineEdit = %MouseSensitivityLine

## CheckButton for vertical axis inversion.
@onready var invert_y_toggle: CheckButton = %InvertYToggle

## CheckButton for enabling aim assist.
@onready var aim_assist_toggle: CheckButton = %AimAssistToggle

## Slider for adjusting aim assist strength.
@onready var aim_assist_slider: HSlider = %AimAssistSlider

## LineEdit input for aim assist strength.
@onready var aim_assist_input: LineEdit = %AimAssistLine

## Slider for controller vibration.
@onready var vibration_slider: HSlider = %VibrationSlider

## LineEdit input for vibration strength.
@onready var vibration_input: LineEdit = %VibrationLine

## Container holding categorized action rows.
@onready var action_list_container: VBoxContainer = %ActionListContainer

## GridContainer displaying table headers.
@onready var header_grid: GridContainer = %HeaderGrid

## Label displaying crouch setting text.
@onready var crouch_mode_label: Label = %CrouchModeLabel

## OptionButton for crouch toggle mode.
@onready var crouch_mode_option: OptionButton = %CrouchModeOption

## Label displaying sprint setting text.
@onready var sprint_mode_label: Label = %SprintModeLabel

## OptionButton for sprint toggle mode.
@onready var sprint_mode_option: OptionButton = %SprintModeOption

## Label displaying valve setting text.
@onready var valve_mode_label: Label = %ValveModeLabel

## OptionButton for valve turn mode.
@onready var valve_mode_option: OptionButton = %ValveModeOption

## Indicates active remapping state.
var is_remapping: bool = false

## Action key currently being remapped.
var action_to_remap: String = ""

## Active slot being edited (0 or 1).
var target_slot_index: int = 0

## Reference to active remapping button.
var remapping_button: Button = null

## Pending candidate event being tested.
var _pending_event: InputEvent = null

## List of chord input events.
var _chord_events: Array[InputEvent] = []

## Flag indicating candidate key press.
var _is_candidate_pressed: bool = false

## Hold detection timer accumulator.
var _hold_timer: float = 0.0

## Multi-tap detection timer accumulator.
var _multi_tap_timer: float = 0.0

## Chord completion timer accumulator.
var _chord_timer: float = 0.0

## Count of recorded sequential presses.
var _press_count: int = 0

## Cache mapping paths to loaded textures.
var _icon_cache: Dictionary = {}


## Configures UI listeners and builds the action rebind list in [method _ready].
func _ready() -> void:
	print("UI: Controls Panel initialized.")
	if is_instance_valid(crouch_mode_option):
		crouch_mode_option.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(sprint_mode_option):
		sprint_mode_option.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(valve_mode_option):
		valve_mode_option.focus_mode = Control.FOCUS_NONE

	_format_header_grid()
	_ensure_all_actions_registered()
	_setup_behavior_controls()
	_setup_mouse_aim_controls()
	_create_control_list()


## Monitors input gesture timers each frame while remapping is active.
func _process(delta: float) -> void:
	if not is_remapping or _pending_event == null:
		return

	if _chord_timer > 0.0:
		_chord_timer -= delta
		if _chord_timer <= 0.0 and _chord_events.size() > 1:
			print("System: Chord combination finalized.")
			_finalize_chord_remap()
			return

	if _is_candidate_pressed:
		_hold_timer += delta
		if _hold_timer >= HOLD_TIME_THRESHOLD:
			if _press_count >= 2:
				print("System: Double-Tap & Hold recognized.")
				_pending_event.set_meta("gesture", "double_tap_hold")
			else:
				print("System: Hold recognized.")
				_pending_event.set_meta("gesture", "hold")
			_finalize_gesture_remap(_pending_event)
	elif _multi_tap_timer > 0.0:
		_multi_tap_timer -= delta
		if _multi_tap_timer <= 0.0:
			if _press_count >= MASH_THRESHOLD_COUNT:
				print("System: Mash gesture recognized.")
				_pending_event.set_meta("gesture", "mash")
			elif _press_count == 2:
				print("System: Double-tap recognized.")
				_pending_event.set_meta("gesture", "double_tap")
			else:
				print("System: Single tap recognized.")
				_pending_event.set_meta("gesture", "single_tap")
			_finalize_gesture_remap(_pending_event)


## Connects and synchronizes mouse and aim input widgets.
func _setup_mouse_aim_controls() -> void:
	print("UI: Configuring Mouse & Aim sliders.")
	_connect_slider(
		mouse_sens_slider,
		mouse_sens_input,
		"mouse_sensitivity",
		0.05,
		5.0,
		"Controls",
		_apply_mouse_sensitivity
	)
	_connect_slider(aim_assist_slider, aim_assist_input, "aim_assist_amount", 0.0, 1.0, "Gameplay")
	_connect_slider(vibration_slider, vibration_input, "vibration_strength", 0.0, 2.0, "Gameplay")

	if is_instance_valid(invert_y_toggle):
		var inv: bool = GlobalSettings.get_setting_bool("Controls", "invert_y", false)
		invert_y_toggle.set_pressed_no_signal(inv)
		invert_y_toggle.toggled.connect(
			func(toggled_on: bool) -> void:
				print("Controls: Invert Y changed -> ", toggled_on)
				GlobalSettings.save_setting("Controls", "invert_y", toggled_on)
				_apply_invert_y(toggled_on)
		)

	if is_instance_valid(aim_assist_toggle):
		var aim: bool = GlobalSettings.get_setting_bool("Gameplay", "aim_assist", true)
		aim_assist_toggle.set_pressed_no_signal(aim)
		aim_assist_toggle.toggled.connect(
			func(toggled_on: bool) -> void:
				print("Controls: Aim Assist changed -> ", toggled_on)
				GlobalSettings.save_setting("Gameplay", "aim_assist", toggled_on)
		)

	_load_slider(mouse_sens_slider, mouse_sens_input, "mouse_sensitivity", 1.0, "Controls")
	_load_slider(aim_assist_slider, aim_assist_input, "aim_assist_amount", 0.5, "Gameplay")
	_load_slider(vibration_slider, vibration_input, "vibration_strength", 1.0, "Gameplay")
	_apply_mouse_sensitivity(
		mouse_sens_slider.value if is_instance_valid(mouse_sens_slider) else 1.0
	)


## Retrieves the active [CameraController] node from the player group safely.
func _get_camera_controller() -> CameraController:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if not is_instance_valid(player):
		return null
	var controller_val: Variant = player.get(&"camera_controller")
	if controller_val is CameraController:
		var camera_node: CameraController = controller_val
		if is_instance_valid(camera_node):
			return camera_node
	return null


## Applies mouse sensitivity settings to player camera controller.
func _apply_mouse_sensitivity(sens: float) -> void:
	print("Engine: Applying Mouse Sensitivity: ", sens)
	var controller: CameraController = _get_camera_controller()
	if is_instance_valid(controller):
		controller.set_mouse_sensitivity(sens)


## Applies vertical camera look inversion to player camera controller.
func _apply_invert_y(inverted: bool) -> void:
	print("Engine: Applying Invert Y: ", inverted)
	var controller: CameraController = _get_camera_controller()
	if is_instance_valid(controller):
		controller.invert_y = inverted


## Connects companion slider and LineEdit pairs with synchronized validation.
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
					print("Controls: Saved ", key, " -> ", slider.value)
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
				if trimmed.is_empty() or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var c_val: float = clampf(trimmed.to_float(), min_val, max_val)
					input_box.text = "%.2f" % c_val
					print("Controls: Manually entered ", key, " -> ", c_val)
					GlobalSettings.save_setting(section, key, c_val)
					if is_instance_valid(slider):
						slider.value = c_val
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				var trimmed: String = input_box.text.strip_edges()
				var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
				if trimmed.is_empty() or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var c_val: float = clampf(trimmed.to_float(), min_val, max_val)
					input_box.text = "%.2f" % c_val
					if is_instance_valid(slider):
						if not is_equal_approx(slider.value, c_val):
							print("Controls: Saved ", key, " on defocus: ", c_val)
							GlobalSettings.save_setting(section, key, c_val)
							slider.value = c_val
		)


## Reads a float setting and synchronizes slider without firing change signals.
func _load_slider(
	slider: HSlider, input_box: LineEdit, key: String, default_val: float, section: String
) -> void:
	if is_instance_valid(slider):
		var val: float = GlobalSettings.get_setting_float(section, key, default_val)
		slider.set_value_no_signal(val)
		if is_instance_valid(input_box):
			input_box.text = "%.2f" % val


## Formats the 5-column header grid and creates missing reset headers.
func _format_header_grid() -> void:
	print("UI: Formatting controls header grid.")
	if not is_instance_valid(header_grid):
		return
	header_grid.columns = 5
	header_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var labels: Array[Node] = header_grid.get_children()
	if labels.is_empty():
		return

	var reset_primary_header: Label = (
		header_grid.get_node_or_null("ColClearPrimary")
		if header_grid.get_node_or_null("ColClearPrimary") is Label
		else null
	)
	if reset_primary_header == null:
		reset_primary_header = Label.new()
		reset_primary_header.name = "ColClearPrimary"
		header_grid.add_child(reset_primary_header)

	var action_header: Label = (
		header_grid.get_node_or_null("ColAction")
		if header_grid.get_node_or_null("ColAction") is Label
		else null
	)
	var primary_header: Label = (
		header_grid.get_node_or_null("ColPrimary")
		if header_grid.get_node_or_null("ColPrimary") is Label
		else null
	)
	var secondary_header: Label = (
		header_grid.get_node_or_null("ColSecondary")
		if header_grid.get_node_or_null("ColSecondary") is Label
		else null
	)
	var reset_secondary_header: Label = (
		header_grid.get_node_or_null("ColClear")
		if header_grid.get_node_or_null("ColClear") is Label
		else null
	)

	if is_instance_valid(action_header):
		header_grid.move_child(action_header, 0)
		action_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_header.size_flags_stretch_ratio = 2.0
		action_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	if is_instance_valid(primary_header):
		header_grid.move_child(primary_header, 1)
		primary_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary_header.size_flags_stretch_ratio = 2.0
		primary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(reset_primary_header):
		header_grid.move_child(reset_primary_header, 2)
		reset_primary_header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reset_primary_header.custom_minimum_size = Vector2(40.0, 0.0)
		reset_primary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if is_instance_valid(reset_secondary_header):
			reset_primary_header.theme_type_variation = (
				reset_secondary_header.theme_type_variation
			)
			reset_primary_header.text = reset_secondary_header.text

	if is_instance_valid(secondary_header):
		header_grid.move_child(secondary_header, 3)
		secondary_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		secondary_header.size_flags_stretch_ratio = 2.0
		secondary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_instance_valid(reset_secondary_header):
		header_grid.move_child(reset_secondary_header, 4)
		reset_secondary_header.size_flags_horizontal = (Control.SIZE_SHRINK_CENTER)
		reset_secondary_header.custom_minimum_size = Vector2(40.0, 0.0)
		reset_secondary_header.horizontal_alignment = (HORIZONTAL_ALIGNMENT_CENTER)


## Ensures all defined actions exist in [InputMap].
func _ensure_all_actions_registered() -> void:
	print("ControlsPanel: Verifying action mappings in InputMap.")
	for category: String in ACTION_CATEGORIES.keys():
		for action: String in ACTION_CATEGORIES[category]:
			if not InputMap.has_action(action):
				print("System: Registering missing action: ", action)
				InputMap.add_action(action)


## Configures behavior dropdowns for crouch, sprint, and valve interactions.
func _setup_behavior_controls() -> void:
	print("UI: Configuring Input Behavior dropdowns.")
	if is_instance_valid(crouch_mode_label):
		crouch_mode_label.text = "Crouch Mode"
	if is_instance_valid(sprint_mode_label):
		sprint_mode_label.text = "Sprint Mode"
	if is_instance_valid(valve_mode_label):
		valve_mode_label.text = "Valve Turn Mode"

	if is_instance_valid(crouch_mode_option):
		crouch_mode_option.clear()
		crouch_mode_option.add_item("Hold", 0)
		crouch_mode_option.add_item("Toggle", 1)
		var sc_val: Variant = GlobalSettings.get_setting("Gameplay", "crouch_mode", "Hold")
		var sc: String = "Hold"
		if sc_val is String:
			sc = sc_val
		crouch_mode_option.selected = 1 if sc == "Toggle" else 0
		crouch_mode_option.item_selected.connect(
			func(idx: int) -> void:
				var m: String = crouch_mode_option.get_item_text(idx)
				print("Settings: Changed Crouch Mode -> ", m)
				GlobalSettings.save_setting("Gameplay", "crouch_mode", m)
		)

	if is_instance_valid(sprint_mode_option):
		sprint_mode_option.clear()
		sprint_mode_option.add_item("Hold", 0)
		sprint_mode_option.add_item("Toggle", 1)
		var ss_val: Variant = GlobalSettings.get_setting("Gameplay", "sprint_mode", "Hold")
		var ss: String = "Hold"
		if ss_val is String:
			ss = ss_val
		sprint_mode_option.selected = 1 if ss == "Toggle" else 0
		sprint_mode_option.item_selected.connect(
			func(idx: int) -> void:
				var m: String = sprint_mode_option.get_item_text(idx)
				print("Settings: Changed Sprint Mode -> ", m)
				GlobalSettings.save_setting("Gameplay", "sprint_mode", m)
		)

	if is_instance_valid(valve_mode_option):
		valve_mode_option.clear()
		valve_mode_option.add_item("Hold", 0)
		valve_mode_option.add_item("One-Time Press", 1)
		valve_mode_option.add_item("Rapid Mash", 2)
		var sv_val: Variant = GlobalSettings.get_setting("Gameplay", "valve_turn_mode", "Hold")
		var sv: String = "Hold"
		if sv_val is String:
			sv = sv_val
		match sv:
			"One-Time Press":
				valve_mode_option.selected = 1
			"Rapid Mash":
				valve_mode_option.selected = 2
			_:
				valve_mode_option.selected = 0
		valve_mode_option.item_selected.connect(
			func(idx: int) -> void:
				var m: String = valve_mode_option.get_item_text(idx)
				print("Settings: Changed Valve Mode -> ", m)
				GlobalSettings.save_setting("Gameplay", "valve_turn_mode", m)
		)


## Generates action list remapping items grouped by category.
func _create_control_list() -> void:
	if not is_instance_valid(action_list_container):
		return
	print("UI: Building categorized controls list.")
	for child: Node in action_list_container.get_children():
		child.queue_free()

	for category: String in ACTION_CATEGORIES.keys():
		var category_title: Label = Label.new()
		category_title.text = category
		category_title.theme_type_variation = "HeaderMedium"
		action_list_container.add_child(category_title)

		var grid: GridContainer = GridContainer.new()
		grid.columns = 5
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_list_container.add_child(grid)

		var actions: Array = ACTION_CATEGORIES[category]
		for action: String in actions:
			_create_action_row(grid, action)


## Creates a rebind row with primary and secondary slots.
func _create_action_row(parent_grid: GridContainer, action: String) -> void:
	var action_label: Label = Label.new()
	action_label.text = action.replace("_", " ").capitalize()
	action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_label.size_flags_stretch_ratio = 2.0
	parent_grid.add_child(action_label)

	var primary_btn: Button = Button.new()
	primary_btn.focus_mode = Control.FOCUS_NONE
	primary_btn.toggle_mode = true
	primary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary_btn.size_flags_stretch_ratio = 2.0
	primary_btn.set_meta("action", action)
	primary_btn.set_meta("slot", 0)
	primary_btn.toggled.connect(_on_remap_button_toggled.bind(primary_btn, action, 0))
	parent_grid.add_child(primary_btn)

	var clear_primary_btn: Button = Button.new()
	clear_primary_btn.focus_mode = Control.FOCUS_NONE
	clear_primary_btn.text = "✕"
	clear_primary_btn.custom_minimum_size = Vector2(40.0, 0.0)
	clear_primary_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clear_primary_btn.tooltip_text = "Clear primary binding"
	parent_grid.add_child(clear_primary_btn)

	var secondary_btn: Button = Button.new()
	secondary_btn.focus_mode = Control.FOCUS_NONE
	secondary_btn.toggle_mode = true
	secondary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secondary_btn.size_flags_stretch_ratio = 2.0
	secondary_btn.set_meta("action", action)
	secondary_btn.set_meta("slot", 1)
	secondary_btn.toggled.connect(_on_remap_button_toggled.bind(secondary_btn, action, 1))
	parent_grid.add_child(secondary_btn)

	var clear_secondary_btn: Button = Button.new()
	clear_secondary_btn.focus_mode = Control.FOCUS_NONE
	clear_secondary_btn.text = "✕"
	clear_secondary_btn.custom_minimum_size = Vector2(40.0, 0.0)
	clear_secondary_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clear_secondary_btn.tooltip_text = "Clear secondary binding"
	parent_grid.add_child(clear_secondary_btn)

	clear_primary_btn.pressed.connect(
		_on_clear_slot_pressed.bind(action, 0, primary_btn, secondary_btn)
	)
	clear_secondary_btn.pressed.connect(
		_on_clear_slot_pressed.bind(action, 1, primary_btn, secondary_btn)
	)

	_update_slot_button_text(primary_btn, action, 0)
	_update_slot_button_text(secondary_btn, action, 1)


## Clears an event slot binding and syncs UI buttons.
func _on_clear_slot_pressed(
	action: String, slot_index: int, primary_btn: Button, secondary_btn: Button
) -> void:
	print("UI: Player cleared slot ", slot_index, " for action: ", action)
	if is_remapping:
		if remapping_button == primary_btn or remapping_button == secondary_btn:
			remapping_button.button_pressed = false

	if InputMap.has_action(action):
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if slot_index == 0 and events.size() > 0:
			events.remove_at(0)
		elif slot_index == 1 and events.size() > 1:
			events.remove_at(1)

		InputMap.action_erase_events(action)
		for ev: InputEvent in events:
			InputMap.action_add_event(action, ev)

	_save_action_mapping(action)
	_update_slot_button_text(primary_btn, action, 0)
	_update_slot_button_text(secondary_btn, action, 1)


## Normalizes input string names.
func _sanitize_key_name(raw_text: String) -> String:
	var clean: String = raw_text
	clean = clean.replace(" - Physical", "")
	clean = clean.replace(" (Physical)", "")
	clean = clean.replace("Physical ", "")
	return clean.strip_edges()


## Constructs an [InputEvent] from an integer ID.
func _create_event_from_id(event_id: int) -> InputEvent:
	if event_id >= 100000:
		var mouse_ev: InputEventMouseButton = InputEventMouseButton.new()
		mouse_ev.button_index = (event_id - 100000) as MouseButton
		return mouse_ev
	var key_ev: InputEventKey = InputEventKey.new()
	key_ev.physical_keycode = event_id as Key
	return key_ev


## Builds an icon or text control for an event.
func _create_event_display_node(event: InputEvent) -> Control:
	var icon_tex: Texture2D = _get_event_icon(event)
	if icon_tex != null:
		var tex_rect: TextureRect = TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = prompt_icon_size
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tex_rect
	var lbl: Label = Label.new()
	lbl.text = _sanitize_key_name(event.as_text())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## Updates display layout and icons on a slot button.
func _update_slot_button_text(button: Button, action: String, slot_index: int) -> void:
	if not is_instance_valid(button):
		return
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var existing_container: Node = button.get_node_or_null("PreviewContainer")
	if existing_container != null:
		existing_container.queue_free()

	button.icon = null
	button.text = ""

	if events.size() <= slot_index:
		button.text = "—"
		return

	var target_ev: InputEvent = events[slot_index]
	var gesture: String = ""
	if target_ev.has_meta("gesture"):
		var raw_gesture: Variant = target_ev.get_meta("gesture")
		if raw_gesture is String:
			gesture = raw_gesture

	var container: HBoxContainer = HBoxContainer.new()
	container.name = "PreviewContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", 6)
	button.add_child(container)

	var prefix: String = ""
	if gesture == "hold" or action in HOLD_ACTIONS:
		prefix = "Hold"
	elif gesture == "double_tap":
		prefix = "2x"
	elif gesture == "double_tap_hold":
		prefix = "2x Hold"
	elif gesture == "mash":
		prefix = "Mash"

	if not prefix.is_empty():
		var prefix_label: Label = Label.new()
		prefix_label.text = prefix
		prefix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(prefix_label)

	if target_ev.has_meta("chord_keys"):
		var raw_keys: Variant = target_ev.get_meta("chord_keys")
		var keys_array: Array = []
		if raw_keys is Array:
			keys_array = raw_keys
		var is_ordered: bool = gesture == "ordered_chord"
		for i: int in range(keys_array.size()):
			var key_val: Variant = keys_array[i]
			var key_id: int = 0
			if key_val is int:
				key_id = key_val
			var ev: InputEvent = _create_event_from_id(key_id)
			container.add_child(_create_event_display_node(ev))
			if i < keys_array.size() - 1:
				var sep: Label = Label.new()
				sep.text = " → " if is_ordered else " + "
				sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
				container.add_child(sep)
	else:
		container.add_child(_create_event_display_node(target_ev))


## Handles remapping button click to listen for hardware inputs.
func _on_remap_button_toggled(
	toggled_on: bool, button: Button, action: String, slot_index: int
) -> void:
	if not is_instance_valid(button):
		return
	var existing_container: Node = button.get_node_or_null("PreviewContainer")
	if existing_container != null:
		existing_container.queue_free()

	if toggled_on:
		print("UI: Remap started for: ", action, " [Slot ", slot_index, "]")
		if is_instance_valid(remapping_button) and remapping_button != button:
			remapping_button.button_pressed = false

		is_remapping = true
		remapping_button = button
		action_to_remap = action
		target_slot_index = slot_index
		_reset_gesture_state()
		button.icon = null
		button.text = "Press, Hold, 2x, Mash, or Chord..."
	else:
		print("UI: Remap canceled for: ", action)
		if remapping_button == button:
			is_remapping = false
			remapping_button = null
			_reset_gesture_state()
		_update_slot_button_text(button, action, slot_index)


## Resets gesture recognition variables.
func _reset_gesture_state() -> void:
	print("System: Resetting gesture state.")
	_pending_event = null
	_chord_events.clear()
	_is_candidate_pressed = false
	_hold_timer = 0.0
	_multi_tap_timer = 0.0
	_chord_timer = 0.0
	_press_count = 0


## Checks if two events correspond to identical hardware keys.
func _is_same_input(ev1: InputEvent, ev2: InputEvent) -> bool:
	if ev1 is InputEventKey and ev2 is InputEventKey:
		var k1: InputEventKey = ev1
		var k2: InputEventKey = ev2
		if k1.physical_keycode != KEY_NONE and k2.physical_keycode != KEY_NONE:
			return k1.physical_keycode == k2.physical_keycode
		return k1.keycode == k2.keycode
	if ev1 is InputEventMouseButton and ev2 is InputEventMouseButton:
		var m1: InputEventMouseButton = ev1
		var m2: InputEventMouseButton = ev2
		return m1.button_index == m2.button_index
	return false


## Generates unique identifier for event types.
func _get_unique_event_id(event: InputEvent) -> int:
	if event is InputEventKey:
		var k: InputEventKey = event
		return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if event is InputEventMouseButton:
		return 100000 + (event as InputEventMouseButton).button_index
	return -1


## Captures incoming input events during remapping.
func _input(event: InputEvent) -> void:
	if not visible or not is_remapping:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.is_echo():
			return
		var clean_key: InputEventKey = InputEventKey.new()
		clean_key.physical_keycode = key_event.physical_keycode
		clean_key.keycode = key_event.keycode
		_process_gesture_event(clean_key, key_event.is_pressed())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		var clean_mouse: InputEventMouseButton = InputEventMouseButton.new()
		clean_mouse.button_index = mouse_event.button_index
		_process_gesture_event(clean_mouse, mouse_event.is_pressed())
		get_viewport().set_input_as_handled()


## Feeds cleaned input event into gesture detection pipeline.
func _process_gesture_event(clean_event: InputEvent, is_pressed: bool) -> void:
	if is_pressed:
		var exists: bool = false
		for ev: InputEvent in _chord_events:
			if _is_same_input(ev, clean_event):
				exists = true
				break
		if not exists:
			_chord_events.append(clean_event)

		if _chord_events.size() > 1:
			_chord_timer = CHORD_COMPLETION_WINDOW
			if is_instance_valid(remapping_button):
				remapping_button.text = "Chord detecting..."
			return

		if _pending_event == null or not _is_same_input(_pending_event, clean_event):
			_pending_event = clean_event
			_press_count = 1
			_is_candidate_pressed = true
			_hold_timer = 0.0
			_multi_tap_timer = 0.0
			if is_instance_valid(remapping_button):
				remapping_button.text = "Holding..."
		else:
			_press_count += 1
			_is_candidate_pressed = true
			_hold_timer = 0.0
			if _press_count >= MASH_THRESHOLD_COUNT:
				_multi_tap_timer = MULTI_TAP_TIME_WINDOW
				if is_instance_valid(remapping_button):
					remapping_button.text = ("Mashing (" + str(_press_count) + ")...")
			elif _press_count == 2:
				if is_instance_valid(remapping_button):
					remapping_button.text = "Holding 2x..."
	else:
		if _chord_events.size() > 1:
			return
		if _is_candidate_pressed and _pending_event != null:
			_is_candidate_pressed = false
			if _hold_timer < HOLD_TIME_THRESHOLD:
				_multi_tap_timer = MULTI_TAP_TIME_WINDOW
				if is_instance_valid(remapping_button):
					remapping_button.text = "Waiting next tap..."


## Finalizes chord keys sequence binding.
func _finalize_chord_remap() -> void:
	var base_event: InputEvent = _chord_events[_chord_events.size() - 1]
	var key_ids: Array[int] = []
	for ev: InputEvent in _chord_events:
		key_ids.append(_get_unique_event_id(ev))
	base_event.set_meta("gesture", "ordered_chord")
	base_event.set_meta("chord_keys", key_ids)
	_finalize_gesture_remap(base_event)


## Stores finalized event into slot and flushes changes.
func _finalize_gesture_remap(new_event: InputEvent) -> void:
	_assign_event_to_action_slot(action_to_remap, target_slot_index, new_event)
	var active_btn: Button = remapping_button
	is_remapping = false
	remapping_button = null
	_reset_gesture_state()
	_save_action_mapping(action_to_remap)
	if is_instance_valid(active_btn):
		active_btn.button_pressed = false


## Assigns an event directly to an action slot.
func _assign_event_to_action_slot(action: String, slot_index: int, new_event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if slot_index == 0:
		if events.is_empty():
			InputMap.action_add_event(action, new_event)
		else:
			events[0] = new_event
			InputMap.action_erase_events(action)
			for ev: InputEvent in events:
				InputMap.action_add_event(action, ev)
	elif slot_index == 1:
		if events.is_empty() or events.size() == 1:
			InputMap.action_add_event(action, new_event)
		else:
			events[1] = new_event
			InputMap.action_erase_events(action)
			for ev: InputEvent in events:
				InputMap.action_add_event(action, ev)


## Resets all bindings to ProjectSettings defaults.
func reset_to_defaults() -> void:
	print("UI: ControlsPanel -> Executing reset to default.")
	InputMap.load_from_project_settings()
	for category: String in ACTION_CATEGORIES.keys():
		for action: String in ACTION_CATEGORIES[category]:
			_save_action_mapping(action)
	if is_instance_valid(action_list_container):
		var grids: Array[Node] = action_list_container.find_children(
			"", "GridContainer", true, false
		)
		for grid: Node in grids:
			for child: Node in grid.get_children():
				if child is Button and child.has_meta("slot"):
					var btn: Button = child
					var action_meta: Variant = btn.get_meta("action")
					var slot_meta: Variant = btn.get_meta("slot")
					var action_name: String = ""
					if action_meta is String:
						action_name = action_meta
					var slot_id: int = 0
					if slot_meta is int:
						slot_id = slot_meta
					_update_slot_button_text(btn, action_name, slot_id)


## Persists a single modified action mapping.
func _save_action_mapping(action: String) -> void:
	print("System: Saving action mapping for: ", action)
	if InputMap.has_action(action):
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		GlobalSettings.save_setting("Controls", action, events)


## Resolves input prompt textures from cache or disk.
func _get_event_icon(event: InputEvent) -> Texture2D:
	var filenames: Array[String] = []
	if event is InputEventKey:
		var code: Key = (
			(event as InputEventKey).physical_keycode
			if (event as InputEventKey).physical_keycode != KEY_NONE
			else (event as InputEventKey).keycode
		)
		var key_str: String = OS.get_keycode_string(code).to_lower()
		match code:
			KEY_SPACE:
				filenames.append("keyboard_space.png")
			KEY_ENTER:
				filenames.append("keyboard_return.png")
			KEY_SHIFT:
				filenames.append("keyboard_shift.png")
			KEY_CTRL:
				filenames.append("keyboard_ctrl.png")
			KEY_ALT:
				filenames.append("keyboard_alt.png")
			KEY_TAB:
				filenames.append("keyboard_tab.png")
			KEY_ESCAPE:
				filenames.append("keyboard_escape.png")
			_:
				if key_str.length() == 1:
					filenames.append("keyboard_%s.png" % key_str)
	elif event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				filenames.append("mouse_left.png")
			MOUSE_BUTTON_RIGHT:
				filenames.append("mouse_right.png")
			MOUSE_BUTTON_MIDDLE:
				filenames.append("mouse_middle.png")

	for fname: String in filenames:
		var paths: Array[String] = [
			ICON_BASE_PATH + fname,
			ICON_BASE_PATH + "Keyboard/" + fname,
			ICON_BASE_PATH + "Mouse/" + fname
		]
		for p: String in paths:
			if _icon_cache.has(p):
				var cached: Variant = _icon_cache[p]
				if cached is Texture2D:
					return cached
				return null
			if ResourceLoader.exists(p):
				var res: Resource = load(p)
				var tex: Texture2D = null
				if res is Texture2D:
					tex = res
				_icon_cache[p] = tex
				return tex
	return null
