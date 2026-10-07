## UI overlay managing 3-wheel combination lock input and code submission.
class_name MachineLockUI
extends CanvasLayer

## Emitted when player submits the final code combination.
signal code_submitted(code: String)

## Emitted when player cancels or closes the combination lock UI.
signal aborted

## Digit and character labels displaying active wheel values.
@export var labels: Array[Label] = []

## Buttons rotating wheels upward/forward.
@export var up_buttons: Array[Button] = []

## Buttons rotating wheels downward/backward.
@export var down_buttons: Array[Button] = []

## Toggles between alphanumeric letter mode and numeric mode.
var use_letters: bool = false

## Current character index stored for each combination wheel.
var wheel_indices: Array[int] = [0, 0, 0]

## Index of the wheel currently receiving keyboard input.
var active_wheel: int = 0

## Numerical character set used for digit lock mode.
const NUMBERS: String = "0123456789"

## Alphabetical character set used for letter lock mode.
const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


## Connects up and down button press signals for each wheel.
func _ready() -> void:
	print("MachineLockUI: Initializing lock UI buttons.")
	for i: int in range(up_buttons.size()):
		up_buttons[i].pressed.connect(_on_button_pressed.bind(i, 1))
		down_buttons[i].pressed.connect(_on_button_pressed.bind(i, -1))


## Configures lock mode and refreshes initial display labels.
func setup(is_letters_mode: bool) -> void:
	print("MachineLockUI: setup() called with letters mode: ", is_letters_mode)
	use_letters = is_letters_mode
	_update_all_labels()


## Handles keyboard events, submit shortcuts, and cancellation inputs.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		print("MachineLockUI: Player pressed ui_accept.")
		_submit_code()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact") and not event.is_echo():
		print("MachineLockUI: Player aborted lock interaction.")
		aborted.emit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_event: InputEventKey = event if event is InputEventKey else null
		var key_str: String = OS.get_keycode_string(key_event.physical_keycode).to_upper()

		if use_letters:
			if (
				key_str.length() == 1
				and key_str.unicode_at(0) >= 65
				and key_str.unicode_at(0) <= 90
			):
				_type_character(key_str)
		else:
			if key_str.length() == 1 and key_str.is_valid_int():
				_type_character(key_str)
			elif key_str.begins_with("KP "):
				var num_str: String = key_str.substr(3, 1)
				if num_str.is_valid_int():
					_type_character(num_str)


## Writes typed character to active wheel and advances to next wheel.
func _type_character(char_str: String) -> void:
	print("MachineLockUI: Player typed character: ", char_str)
	var target_set: String = LETTERS if use_letters else NUMBERS
	var char_index: int = target_set.find(char_str)

	if char_index != -1:
		wheel_indices[active_wheel] = char_index
		active_wheel = (active_wheel + 1) % 3
		_update_all_labels()


## Rotates target wheel by step direction and refreshes display.
func _on_button_pressed(wheel_index: int, direction: int) -> void:
	print("MachineLockUI: Player rotated wheel ", wheel_index, " dir: ", direction)
	var set_length: int = LETTERS.length() if use_letters else NUMBERS.length()
	wheel_indices[wheel_index] = (wheel_indices[wheel_index] + direction + set_length) % set_length
	active_wheel = wheel_index
	_update_all_labels()


## Updates visual text of all wheel labels to match stored indices.
func _update_all_labels() -> void:
	var target_set: String = LETTERS if use_letters else NUMBERS
	for i: int in range(labels.size()):
		var idx: int = wheel_indices[i]
		labels[i].text = target_set.substr(idx, 1)


## Compiles wheel characters into string and emits [signal code_submitted].
func _submit_code() -> void:
	var target_set: String = LETTERS if use_letters else NUMBERS
	var final_code: String = ""

	for idx: int in wheel_indices:
		final_code += target_set.substr(idx, 1)

	print("MachineLockUI: Player submitted code: ", final_code)
	code_submitted.emit(final_code)
