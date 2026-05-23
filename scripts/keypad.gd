extends Control
class_name UIKeypad

signal code_entered(code: int)

@onready var line_edit: LineEdit = $VBoxContainer/LineEdit
@onready var grid_container: GridContainer = $VBoxContainer/GridContainer

var enteredCode := ""


func _ready() -> void:
	for button in grid_container.get_children():
		# Bind the button's name so we know which one was pressed
		button.pressed.connect(_on_button_pressed.bind(button.name))


# FIX: Typed the parameter as String and renamed to button_name
func _on_button_pressed(button_name: String) -> void:
	if button_name.is_valid_int():
		# --- THE FIX ---
		# Only add the number if we currently have less than 4 digits
		if enteredCode.length() < 4:
			enteredCode += button_name
			line_edit.text = enteredCode

	elif button_name == "Enter":
		_send_code()
	elif button_name == "Reset":
		enteredCode = ""
		line_edit.text = ""


func _send_code() -> void:
	if enteredCode.is_valid_int():
		code_entered.emit(enteredCode.to_int())
	enteredCode = ""
	line_edit.text = ""
