## Manages 2D numeric keypad UI input, display formatting, and submission signals.
class_name UIKeypad
extends Control

## Emitted when the player submits a non-empty numeric sequence.
## [param code] The submitted sequence string.
@warning_ignore("unused_signal")
signal code_entered(code: String)

## Emitted whenever any keypad button is pressed.
## [param button_name] The identifier of the clicked button node.
@warning_ignore("unused_signal")
signal button_clicked(button_name: String)

## Emitted when visual state changes, signaling the parent SubViewport to redraw.
@warning_ignore("unused_signal")
signal display_updated

## The currently entered numeric code.
var entered_code: String = ""

## Indicates whether the keypad is locked temporarily after submission.
var is_locked_out: bool = false

## Reference to the UI LineEdit for displaying the code.
@onready var line_edit: LineEdit = $VBoxContainer/LineEdit

## Reference to the GridContainer holding the keypad buttons.
@onready var grid_container: GridContainer = $VBoxContainer/GridContainer


## Initializes button signals and disables standard UI focus navigation.
func _ready() -> void:
	print("UIKeypad: Initialization started.")
	for child: Node in grid_container.get_children():
		if child is Button:
			var btn: Button = child as Button
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_button_pressed.bind(btn.name))
	print("UIKeypad: Button signals connected successfully.")
	display_updated.emit()


## Routes button inputs to numeric concatenation, clearing, or code submission.
## [param button_name] The string name of the pressed button node.
func _on_button_pressed(button_name: String) -> void:
	if is_locked_out:
		return

	print("UIKeypad: Button pressed -> ", button_name)
	button_clicked.emit(button_name)

	if button_name.is_valid_int():
		if entered_code.length() < 4:
			entered_code += button_name
			line_edit.text = entered_code
			print("UIKeypad: Current code updated to -> ", entered_code)
			display_updated.emit()

	elif button_name == "Enter":
		print("UIKeypad: Enter button triggered.")
		_send_code()

	elif button_name == "Reset":
		_reset_display()
		print("UIKeypad: Code reset triggered.")


## Dispatches the completed code string if not empty.
func _send_code() -> void:
	print("UIKeypad: Attempting to send code -> ", entered_code)

	if entered_code.length() > 0:
		code_entered.emit(entered_code)
		print("UIKeypad: Success. Code emitted -> ", entered_code)
	else:
		print("UIKeypad: Failed. Code was empty.")


## Temporarily locks the keypad and shows visual validation status.
## [param is_correct] Whether the entered combination matched the valid code.
func display_result(is_correct: bool) -> void:
	print("UIKeypad: Displaying validation result -> ", is_correct)
	is_locked_out = true

	if is_correct:
		line_edit.add_theme_color_override("font_color", Color.GREEN)
		line_edit.text = "CORRECT"
	else:
		line_edit.add_theme_color_override("font_color", Color.RED)
		line_edit.text = "INCORRECT"

	display_updated.emit()
	get_tree().create_timer(1.5).timeout.connect(_reset_display)


## Clears active text and unlocks the keypad for subsequent entries.
func _reset_display() -> void:
	print("UIKeypad: Resetting display state.")
	entered_code = ""
	line_edit.text = ""
	line_edit.remove_theme_color_override("font_color")
	is_locked_out = false
	display_updated.emit()
