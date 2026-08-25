## Centralized input manager responsible for dispatching single-tap, hold,
## double-tap, double-tap & hold, rapid mashing, chords, and input buffering.
extends Node

## Emitted when an action binding is successfully resolved and triggered.
## [param action] The name of the input action that was executed.
## [param gesture] The gesture type detected
## ("single_tap", "hold", "double_tap", "double_tap_hold", "mash", "chord").
signal action_triggered(action: String, gesture: String)

## Duration in seconds a button must be held down to trigger a hold gesture.
const HOLD_THRESHOLD: float = 0.45

## Maximum time window in seconds between taps to register multi-tap gestures.
const MULTI_TAP_WINDOW: float = 0.30

## Number of taps required to trigger a rapid mashing action.
const MASH_TAP_COUNT: int = 3

## Duration in seconds an input trigger is preserved in the buffer queue.
const BUFFER_DURATION: float = 0.20

## Internal tracking state for active physical inputs.
var _active_inputs: Dictionary = {}

## Maps action names to the physics frame tick when they were triggered.
var _triggered_actions_frame: Dictionary = {}

## Set of currently held physical key/button unique IDs.
var _held_keys: Dictionary = {}

## Circular buffer tracking recent action timestamps for input buffering.
var _input_buffer: Dictionary = {}


## Lifecycle method called when the node enters the scene tree.
func _ready() -> void:
	print("System: GestureInputManager initialized.")


## Frame lifecycle method updating gesture timers and expiring buffered inputs.
## [param delta] Frame execution delta in seconds.
func _process(delta: float) -> void:
	var keys_to_remove: Array = []
	var now: float = Time.get_ticks_msec() / 1000.0

	for action: Variant in _input_buffer.keys():
		var timestamp: float = _input_buffer[action] as float
		if now - timestamp > BUFFER_DURATION:
			keys_to_remove.append(action)

	for action: Variant in keys_to_remove:
		_input_buffer.erase(action)
	keys_to_remove.clear()

	for input_key: Variant in _active_inputs.keys():
		var data: Dictionary = _active_inputs[input_key] as Dictionary
		var is_pressed: bool = data["is_pressed"] as bool
		var gesture_type: String = data["gesture_type"] as String
		var action: String = data["action"] as String

		if is_pressed:
			data["hold_timer"] = (data["hold_timer"] as float) + delta
			if gesture_type == "hold" and not (data["hold_fired"] as bool):
				if (data["hold_timer"] as float) >= HOLD_THRESHOLD:
					data["hold_fired"] = true
					_dispatch_action(action, "hold")
			elif gesture_type == "double_tap_hold" and not (data["hold_fired"] as bool):
				if (
					(data["tap_count"] as int) >= 2
					and (data["hold_timer"] as float) >= HOLD_THRESHOLD
				):
					data["hold_fired"] = true
					_dispatch_action(action, "double_tap_hold")
		else:
			if (data["tap_window"] as float) > 0.0:
				data["tap_window"] = (data["tap_window"] as float) - delta
				if (data["tap_window"] as float) <= 0.0:
					if gesture_type == "single_tap" and (data["tap_count"] as int) == 1:
						_dispatch_action(action, "single_tap")
					keys_to_remove.append(input_key)

	for key: Variant in keys_to_remove:
		_active_inputs.erase(key)


## Intercepts global input events to evaluate gestures, chords, and buffering.
## [param event] The [InputEvent] received from the engine.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event is InputEventKey and (event as InputEventKey).is_echo():
		return

	var input_id: int = _get_unique_event_id(event)
	var is_pressed: bool = event.is_pressed()

	if is_pressed:
		_held_keys[input_id] = true
	else:
		_held_keys.erase(input_id)

	var matching_bindings: Array[Dictionary] = _get_actions_for_event(event)
	if matching_bindings.is_empty():
		return

	for binding_info: Dictionary in matching_bindings:
		var action: String = binding_info["action"] as String
		var gesture_type: String = binding_info["gesture"] as String
		var chord_keys: Array = binding_info["chord_keys"] as Array
		var tracking_key: String = str(input_id) + "_" + action

		if is_pressed:
			if gesture_type == "chord":
				if _are_chord_keys_pressed(chord_keys):
					_dispatch_action(action, "chord")
				continue

			if gesture_type == "single_tap" or gesture_type == "":
				_dispatch_action(action, "single_tap")

			if not _active_inputs.has(tracking_key):
				_active_inputs[tracking_key] = {
					"action": action,
					"gesture_type": gesture_type,
					"is_pressed": true,
					"hold_timer": 0.0,
					"hold_fired": false,
					"tap_window": 0.0,
					"tap_count": 1
				}
			else:
				var data: Dictionary = _active_inputs[tracking_key] as Dictionary
				data["is_pressed"] = true
				data["hold_timer"] = 0.0
				data["hold_fired"] = false
				data["tap_count"] = (data["tap_count"] as int) + 1

				if gesture_type == "double_tap" and (data["tap_count"] as int) == 2:
					_dispatch_action(action, "double_tap")
					_active_inputs.erase(tracking_key)
				elif gesture_type == "mash" and (data["tap_count"] as int) >= MASH_TAP_COUNT:
					_dispatch_action(action, "mash")
					data["tap_count"] = 0
		else:
			if _active_inputs.has(tracking_key):
				var data: Dictionary = _active_inputs[tracking_key] as Dictionary
				data["is_pressed"] = false
				if gesture_type in ["double_tap", "double_tap_hold", "mash"]:
					data["tap_window"] = MULTI_TAP_WINDOW
				elif gesture_type in ["hold", "single_tap"]:
					_active_inputs.erase(tracking_key)


