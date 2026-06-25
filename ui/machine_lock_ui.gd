class_name MachineLockUI
extends CanvasLayer

signal code_submitted(code: String)
signal aborted

@export var labels: Array[Label] = []
@export var up_buttons: Array[Button] = []
@export var down_buttons: Array[Button] = []

var use_letters: bool = false
var wheel_indices: Array[int] = [0, 0, 0]
var active_wheel: int = 0

const NUMBERS: String = "0123456789"
const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


func _ready() -> void:
	for i: int in range(up_buttons.size()):
		up_buttons[i].pressed.connect(_on_button_pressed.bind(i, 1))
		down_buttons[i].pressed.connect(_on_button_pressed.bind(i, -1))


# Called by the 3D lock when instantiated
func setup(is_letters_mode: bool) -> void:
	use_letters = is_letters_mode
	_update_all_labels()


func _input(event: InputEvent) -> void:
	# 1. Check for enter/submit
	if event.is_action_pressed("ui_accept"):
		_submit_code()
		get_viewport().set_input_as_handled()
		return

	# 2. Check for exit/detach (Assuming "interact" is mapped to E)
	if event.is_action_pressed("interact") and not event.is_echo():
		aborted.emit()
		get_viewport().set_input_as_handled()
		return

	# 3. Check for typing
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_str: String = OS.get_keycode_string(event.physical_keycode).to_upper()
		
		if use_letters:
			if key_str.length() == 1 and key_str.unicode_at(0) >= 65 and key_str.unicode_at(0) <= 90:
				_type_character(key_str)
		else:
			if key_str.length() == 1 and key_str.is_valid_int():
				_type_character(key_str)
			elif key_str.begins_with("KP "):
				var num_str: String = key_str.substr(3, 1)
				if num_str.is_valid_int():
					_type_character(num_str)


func _type_character(char_str: String) -> void:
	var target_set: String = LETTERS if use_letters else NUMBERS
	var char_index: int = target_set.find(char_str)
	
	if char_index != -1:
		wheel_indices[active_wheel] = char_index
		active_wheel = (active_wheel + 1) % 3
		_update_all_labels()


func _on_button_pressed(wheel_index: int, direction: int) -> void:
	var set_length: int = LETTERS.length() if use_letters else NUMBERS.length()
	wheel_indices[wheel_index] = (wheel_indices[wheel_index] + direction + set_length) % set_length
	active_wheel = wheel_index 
	_update_all_labels()


func _update_all_labels() -> void:
	var target_set: String = LETTERS if use_letters else NUMBERS
	for i: int in range(labels.size()):
		var idx: int = wheel_indices[i]
		labels[i].text = target_set.substr(idx, 1)


func _submit_code() -> void:
	var target_set: String = LETTERS if use_letters else NUMBERS
	var final_code: String = ""
	
	for idx: int in wheel_indices:
		final_code += target_set.substr(idx, 1)
		
	code_submitted.emit(final_code)
