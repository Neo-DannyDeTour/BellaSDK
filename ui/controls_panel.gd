## Manages player key remapping UI, multi-slot bindings, categories, and behavior settings.
## Supports single-tap, hold, double-tap, double-tap & hold,
##  rapid mashing, and multi-key chord binding detection.
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

## Base directory path where Kenney input prompt icons are stored.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## List of actions that are inherently hold-activated by design.
const HOLD_ACTIONS: Array[String] = ["ttsandy", "describe_surroundings"]

## Duration in seconds a button must be held down to be registered as a Hold binding.
const HOLD_TIME_THRESHOLD: float = 0.45

## Maximum time gap in seconds between consecutive presses to register multi-tap gestures.
const MULTI_TAP_TIME_WINDOW: float = 0.30

## Number of rapid taps required within the multi-tap window to register a mash gesture.
const MASH_THRESHOLD_COUNT: int = 3

## Time gap in seconds allowed between chord member key presses.
const CHORD_COMPLETION_WINDOW: float = 0.25

## Indicates if the player is currently pressing keys to remap an action.
var is_remapping: bool = false

## The specific input action string currently being remapped.
var action_to_remap: String = ""

## The target event index being remapped (0 for Primary, 1 for Secondary).
var target_slot_index: int = 0

## Reference to the UI button currently waiting for player input.
var remapping_button: Button = null

## The candidate input event currently being evaluated for gestures.
var _pending_event: InputEvent = null

## List of unique input events pressed simultaneously for chord binding detection.
var _chord_events: Array[InputEvent] = []

## Tracks whether the candidate key or mouse button is currently held down.
var _is_candidate_pressed: bool = false

## Countdown timer tracking hold duration.
var _hold_timer: float = 0.0

## Countdown timer tracking multi-tap detection window.
var _multi_tap_timer: float = 0.0

## Countdown timer allowing multiple simultaneous keys to register as a chord.
var _chord_timer: float = 0.0

## Tracks how many times the candidate button was tapped within the detection window.
var _press_count: int = 0

## Cache mapping resolved file paths to preloaded textures to prevent redundant disk I/O.
var _icon_cache: Dictionary = {}

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
				print("System: Double-Tap & Hold gesture recognized.")
				_pending_event.set_meta("gesture", "double_tap_hold")
			else:
				print("System: Hold gesture recognized.")
				_pending_event.set_meta("gesture", "hold")
			_finalize_gesture_remap(_pending_event)
	elif _multi_tap_timer > 0.0:
		_multi_tap_timer -= delta
		if _multi_tap_timer <= 0.0:
			if _press_count >= MASH_THRESHOLD_COUNT:
				print("System: Mash gesture recognized.")
				_pending_event.set_meta("gesture", "mash")
			elif _press_count == 2:
				print("System: Double-tap recognized on timeout.")
				_pending_event.set_meta("gesture", "double_tap")
			else:
				print("System: Single tap recognized on timeout.")
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


## Helper to construct a normalized [InputEvent] from a custom unique event ID.
## [param event_id] The unique integer representation of a key or mouse button.
## [return] A newly created [InputEvent] corresponding to the ID.
func _create_event_from_id(event_id: int) -> InputEvent:
	if event_id >= 100000:
		var mouse_ev: InputEventMouseButton = InputEventMouseButton.new()
		mouse_ev.button_index = (event_id - 100000) as MouseButton
		return mouse_ev

	var key_ev: InputEventKey = InputEventKey.new()
	key_ev.physical_keycode = event_id as Key
	return key_ev


