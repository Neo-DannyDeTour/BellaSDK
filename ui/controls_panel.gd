## Manages player key remapping UI, multi-slot bindings, categories, and behavior settings.
## Supports single-tap, hold-to-activate, and double-tap gesture binding detection.
class_name ControlsPanel
extends Panel

## Structure mapping categories to exact ProjectSettings InputMap action names.
const ACTION_CATEGORIES: Dictionary = {
	"Movement": ["forward", "backward", "left", "right", "jump", "crouch", "sprint"],
	"Interactions & Combat":
	[
		"interact",
		"shoot",
		"flashlight",
		"zoom",
		"sonar_ping",
		"ttsandy",
		"describe_surroundings",
		"grenade_throw"
	],
	"UI & Navigation": ["exit"],
	"Developer Stuff": ["noclip", "console", "debug_menu"]
}

## List of actions that are inherently hold-activated by design.
const HOLD_ACTIONS: Array[String] = ["ttsandy", "describe_surroundings"]

## Duration in seconds a button must be held down to be registered as a Hold binding.
const HOLD_TIME_THRESHOLD: float = 0.45

## Maximum time gap in seconds between consecutive presses to register as a Double Tap binding.
const DOUBLE_TAP_TIME_WINDOW: float = 0.30

## Indicates if the player is currently pressing a key to remap an action.
var is_remapping: bool = false

## The specific input action string currently being remapped.
var action_to_remap: String = ""

## The target event index being remapped (0 for Primary, 1 for Secondary).
var target_slot_index: int = 0

## Reference to the UI button currently waiting for player input.
var remapping_button: Button = null

## The candidate input event currently being evaluated for gestures.
var _pending_event: InputEvent = null

## Tracks whether the candidate key or mouse button is currently held down.
var _is_candidate_pressed: bool = false

## Countdown timer tracking hold duration.
var _hold_timer: float = 0.0

## Countdown timer tracking double-tap detection window.
var _double_tap_timer: float = 0.0

## Tracks how many times the candidate button was tapped within the detection window.
var _press_count: int = 0

## Container holding the categorized action list.
@onready var action_list_container: VBoxContainer = %ActionListContainer

## GridContainer displaying column headers (Action, Primary, Secondary, Reset).
@onready var header_grid: GridContainer = %HeaderGrid

## Reference to the [Label] indicating the crouch behavior setting.
@onready var crouch_mode_label: Label = %CrouchModeLabel

## Reference to the [OptionButton] dropdown for crouch input behavior mode.
@onready var crouch_mode_option: OptionButton = %CrouchModeOption

## Reference to the [Label] indicating the sprint behavior setting.
@onready var sprint_mode_label: Label = %SprintModeLabel

## Option dropdown for Sprint input behavior mode.
@onready var sprint_mode_option: OptionButton = %SprintModeOption


## Lifecycle method called when the node enters the scene tree.
## Builds the complete remapping interface and registers behavior toggles.
func _ready() -> void:
	print("UI: Controls Panel initialized.")

	if crouch_mode_option:
		crouch_mode_option.focus_mode = Control.FOCUS_NONE

	if sprint_mode_option:
		sprint_mode_option.focus_mode = Control.FOCUS_NONE

	_format_header_grid()
	_ensure_all_actions_registered()
	_setup_behavior_controls()
	_create_control_list()


## Frame lifecycle method monitoring gesture recognition timers while remapping.
## [param delta] Elapsed time since the previous frame in seconds.
func _process(delta: float) -> void:
	if not is_remapping or _pending_event == null:
		return

	if _is_candidate_pressed:
		_hold_timer += delta
		if _hold_timer >= HOLD_TIME_THRESHOLD:
			print("System: Hold gesture recognized for candidate input.")
			_pending_event.set_meta("gesture", "hold")
			_finalize_gesture_remap(_pending_event)
	elif _double_tap_timer > 0.0:
		_double_tap_timer -= delta
		if _double_tap_timer <= 0.0:
			print("System: Double-tap window expired. Registering Single Tap.")
			_pending_event.set_meta("gesture", "single_tap")
			_finalize_gesture_remap(_pending_event)


