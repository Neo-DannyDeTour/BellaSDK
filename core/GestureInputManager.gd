## Centralized input manager responsible for dispatching single-tap, hold,
## double-tap, double-tap & hold, rapid mashing, chords, and ordered sequence combinations.
extends Node

## Emitted when an action binding is successfully resolved and triggered.
## [param action] The name of the input action that was executed.
## [param gesture] The gesture type detected.
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

## Dictionary tracking the physics frame when an action was released.
var _released_actions_frame: Dictionary = {}

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

	# Clean up frame-specific actions tracking
	var current_frame: int = Engine.get_physics_frames()
	var triggered_keys_to_remove: Array = []
	for action: Variant in _triggered_actions_frame.keys():
		var target_frame: int = _triggered_actions_frame[action] as int
		if current_frame > target_frame + 1:
			triggered_keys_to_remove.append(action)
	for key: Variant in triggered_keys_to_remove:
		_triggered_actions_frame.erase(key)

	var released_keys_to_remove: Array = []
	for action: Variant in _released_actions_frame.keys():
		var target_frame: int = _released_actions_frame[action] as int
		if current_frame > target_frame + 1:
			released_keys_to_remove.append(action)
	for key: Variant in released_keys_to_remove:
		_released_actions_frame.erase(key)


## Intercepts global input events to evaluate gestures, chords, and buffering.
## [param event] The [InputEvent] received from the engine.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event is InputEventKey and (event as InputEventKey).is_echo():
		return

	var input_id: int = _get_unique_event_id(event)
	var is_pressed: bool = event.is_pressed()

	var matching_bindings: Array[Dictionary] = _get_actions_for_event(event)

	if is_pressed:
		var consumed_by_chord: bool = false

		# 1. Check ordered chords before registering the new key into _held_keys
		for binding_info: Dictionary in matching_bindings:
			var gesture_type: String = binding_info["gesture"] as String
			var chord_keys: Array = binding_info["chord_keys"] as Array
			var action: String = binding_info["action"] as String

			if gesture_type == "ordered_chord" and not chord_keys.is_empty():
				var trigger_key: int = chord_keys[chord_keys.size() - 1] as int
				# Trigger only if current key is the final key AND all preceding modifiers were already down
				if input_id == trigger_key and _are_modifier_keys_held(chord_keys):
					print("System: Ordered chord validated: ", action)
					_dispatch_action(action, "ordered_chord")
					consumed_by_chord = true

			elif gesture_type == "chord" and not chord_keys.is_empty():
				if _are_chord_keys_pressed(chord_keys):
					print("System: Standard chord triggered for action: ", action)
					_dispatch_action(action, "chord")
					consumed_by_chord = true

		_held_keys[input_id] = true

		if consumed_by_chord:
			return

		for binding_info: Dictionary in matching_bindings:
			var action: String = binding_info["action"] as String
			var gesture_type: String = binding_info["gesture"] as String
			var tracking_key: String = str(input_id) + "_" + action

			if gesture_type in ["chord", "ordered_chord"]:
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
		_held_keys.erase(input_id)

		for binding_info: Dictionary in matching_bindings:
			var action: String = binding_info["action"] as String
			var gesture_type: String = binding_info["gesture"] as String
			var tracking_key: String = str(input_id) + "_" + action

			_released_actions_frame[action] = Engine.get_physics_frames()

			if _active_inputs.has(tracking_key):
				var data: Dictionary = _active_inputs[tracking_key] as Dictionary
				data["is_pressed"] = false
				if gesture_type in ["double_tap", "double_tap_hold", "mash"]:
					data["tap_window"] = MULTI_TAP_WINDOW
				elif gesture_type in ["hold", "single_tap"]:
					_active_inputs.erase(tracking_key)


## Checks if all modifier keys preceding the final trigger key are held down.
## [param chord_keys] List of integer unique key IDs in chronological order.
## [return] True if all prefix keys are currently in [_held_keys].
func _are_modifier_keys_held(chord_keys: Array) -> bool:
	if chord_keys.size() < 2:
		return false
	for i: int in range(chord_keys.size() - 1):
		var k: int = chord_keys[i] as int
		if not _held_keys.has(k):
			return false
	return true


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
			if gesture in ["chord", "ordered_chord"] and not chord_keys.is_empty():
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