## Builds a UI preview element (icon [TextureRect] or [Label]) for an input event.
## [param event] The [InputEvent] to generate an element for.
## [return] A configured [Control] ready to add to a layout container.
func _create_event_display_node(event: InputEvent) -> Control:
	var icon_tex: Texture2D = _get_event_icon(event)
	if icon_tex != null:
		var tex_rect: TextureRect = TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(24.0, 24.0)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tex_rect

	var lbl: Label = Label.new()
	lbl.text = _sanitize_key_name(event.as_text())
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## Updates the display layout, text, and icons on a remap button for a specific action slot.
## [param button] The [Button] to update.
## [param action] The input action key string.
## [param slot_index] The target slot index (0 for Primary, 1 for Secondary).
func _update_slot_button_text(button: Button, action: String, slot_index: int) -> void:
	print("UI: Updating slot button for action: ", action, " [Slot ", slot_index, "]")
	var events: Array[InputEvent] = InputMap.action_get_events(action)

	# Clean up any existing dynamic preview containers inside the button
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
		gesture = target_ev.get_meta("gesture") as String

	var container: HBoxContainer = HBoxContainer.new()
	container.name = "PreviewContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_theme_constant_override("separation", 6)
	button.add_child(container)

	# 1. Determine and add gesture prefix label
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

	# 2. Render Chord combination icons or single event icon
	if target_ev.has_meta("chord_keys"):
		var keys_array: Array = target_ev.get_meta("chord_keys") as Array
		for i: int in range(keys_array.size()):
			var key_id: int = keys_array[i] as int
			var ev: InputEvent = _create_event_from_id(key_id)
			container.add_child(_create_event_display_node(ev))

			if i < keys_array.size() - 1:
				var plus_label: Label = Label.new()
				plus_label.text = "+"
				plus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				container.add_child(plus_label)
	else:
		container.add_child(_create_event_display_node(target_ev))


## Handles toggle state changes on remapping buttons to begin or cancel listening for inputs.
## [param toggled_on] Whether the remapping mode is active.
## [param button] The button that triggered the event.
## [param action] The input action key string.
## [param slot_index] The target slot index.
func _on_remap_button_toggled(
	toggled_on: bool, button: Button, action: String, slot_index: int
) -> void:
	var existing_container: Node = button.get_node_or_null("PreviewContainer")
	if existing_container != null:
		existing_container.queue_free()

	if toggled_on:
		print("UI: Remap started for: ", action, " [Slot ", slot_index, "]")
		if remapping_button and remapping_button != button:
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


## Resets all temporary gesture recognition parameters and timers.
func _reset_gesture_state() -> void:
	_pending_event = null
	_chord_events.clear()
	_is_candidate_pressed = false
	_hold_timer = 0.0
	_multi_tap_timer = 0.0
	_chord_timer = 0.0
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


## Generates a unique integer identifier for hardware inputs.
## [param event] The [InputEvent] to identify.
## [return] A unique integer ID.
func _get_unique_event_id(event: InputEvent) -> int:
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if event is InputEventMouseButton:
		return 100000 + (event as InputEventMouseButton).button_index
	return -1


## Intercepts global input events to evaluate gestures and chord combinations.
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
		var exists_in_chord: bool = false
		for ev: InputEvent in _chord_events:
			if _is_same_input(ev, clean_event):
				exists_in_chord = true
				break
		if not exists_in_chord:
			_chord_events.append(clean_event)

		if _chord_events.size() > 1:
			_chord_timer = CHORD_COMPLETION_WINDOW
			if remapping_button:
				remapping_button.text = "Chord detecting..."
			return

		if _pending_event == null or not _is_same_input(_pending_event, clean_event):
			_pending_event = clean_event
			_press_count = 1
			_is_candidate_pressed = true
			_hold_timer = 0.0
			_multi_tap_timer = 0.0
			if remapping_button:
				remapping_button.text = "Holding..."
		else:
			_press_count += 1
			_is_candidate_pressed = true
			_hold_timer = 0.0
			if _press_count >= MASH_THRESHOLD_COUNT:
				_multi_tap_timer = MULTI_TAP_TIME_WINDOW
				if remapping_button:
					remapping_button.text = "Mashing (" + str(_press_count) + ")..."
			elif _press_count == 2:
				if remapping_button:
					remapping_button.text = "Holding 2x..."
	else:
		if _chord_events.size() > 1:
			return

		if _is_candidate_pressed and _pending_event != null:
			_is_candidate_pressed = false
			if _hold_timer < HOLD_TIME_THRESHOLD:
				_multi_tap_timer = MULTI_TAP_TIME_WINDOW
				if remapping_button:
					remapping_button.text = "Waiting next tap..."


## Finalizes chord assignment using the base anchor event and chord metadata.
func _finalize_chord_remap() -> void:
	var base_event: InputEvent = _chord_events[0]
	var key_ids: Array[int] = []
	for ev: InputEvent in _chord_events:
		key_ids.append(_get_unique_event_id(ev))

	base_event.set_meta("gesture", "chord")
	base_event.set_meta("chord_keys", key_ids)
	_finalize_gesture_remap(base_event)


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
		if events.is_empty() or events.size() == 1:
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