## Applies proper stretch flags and centered text alignment to the static header grid.
func _format_header_grid() -> void:
	header_grid.columns = 4
	header_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var labels: Array[Node] = header_grid.get_children()
	if labels.size() >= 4:
		var action_header: Label = labels[0] as Label
		var primary_header: Label = labels[1] as Label
		var secondary_header: Label = labels[2] as Label
		var reset_header: Label = labels[3] as Label

		action_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_header.size_flags_stretch_ratio = 2.0
		action_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		primary_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary_header.size_flags_stretch_ratio = 2.0
		primary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		secondary_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		secondary_header.size_flags_stretch_ratio = 2.0
		secondary_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		reset_header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reset_header.custom_minimum_size = Vector2(40.0, 0.0)
		reset_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Ensures all defined actions exist inside [InputMap] to prevent lookup failures.
func _ensure_all_actions_registered() -> void:
	for category: String in ACTION_CATEGORIES.keys():
		for action: String in ACTION_CATEGORIES[category]:
			if not InputMap.has_action(action):
				print("System: Registering missing InputMap action: ", action)
				InputMap.add_action(action)
				if action == "ttsandy":
					var default_key: InputEventKey = InputEventKey.new()
					default_key.physical_keycode = KEY_T
					default_key.set_meta("gesture", "hold")
					InputMap.action_add_event(action, default_key)


## Sets up options and loads persisted behavior preferences (Toggle vs Hold).
func _setup_behavior_controls() -> void:
	print("UI: Configuring Input Behavior dropdowns.")
	crouch_mode_label.text = "Crouch Mode"
	sprint_mode_label.text = "Sprint Mode"

	crouch_mode_option.clear()
	crouch_mode_option.add_item("Hold", 0)
	crouch_mode_option.add_item("Toggle", 1)

	var saved_crouch: String = (
		GlobalSettings.get_setting("Gameplay", "crouch_mode", "Hold") as String
	)
	crouch_mode_option.select(1 if saved_crouch == "Toggle" else 0)
	crouch_mode_option.item_selected.connect(_on_crouch_mode_selected)

	sprint_mode_option.clear()
	sprint_mode_option.add_item("Hold", 0)
	sprint_mode_option.add_item("Toggle", 1)

	var saved_sprint: String = (
		GlobalSettings.get_setting("Gameplay", "sprint_mode", "Hold") as String
	)
	sprint_mode_option.select(1 if saved_sprint == "Toggle" else 0)
	sprint_mode_option.item_selected.connect(_on_sprint_mode_selected)


## Handles crouch mode selection changes.
## [param index] The selected dropdown index.
func _on_crouch_mode_selected(index: int) -> void:
	var mode: String = crouch_mode_option.get_item_text(index)
	print("Settings: Player changed Crouch Mode to: ", mode)
	GlobalSettings.save_setting("Gameplay", "crouch_mode", mode)


## Handles sprint mode selection changes.
## [param index] The selected dropdown index.
func _on_sprint_mode_selected(index: int) -> void:
	var mode: String = sprint_mode_option.get_item_text(index)
	print("Settings: Player changed Sprint Mode to: ", mode)
	GlobalSettings.save_setting("Gameplay", "sprint_mode", mode)


## Generates the UI elements grouped by categories with primary, secondary, and clear slots.
func _create_control_list() -> void:
	print("UI: Building categorized controls list.")
	for child: Node in action_list_container.get_children():
		child.queue_free()

	for category: String in ACTION_CATEGORIES.keys():
		var category_title: Label = Label.new()
		category_title.text = category
		category_title.theme_type_variation = "HeaderMedium"
		action_list_container.add_child(category_title)

		var grid: GridContainer = GridContainer.new()
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_list_container.add_child(grid)

		var actions: Array = ACTION_CATEGORIES[category]
		for action: String in actions:
			_create_action_row(grid, action)


## Creates an individual row with primary/secondary remap buttons and an inline clear button.
## [param parent_grid] The [GridContainer] hosting the row.
## [param action] The input action key string.
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

	var secondary_btn: Button = Button.new()
	secondary_btn.focus_mode = Control.FOCUS_NONE
	secondary_btn.toggle_mode = true
	secondary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	secondary_btn.size_flags_stretch_ratio = 2.0
	secondary_btn.set_meta("action", action)
	secondary_btn.set_meta("slot", 1)
	secondary_btn.toggled.connect(_on_remap_button_toggled.bind(secondary_btn, action, 1))
	parent_grid.add_child(secondary_btn)

	var clear_btn: Button = Button.new()
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.text = "✕"
	clear_btn.custom_minimum_size = Vector2(40.0, 0.0)
	clear_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	clear_btn.tooltip_text = "Clear secondary binding or reset action"
	clear_btn.pressed.connect(_on_clear_action_pressed.bind(action, primary_btn, secondary_btn))
	parent_grid.add_child(clear_btn)

	_update_slot_button_text(primary_btn, action, 0)
	_update_slot_button_text(secondary_btn, action, 1)