## Checks if an action was triggered during the current physics frame window.
## [param action] The input action key string.
## [return] True if the action's gesture conditions were satisfied.
func is_action_just_triggered(action: String) -> bool:
	var current_frame: int = Engine.get_physics_frames()
	if _triggered_actions_frame.has(action):
		var target_frame: int = _triggered_actions_frame[action] as int
		if current_frame == target_frame or current_frame == target_frame + 1:
			return true
	return false


## Checks if an action is currently active, taking into account chords and gestures.
## [param action] The input action key string.
## [return] True if the action's gesture and key requirements are currently met.
func is_action_active(action: String) -> bool:
	if not InputMap.has_action(action):
		return false

	var events: Array[InputEvent] = InputMap.action_get_events(action)
	for bound_event: InputEvent in events:
		var gesture: String = bound_event.get_meta("gesture", "single_tap") as String
		var chord_keys: Array = bound_event.get_meta("chord_keys", []) as Array

		if gesture == "ordered_chord" and not chord_keys.is_empty():
			if _are_chord_keys_pressed(chord_keys):
				return true
		elif gesture == "chord" and not chord_keys.is_empty():
			if _are_chord_keys_pressed(chord_keys):
				return true
		elif gesture == "single_tap" or gesture == "":
			if _is_event_currently_held(bound_event):
				return true

	return false


## Checks if the physical key or mouse button for an event is currently held.
## [param event] The [InputEvent] to inspect.
## [return] True if the event ID exists in [_held_keys].
func _is_event_currently_held(event: InputEvent) -> bool:
	var event_id: int = _get_unique_event_id(event)
	return _held_keys.has(event_id)


## Emits action signals, updates buffered queue, and timestamps single-frame triggers.
## [param action] The input action key string.
## [param gesture] The detected gesture mode.
func _dispatch_action(action: String, gesture: String) -> void:
	print("Input Dispatch: [", action, "] triggered via [", gesture, "]")
	var now: float = Time.get_ticks_msec() / 1000.0
	_input_buffer[action] = now
	_triggered_actions_frame[action] = Engine.get_physics_frames()
	action_triggered.emit(action, gesture)


## Checks if an action is currently pressed down, validating chords and gestures.
## [param action] The input action key string to evaluate.
## [return] True if all key requirements and active gestures are met.
func is_action_pressed(action: String) -> bool:
	print("Input: Polling is_action_pressed for action: ", action)
	if not InputMap.has_action(action):
		return false

	var events: Array[InputEvent] = InputMap.action_get_events(action)
	for bound_event: InputEvent in events:
		var gesture: String = bound_event.get_meta("gesture", "single_tap") as String
		var chord_keys: Array = bound_event.get_meta("chord_keys", []) as Array

		if gesture in ["chord", "ordered_chord"] and not chord_keys.is_empty():
			if _are_chord_keys_pressed(chord_keys):
				return true
		elif gesture == "single_tap" or gesture == "":
			if _is_event_currently_held(bound_event):
				return true

	return false


## Checks if an action met its trigger condition during the current physics frame.
## [param action] The input action key string to evaluate.
## [return] True if the action triggered this frame.
func is_action_just_pressed(action: String) -> bool:
	print("Input: Polling is_action_just_pressed for action: ", action)
	var current_frame: int = Engine.get_physics_frames()
	if _triggered_actions_frame.has(action):
		var target_frame: int = _triggered_actions_frame[action] as int
		if current_frame == target_frame or current_frame == target_frame + 1:
			return true
	return false


## Checks if an action was released during the active frame window.
## [param action] The input action key string to evaluate.
## [return] True if the action was released this frame.
func is_action_just_released(action: String) -> bool:
	print("Input: Polling is_action_just_released for action: ", action)
	var current_frame: int = Engine.get_physics_frames()
	if _released_actions_frame.has(action):
		var target_frame: int = _released_actions_frame[action] as int
		if current_frame == target_frame or current_frame == target_frame + 1:
			return true
	return false


## Gets an input vector by reading four actions.
## [param negative_x] The negative X action.
## [param positive_x] The positive X action.
## [param negative_y] The negative Y action.
## [param positive_y] The positive Y action.
## [return] The resulting Vector2.
func get_vector(
	negative_x: String, positive_x: String, negative_y: String, positive_y: String
) -> Vector2:
	return Input.get_vector(negative_x, positive_x, negative_y, positive_y)


## Gets an input axis by reading two actions.
## [param negative_action] The negative action.
## [param positive_action] The positive action.
## [return] The resulting float.
func get_axis(negative_action: String, positive_action: String) -> float:
	return Input.get_axis(negative_action, positive_action)