## Resolves an [InputEvent] to a matching default Kenney prompt icon texture.
## Checks root default directory and subfolders with in-memory caching.
## [param event] The [InputEvent] to find an icon for.
## [return] The loaded [Texture2D], or null if no matching asset exists.
func _get_event_icon(event: InputEvent) -> Texture2D:
	var possible_filenames: Array[String] = []

	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		var code: Key = (
			key_event.physical_keycode
			if key_event.physical_keycode != KEY_NONE
			else key_event.keycode
		)
		var key_str: String = OS.get_keycode_string(code).to_lower()

		match code:
			KEY_SPACE:
				possible_filenames.append("keyboard_space.png")
				possible_filenames.append("keyboard_space_icon.png")
			KEY_ENTER:
				possible_filenames.append("keyboard_return.png")
				possible_filenames.append("keyboard_enter.png")
			KEY_SHIFT:
				possible_filenames.append("keyboard_shift.png")
			KEY_CTRL:
				possible_filenames.append("keyboard_ctrl.png")
			KEY_ALT:
				possible_filenames.append("keyboard_alt.png")
			KEY_TAB:
				possible_filenames.append("keyboard_tab.png")
			KEY_ESCAPE:
				possible_filenames.append("keyboard_escape.png")
			KEY_BACKSPACE:
				possible_filenames.append("keyboard_backspace.png")
			KEY_CAPSLOCK:
				possible_filenames.append("keyboard_capslock.png")
			KEY_SLASH:
				possible_filenames.append("keyboard_slash_forward.png")
			KEY_BACKSLASH:
				possible_filenames.append("keyboard_slash_back.png")
			KEY_SEMICOLON:
				possible_filenames.append("keyboard_semicolon.png")
			KEY_PERIOD:
				possible_filenames.append("keyboard_period.png")
			KEY_COMMA:
				possible_filenames.append("keyboard_comma.png")
			KEY_MINUS:
				possible_filenames.append("keyboard_minus.png")
			KEY_EQUAL:
				possible_filenames.append("keyboard_equals.png")
			KEY_PAGEUP:
				possible_filenames.append("keyboard_page_up.png")
			KEY_PAGEDOWN:
				possible_filenames.append("keyboard_page_down.png")
			KEY_PAUSE:
				possible_filenames.append("keyboard_pause.png")
			KEY_SCROLLLOCK:
				possible_filenames.append("keyboard_scroll_lock.png")
			KEY_PRINT:
				possible_filenames.append("keyboard_printscreen.png")
			_:
				if key_str.length() == 1:
					possible_filenames.append("keyboard_%s.png" % key_str)
					possible_filenames.append("keyboard_%s_outline.png" % key_str)

	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				possible_filenames.append("mouse_left.png")
				possible_filenames.append("mouse_left_click.png")
				possible_filenames.append("mouse_left_outline.png")
			MOUSE_BUTTON_RIGHT:
				possible_filenames.append("mouse_right.png")
				possible_filenames.append("mouse_right_click.png")
				possible_filenames.append("mouse_right_outline.png")
			MOUSE_BUTTON_MIDDLE:
				possible_filenames.append("mouse_middle.png")
				possible_filenames.append("mouse_scroll.png")
			MOUSE_BUTTON_WHEEL_UP:
				possible_filenames.append("mouse_scroll_up.png")
			MOUSE_BUTTON_WHEEL_DOWN:
				possible_filenames.append("mouse_scroll_down.png")

	if possible_filenames.is_empty():
		return null

	for file_name: String in possible_filenames:
		var candidate_paths: Array[String] = [
			ICON_BASE_PATH + file_name,
			ICON_BASE_PATH + "Keyboard/" + file_name,
			ICON_BASE_PATH + "Mouse/" + file_name
		]

		for full_path: String in candidate_paths:
			if _icon_cache.has(full_path):
				return _icon_cache[full_path] as Texture2D

			if ResourceLoader.exists(full_path):
				var tex: Texture2D = load(full_path) as Texture2D
				_icon_cache[full_path] = tex
				return tex

	print("UI: Icon not found for event across tested search paths: ", event.as_text())
	return null