## Cleans up Godot input text representations by stripping physical markers.
## [param raw_text] Raw string from [method InputEvent.as_text].
## [return] Sanitized, clean key name.
func _sanitize_key_name(raw_text: String) -> String:
	var clean: String = raw_text
	clean = clean.replace(" - Physical", "")
	clean = clean.replace(" (Physical)", "")
	clean = clean.replace("Physical ", "")
	return clean.strip_edges()


## Updates the display text on a remap button for a specific action slot, applying prefixes.
## [param button] The [Button] to update.
## [param action] The input action key string.
## [param slot_index] The target slot index (0 for Primary, 1 for Secondary).
func _update_slot_button_text(button: Button, action: String, slot_index: int) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var key_text: String = "—"

	if events.size() > slot_index:
		var target_ev: InputEvent = events[slot_index]
		var raw_name: String = _sanitize_key_name(target_ev.as_text())
		var gesture: String = ""
		if target_ev.has_meta("gesture"):
			gesture = target_ev.get_meta("gesture") as String

		if gesture == "hold" or action in HOLD_ACTIONS:
			key_text = "Hold " + raw_name
		elif gesture == "double_tap":
			key_text = "2x " + raw_name
		else:
			key_text = raw_name

	button.text = key_text


## Handles toggle state changes on remapping buttons to begin or cancel listening for inputs.
## [param toggled_on] Whether the remapping mode is active.
## [param button] The button that triggered the event.
## [param action] The input action key string.
## [param slot_index] The target slot index.
func _on_remap_button_toggled(
	toggled_on: bool, button: Button, action: String, slot_index: int
) -> void:
	if toggled_on:
		print("UI: Remap started for: ", action, " [Slot ", slot_index, "]")
		if remapping_button and remapping_button != button:
			remapping_button.button_pressed = false

		is_remapping = true
		remapping_button = button
		action_to_remap = action
		target_slot_index = slot_index
		_reset_gesture_state()
		button.text = "Press, Hold, or 2x Tap..."
	else:
		print("UI: Remap canceled for: ", action)
		if remapping_button == button:
			is_remapping = false
			remapping_button = null
			_reset_gesture_state()
			_update_slot_button_text(button, action, slot_index)


## Resets all temporary gesture recognition parameters and timers.
func _reset_gesture_state() -> void:
	_pending_event = null
	_is_candidate_pressed = false
	_hold_timer = 0.0
	_double_tap_timer = 0.0
	_press_count = 0


## Compares two input events to verify if they correspond to the exact same physical input.
## [param ev1] First [InputEvent].
## [param ev2] Second [InputEvent].
## [return] True if both events represent identical hardware inputs.
func _is_same_input(ev1: InputEvent, ev2: InputEvent) -> bool:
	if ev1 is InputEventKey and ev2 is InputEventKey:
		var k1: InputEventKey = ev1 as InputEventKey
		var k2: InputEventKey = ev2 as InputEventKey
		if k1.physical_keycode != KEY_NONE and k2.physical_keycode != KEY_NONE:
			return k1.physical_keycode == k2.physical_keycode
		return k1.keycode == k2.keycode
	if ev1 is InputEventMouseButton and ev2 is InputEventMouseButton:
		var m1: InputEventMouseButton = ev1 as InputEventMouseButton
		var m2: InputEventMouseButton = ev2 as InputEventMouseButton
		return m1.button_index == m2.button_index
	return false


## Intercepts global input events to evaluate Single Tap, Hold, or Double Tap gestures.
## [param event] The [InputEvent] received from the engine.
func _input(event: InputEvent) -> void:
	if not visible or not is_remapping:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.is_echo():
			return

		var clean_key: InputEventKey = InputEventKey.new()
		clean_key.physical_keycode = key_event.physical_keycode
		clean_key.keycode = key_event.keycode
		_process_gesture_event(clean_key, key_event.is_pressed())
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		var clean_mouse: InputEventMouseButton = InputEventMouseButton.new()
		clean_mouse.button_index = mouse_event.button_index
		_process_gesture_event(clean_mouse, mouse_event.is_pressed())
		get_viewport().set_input_as_handled()


