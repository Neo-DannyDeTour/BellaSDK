extends Control
class_name UIKeypad

signal code_entered(code: String)
signal button_clicked(button_name: String)

var entered_code: String = ""
var is_locked_out: bool = false

@onready var line_edit: LineEdit = $VBoxContainer/LineEdit
@onready var grid_container: GridContainer = $VBoxContainer/GridContainer

func _ready() -> void:
	print("UIKeypad: Initialization started.")
	for child: Node in grid_container.get_children():
		if child is Button:
			child.focus_mode = Control.FOCUS_NONE 
			child.pressed.connect(_on_button_pressed.bind(child.name))
	print("UIKeypad: Button signals connected successfully.")

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

	elif button_name == "Enter":
		print("UIKeypad: Enter button triggered.")
		_send_code()

	elif button_name == "Reset":
		_reset_display()
		print("UIKeypad: Code reset triggered.")

func _send_code() -> void:
	print("UIKeypad: Attempting to send code -> ", entered_code)
	
	if entered_code.length() > 0:
		code_entered.emit(entered_code)
		print("UIKeypad: Success. Code emitted -> ", entered_code)
	else:
		print("UIKeypad: Failed. Code was empty.")

func display_result(is_correct: bool) -> void:
	is_locked_out = true 
	
	if is_correct:
		line_edit.add_theme_color_override("font_color", Color.GREEN)
		line_edit.text = "CORRECT"
	else:
		line_edit.add_theme_color_override("font_color", Color.RED)
		line_edit.text = "INCORRECT"
		
	get_tree().create_timer(1.5).timeout.connect(_reset_display)

func _reset_display() -> void:
	entered_code = ""
	line_edit.text = ""
	line_edit.remove_theme_color_override("font_color")
	is_locked_out = false
