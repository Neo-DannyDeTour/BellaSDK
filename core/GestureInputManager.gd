## Centralized input manager responsible for dispatching single-tap, hold,
## and double-tap gestures during gameplay.
extends Node

## Emitted when an action binding is successfully resolved and triggered.
## [param action] The name of the input action that was executed.
## [param gesture] The gesture type detected ("single_tap", "hold", "double_tap").
signal action_triggered(action: String, gesture: String)

## Duration in seconds a button must be held down to trigger a hold gesture.
const HOLD_THRESHOLD: float = 0.45

## Maximum time window in seconds between taps to register a double-tap gesture.
const DOUBLE_TAP_WINDOW: float = 0.30

## Internal tracking state for an active physical input.
var _active_inputs: Dictionary = {}

## Queue of actions successfully triggered during the current frame.
var _triggered_actions_this_frame: Dictionary = {}


## Lifecycle method called when the node enters the scene tree.
func _ready() -> void:
	print("System: GestureInputManager initialized.")


## Frame lifecycle method updating hold timers and resolving single-tap timeouts.
## [param delta] Frame execution delta in seconds.
func _process(delta: float) -> void:
	_triggered_actions_this_frame.clear()

	var keys_to_remove: Array = []

	for input_key: Variant in _active_inputs.keys():
		var data: Dictionary = _active_inputs[input_key] as Dictionary
		var is_pressed: bool = data["is_pressed"] as bool
		var gesture_type: String = data["gesture_type"] as String

		if is_pressed:
			data["hold_timer"] = (data["hold_timer"] as float) + delta
			if gesture_type == "hold" and not (data["hold_fired"] as bool):
				if (data["hold_timer"] as float) >= HOLD_THRESHOLD:
					data["hold_fired"] = true
					_dispatch_action(data["action"] as String, "hold")
		else:
			if (data["tap_window"] as float) > 0.0:
				data["tap_window"] = (data["tap_window"] as float) - delta
				if (data["tap_window"] as float) <= 0.0:
					if gesture_type == "single_tap" and (data["tap_count"] as int) == 1:
						_dispatch_action(data["action"] as String, "single_tap")
					keys_to_remove.append(input_key)

	for key: Variant in keys_to_remove:
		_active_inputs.erase(key)


## Intercepts global input events to evaluate Single Tap, Hold, or Double Tap gestures.
## Consumes events tied to gesture-tracked actions to prevent raw input leakage.
## [param event] The [InputEvent] received from the engine.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	if event is InputEventKey and (event as InputEventKey).is_echo():
		return

	var binding_info: Dictionary = _get_action_for_event(event)
	if binding_info.is_empty():
		return

	var input_id: int = _get_unique_event_id(event)
	var action: String = binding_info["action"] as String
	var gesture_type: String = binding_info["gesture"] as String
	var is_pressed: bool = event.is_pressed()

	if is_pressed:
		if not _active_inputs.has(input_id):
			_active_inputs[input_id] = {
				"action": action,
				"gesture_type": gesture_type,
				"is_pressed": true,
				"hold_timer": 0.0,
				"hold_fired": false,
				"tap_window": 0.0,
				"tap_count": 1
			}
		else:
			var data: Dictionary = _active_inputs[input_id] as Dictionary
			data["is_pressed"] = true
			data["hold_timer"] = 0.0
			data["hold_fired"] = false
			data["tap_count"] = (data["tap_count"] as int) + 1

			if gesture_type == "double_tap" and (data["tap_count"] as int) >= 2:
				_dispatch_action(action, "double_tap")
				_active_inputs.erase(input_id)
	else:
		if _active_inputs.has(input_id):
			var data: Dictionary = _active_inputs[input_id] as Dictionary
			data["is_pressed"] = false
			if gesture_type == "double_tap" or gesture_type == "single_tap":
				data["tap_window"] = DOUBLE_TAP_WINDOW
			elif gesture_type == "hold":
				_active_inputs.erase(input_id)


## Checks if an action was triggered by its configured gesture during the current frame.
## [param action] The input action key string.
## [return] True if the action's gesture conditions were satisfied this frame.
func is_action_just_triggered(action: String) -> bool:
	return _triggered_actions_this_frame.has(action)


## Checks if a continuous action (like Movement) is currently held down.
## [param action] The input action key string.
## [return] True if the action is currently active.
func is_action_active(action: String) -> bool:
	return Input.is_action_pressed(action)


## Emits action signals and caches single-frame trigger statuses.
## [param action] The input action key string.
## [param gesture] The detected gesture mode.
func _dispatch_action(action: String, gesture: String) -> void:
	print("Input Dispatch: [", action, "] triggered via [", gesture, "]")
	_triggered_actions_this_frame[action] = true
	action_triggered.emit(action, gesture)


## Matches an incoming physical input event against registered [InputMap] bindings.
## [param event] The [InputEvent] to test.
## [return] A [Dictionary] with action name and gesture type metadata.
func _get_action_for_event(event: InputEvent) -> Dictionary:
	for action: String in InputMap.get_actions():
		for bound_event: InputEvent in InputMap.action_get_events(action):
			if _is_matching_event(event, bound_event):
				var gesture: String = "single_tap"
				if bound_event.has_meta("gesture"):
					gesture = bound_event.get_meta("gesture") as String
				return {"action": action, "gesture": gesture}
	return {}


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