## Feeds a normalized key/button press or release into the gesture recognition pipeline.
## [param clean_event] Normalized [InputEvent].
## [param is_pressed] Whether the physical button is currently pressed down.
func _process_gesture_event(clean_event: InputEvent, is_pressed: bool) -> void:
	if is_pressed:
		if _pending_event == null or not _is_same_input(_pending_event, clean_event):
			_pending_event = clean_event
			_press_count = 1
			_is_candidate_pressed = true
			_hold_timer = 0.0
			_double_tap_timer = 0.0
			if remapping_button:
				remapping_button.text = "Holding..."
		else:
			_press_count += 1
			if _press_count == 2 and _double_tap_timer > 0.0:
				print("System: Double-tap gesture recognized!")
				_pending_event.set_meta("gesture", "double_tap")
				_finalize_gesture_remap(_pending_event)
	else:
		if _is_candidate_pressed and _pending_event != null:
			_is_candidate_pressed = false
			if _hold_timer < HOLD_TIME_THRESHOLD:
				_double_tap_timer = DOUBLE_TAP_TIME_WINDOW
				if remapping_button:
					remapping_button.text = "Waiting 2x tap..."


## Finalizes the captured input assignment, updates UI, and persists config.
## [param new_event] The finalized [InputEvent] to assign.
func _finalize_gesture_remap(new_event: InputEvent) -> void:
	var gesture_name: String = "single_tap"
	if new_event.has_meta("gesture"):
		gesture_name = new_event.get_meta("gesture") as String

	print(
		"System: Assigning ",
		_sanitize_key_name(new_event.as_text()),
		" [Gesture: ",
		gesture_name,
		"] to ",
		action_to_remap,
		" [Slot ",
		target_slot_index,
		"]"
	)

	_assign_event_to_action_slot(action_to_remap, target_slot_index, new_event)

	var active_btn: Button = remapping_button
	var mapped_action: String = action_to_remap
	var mapped_slot: int = target_slot_index

	is_remapping = false
	if active_btn:
		active_btn.button_pressed = false
	remapping_button = null
	_reset_gesture_state()

	_save_controls()
	if active_btn:
		_update_slot_button_text(active_btn, mapped_action, mapped_slot)
	_refresh_all_buttons()


## Assigns an event specifically to either the primary or secondary slot index of an action.
## [param action] The action to assign the event to.
## [param slot_index] Target index (0 or 1).
## [param new_event] The new [InputEvent] to store.
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
		if events.is_empty():
			InputMap.action_add_event(action, new_event)
		elif events.size() == 1:
			InputMap.action_add_event(action, new_event)
		else:
			events[1] = new_event
			InputMap.action_erase_events(action)
			for ev: InputEvent in events:
				InputMap.action_add_event(action, ev)


## Clears secondary binding or erases all bindings for a given action.
## [param action] The input action key string to clear.
## [param primary_btn] Direct reference to primary slot [Button].
## [param secondary_btn] Direct reference to secondary slot [Button].
func _on_clear_action_pressed(action: String, primary_btn: Button, secondary_btn: Button) -> void:
	print("UI: Player cleared bindings for action: ", action)
	if InputMap.has_action(action):
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.size() > 1:
			events.remove_at(1)
			InputMap.action_erase_events(action)
			for ev: InputEvent in events:
				InputMap.action_add_event(action, ev)
		else:
			InputMap.action_erase_events(action)

	_save_controls()
	_update_slot_button_text(primary_btn, action, 0)
	_update_slot_button_text(secondary_btn, action, 1)
	_refresh_all_buttons()


## Restores all keybindings to factory default configurations.
func _on_reset_all_pressed() -> void:
	print("UI: Resetting all keybindings to default.")
	InputMap.load_from_project_settings()
	_save_controls()
	_refresh_all_buttons()


## Refreshes button texts across all category grids.
func _refresh_all_buttons() -> void:
	for grid: Node in action_list_container.find_children("", "GridContainer", true, false):
		for child: Node in grid.get_children():
			if child is Button and child.has_meta("slot"):
				var action: String = child.get_meta("action") as String
				var slot: int = child.get_meta("slot") as int
				_update_slot_button_text(child, action, slot)


## Persists all active action mappings into [GlobalSettings].
func _save_controls() -> void:
	print("System: Saving all action mappings to GlobalSettings.")
	for category: String in ACTION_CATEGORIES.keys():
		for action: String in ACTION_CATEGORIES[category]:
			if InputMap.has_action(action):
				var events: Array[InputEvent] = InputMap.action_get_events(action)
				GlobalSettings.save_setting("Controls", action, events)


## Resets all keybindings to factory default configurations and refreshes UI.
func reset_to_defaults() -> void:
	print("UI: ControlsPanel -> Executing reset to default.")
	_on_reset_all_pressed()