## Checks if an action was triggered by its
## configured gesture during the current physics frame window.
## [param action] The input action key string.
## [return] True if the action's gesture conditions were satisfied.
func is_action_just_triggered(action: String) -> bool:
	var current_frame: int = Engine.get_physics_frames()
	if _triggered_actions_frame.has(action):
		var target_frame: int = _triggered_actions_frame[action] as int
		if current_frame == target_frame or current_frame == target_frame + 1:
			_triggered_actions_frame.erase(action)
			return true
	return false


## Consumes a buffered action if it was executed within the allowed duration buffer window.
## [param action] The action to poll and consume.
## [return] True if the action was successfully consumed from buffer.
func consume_buffered_action(action: String) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _input_buffer.has(action):
		var timestamp: float = _input_buffer[action] as float
		if now - timestamp <= BUFFER_DURATION:
			print("Buffer: Consumed buffered action: ", action)
			_input_buffer.erase(action)
			return true
		_input_buffer.erase(action)
	return false


## Checks if a continuous action is currently held down.
## [param action] The input action key string.
## [return] True if the action is currently active.
func is_action_active(action: String) -> bool:
	return Input.is_action_pressed(action)


## Emits action signals, updates buffered queue, and timestamps single-frame triggers.
## [param action] The input action key string.
## [param gesture] The detected gesture mode.
func _dispatch_action(action: String, gesture: String) -> void:
	print("Input Dispatch: [", action, "] triggered via [", gesture, "]")
	var now: float = Time.get_ticks_msec() / 1000.0
	_input_buffer[action] = now
	_triggered_actions_frame[action] = Engine.get_physics_frames()
	action_triggered.emit(action, gesture)


## Checks if all required keys/buttons in a chord list are currently held down.
## [param chord_keys] List of integer unique key IDs.
## [return] True if all keys are active in the held keys dictionary.
func _are_chord_keys_pressed(chord_keys: Array) -> bool:
	if chord_keys.is_empty():
		return false
	for k: Variant in chord_keys:
		if not _held_keys.has(k as int):
			return false
	return true


## Matches an incoming physical input event against all registered [InputMap] bindings.
## Evaluates direct matches as well as participant keys in multi-key chords.
## [param event] The [InputEvent] to test.
## [return] An [Array] of [Dictionary] objects containing matched actions and gesture metadata.
func _get_actions_for_event(event: InputEvent) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var event_id: int = _get_unique_event_id(event)

	for action: String in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue

		for bound_event: InputEvent in InputMap.action_get_events(action):
			var gesture: String = "single_tap"
			var chord_keys: Array = []
			if bound_event.has_meta("gesture"):
				gesture = bound_event.get_meta("gesture") as String
			if bound_event.has_meta("chord_keys"):
				chord_keys = bound_event.get_meta("chord_keys") as Array

			var is_match: bool = false
			if gesture == "chord" and not chord_keys.is_empty():
				if chord_keys.has(event_id):
					is_match = true
			else:
				is_match = _is_matching_event(event, bound_event)

			if is_match:
				matches.append({"action": action, "gesture": gesture, "chord_keys": chord_keys})
	return matches


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


## Verifies if two physical input events correspond to identical hardware buttons.
## [param ev1] First [InputEvent].
## [param ev2] Second [InputEvent].
## [return] True if matching hardware inputs.
func _is_matching_event(ev1: InputEvent, ev2: InputEvent) -> bool:
	if ev1 is InputEventKey and ev2 is InputEventKey:
		var k1: InputEventKey = ev1 as InputEventKey
		var k2: InputEventKey = ev2 as InputEventKey
		var key1: int = k1.physical_keycode if k1.physical_keycode != KEY_NONE else k1.keycode
		var key2: int = k2.physical_keycode if k2.physical_keycode != KEY_NONE else k2.keycode
		return key1 == key2
	if ev1 is InputEventMouseButton and ev2 is InputEventMouseButton:
		return (
			(ev1 as InputEventMouseButton).button_index
			== (ev2 as InputEventMouseButton).button_index
		)
	return false
