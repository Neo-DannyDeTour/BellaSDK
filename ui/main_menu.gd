extends CanvasLayer
class_name MainMenu

const DEFAULT_SENSITIVITY: float = 0.5
const CHAPTER_SCREEN: PackedScene = preload("res://ui/menu_chapter_screen.tscn")

@export_group("Options Tabs & Navigation")
@export var back_buttons: Array[Button]
@export var tab_buttons: Array[Button]
@export var option_panels: Array[Control]

@onready var main_buttons: VBoxContainer = $MarginContainer/MainButtons
@onready var options_menu: Control = %CenterContainer
@onready var save_load_panel: Panel = $SaveLoadPanel

# Main Menu Buttons
@onready var continue_button: Button = %Continue
@onready var new_game_button: Button = %NewGame
@onready var restart_button: Button = %RestartGame
@onready var save_button: Button = %SaveGame
@onready var load_button: Button = %LoadGame
@onready var options_button: Button = %Options
@onready var exit_button: Button = %Exit

var has_calibrated: bool = false
var max_mouse_speed: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("UI: MainMenu initialized.")
	
	# Connect Main Buttons
	continue_button.pressed.connect(_on_resume_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	restart_button.pressed.connect(_on_start_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	load_button.pressed.connect(_on_load_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	
	# Connect Navigation Buttons
	for btn: Button in back_buttons:
		if btn:
			btn.pressed.connect(_return_to_main_buttons)
			
	# Connect Options Tab Buttons
	for i: int in range(tab_buttons.size()):
		var btn: Button = tab_buttons[i]
		if btn:
			btn.pressed.connect(_on_tab_pressed.bind(i))
	
	_check_game_context()
	_return_to_main_buttons()


func _check_game_context() -> void:
	print("UI: Checking game context for SaveManager and Pause state.")
	if SaveManager.has_method("has_saves"):
		var saves_exist: bool = SaveManager.has_saves() as bool
		load_button.visible = saves_exist

	if get_parent().has_method("toggle_pause"):
		continue_button.show()
		restart_button.show()
		save_button.show()
		new_game_button.text = "End Run" 
	else:
		continue_button.hide()
		restart_button.hide()
		save_button.hide()


func _return_to_main_buttons() -> void:
	print("UI: Player routed to Main Buttons.")
	main_buttons.visible = true
	options_menu.visible = false
	save_load_panel.visible = false


func _on_resume_pressed() -> void:
	print("UI: Player clicked Resume.")
	var parent: Node = get_parent()
	if parent and parent.has_method("toggle_pause"):
		parent.call("toggle_pause")


func _on_new_game_pressed() -> void:
	print("UI: Player clicked New Game.")
	if not has_calibrated:
		_apply_bucket_calibration()

	main_buttons.hide()
	var chapter_window: Node = CHAPTER_SCREEN.instantiate()
	add_child(chapter_window)


func _on_start_game_pressed() -> void:
	print("UI: Player clicked Restart Game.")
	if not has_calibrated:
		_apply_bucket_calibration()

	get_tree().paused = false
	if get_parent().has_method("toggle_pause"):
		get_tree().reload_current_scene()


func _on_options_pressed() -> void:
	print("UI: Player clicked Options.")
	main_buttons.visible = false
	save_load_panel.visible = false
	options_menu.visible = true
	
	# Open the first tab automatically so the panel isn't empty
	if tab_buttons.size() > 0 and option_panels.size() > 0:
		_on_tab_pressed(0)


func _on_load_pressed() -> void:
	print("UI: Player clicked Load Game.")
	main_buttons.visible = false
	options_menu.visible = false
	save_load_panel.visible = true


func _on_exit_pressed() -> void:
	print("UI: Player clicked Exit.")
	get_tree().quit()


func _on_tab_pressed(tab_index: int) -> void:
	print("UI: Switched to options tab index: ", tab_index)
	for i: int in range(option_panels.size()):
		if option_panels[i]:
			option_panels[i].visible = (i == tab_index)


func _apply_bucket_calibration() -> void:
	print("System: Running mouse sensitivity bucket calibration.")
	# If the user has already manually set a sensitivity, skip calibration
	var saved_sens: Variant = GlobalSettings.get_setting("Settings", "mouse_sensitivity", null)
	if saved_sens != null:
		has_calibrated = true
		return

	has_calibrated = true
	var auto_sens: float = DEFAULT_SENSITIVITY

	# 7-TIER BUCKET SYSTEM (0.05 to 0.70)
	if max_mouse_speed > 6500.0:
		auto_sens = 0.70
		print("System: Calibrated TIER 7 - Extreme (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 5000.0:
		auto_sens = 0.50
		print("System: Calibrated TIER 6 - Fast (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 4000.0:
		auto_sens = 0.40
		print("System: Calibrated TIER 5 - Moderately Fast (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 3000.0:
		auto_sens = 0.30
		print("System: Calibrated TIER 4 - Average (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 2000.0:
		auto_sens = 0.20
		print("System: Calibrated TIER 3 - Moderately Low (Speed: ", max_mouse_speed, ")")
	elif max_mouse_speed > 1000.0:
		auto_sens = 0.10
		print("System: Calibrated TIER 2 - Low (Speed: ", max_mouse_speed, ")")
	else:
		auto_sens = 0.05
		print("System: Calibrated TIER 1 - Precise (Speed: ", max_mouse_speed, ")")

	GlobalSettings.save_setting("Settings", "mouse_sensitivity", auto_sens)


func _input(event: InputEvent) -> void:
	# 1. Background mouse speed tracking for auto-calibration
	if not has_calibrated and event is InputEventMouseMotion:
		var current_speed: float = event.velocity.length()
		if current_speed > max_mouse_speed:
			max_mouse_speed = current_speed

	# 2. Standard UI routing
	if event.is_action_pressed("ui_cancel"):
		if not self.visible:
			return
		
		if options_menu.visible or save_load_panel.visible:
			_return_to_main_buttons()
			get_viewport().set_input_as_handled()
		elif main_buttons.visible and get_parent().has_method("toggle_pause"):
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
