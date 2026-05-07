extends CanvasLayer

@onready var main_buttons: VBoxContainer = $MarginContainer/MainButtons
@onready var options: Panel = $Options
@onready var controls_panel: Panel = $ControlsPanel

@onready var continue_button: Button = %Continue
@onready var new_game_button: Button = %NewGame
@onready var restart_button: Button = %RestartGame

# --- EXPLICIT UI REFERENCES ---
@onready var sens_slider: HSlider = %MouseSensitivitySlider
@onready var sens_label: Label = %MouseSensitivityLabel
@onready var sens_input: LineEdit = %MouseSensitivityLine

# --- AUTOMATED REMAPPING ---
var is_remapping: bool = false
var action_to_remap: String = ""
var remapping_button: Button = null

# --- NEW SWAP VARIABLES ---
var pending_swap_event: InputEvent = null
var pending_conflict_action: String = ""

# List every action exactly as it appears in your Project Settings > Input Map
var my_actions := [
	"forward", "backward", "left", "right", 
	"jump", "crouch", "interact", "flashlight", 
	"zoom", "noclip", "console"
]

const SAVE_PATH = "user://settings.cfg"
# Tweak this to find the perfect "First Time Playing" speed!
const DEFAULT_SENSITIVITY: float = 0.05 
# --- AUTO-CALIBRATION VARIABLES ---
var max_mouse_speed: float = 0.0
var has_calibrated: bool = false # Prevents overwriting if they already saved a preference

const CHAPTER_SCREEN = preload("res://scenes/ChapterScreen.tscn")

func _ready() -> void:
	# 1. Connect signals FIRST
	sens_slider.value_changed.connect(_on_sensitivity_changed)
	sens_slider.drag_ended.connect(_on_sensitivity_drag_ended) 
	
	if has_node("%MouseSensitivityLine"):
		sens_input.text_submitted.connect(_on_sensitivity_input_submitted)
		
	continue_button.pressed.connect(_on_resume_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed) # <-- ADD THIS LINE

	# 2. Load from file
	load_controls()
	
	# 3. CONTEXT CHECK: Are we at the Title Screen or in the Game?
	if get_parent().has_method("toggle_pause"):
		# We are IN-GAME (Attached to the Player)
		continue_button.show()
		restart_button.show() # Show Restart button
		#restart_button.text = "Restart Level" 
		#new_game_button.text = "Select Level" # Optional: rename it while in-game so it makes sense!
	else:
		# We are at the MAIN MENU (First time launch)
		continue_button.hide()
		restart_button.hide() # <-- HIDE Restart Level on the Main Menu
		new_game_button.text = ""
	
	# 4. Set up the UI visibility
	main_buttons.visible = true
	options.visible = false
	controls_panel.visible = false
	create_control_list()

func create_control_list() -> void:
	var container := $ControlsPanel/VBoxContainer
	var template := $ControlsPanel/VBoxContainer/RemapButtonTemplate
	
	for action: String in my_actions:
		var new_button := template.duplicate()
		new_button.show()
		container.add_child(new_button)
		new_button.set_meta("action", action)
		update_button_text(new_button, action)
		new_button.toggled.connect(_on_any_remap_button_toggled.bind(new_button))

func _on_any_remap_button_toggled(toggled_on: bool, button: Button) -> void:
	if toggled_on:
		is_remapping = true
		remapping_button = button
		action_to_remap = button.get_meta("action")
		button.text = "Press any key..."
	else:
		is_remapping = false
		pending_swap_event = null 
		update_button_text(button, button.get_meta("action"))

func update_button_text(button: Button, action: String) -> void:
	var events := InputMap.action_get_events(action)
	var key_name := "Unassigned"
	
	if events.size() > 0:
		var raw_text := events[0].as_text()
		key_name = raw_text.replace(" (Physical)", "") \
						   .replace(" - Physical", "") \
						   .replace(" (Physics)", "") \
						   .replace(" - Physics", "") \
						   .strip_edges()
						
	button.text = action.capitalize() + ": " + key_name

# This handles the %NewGame button
func _on_new_game_pressed() -> void:
	if not has_calibrated:
		_apply_bucket_calibration()
		
	# 1. Hide the menu buttons so they don't overlap the Chapter Screen
	main_buttons.hide() 
	
	# 2. Spawn the Chapter Screen ON TOP of this menu
	var chapter_window := CHAPTER_SCREEN.instantiate()
	add_child(chapter_window)

# This handles the %StartGame button (Which now strictly acts as "Restart Level")
func _on_start_game_pressed() -> void:
	if not has_calibrated:
		_apply_bucket_calibration()
		
	get_tree().paused = false
	
	# Reloads whatever the current active level is
	if get_parent().has_method("toggle_pause"):
		get_tree().reload_current_scene()

func _apply_bucket_calibration() -> void:
	has_calibrated = true
	var auto_sens: float = DEFAULT_SENSITIVITY
	
	# BUCKET 1: Twitchy / Wrist Aimers / High Speed
	# They like their cursor fast in the menu, so give them a fast 3D camera!
	if max_mouse_speed > 4000.0:
		auto_sens = 0.5 # Your preferred speed!
		print("Calibrated: FAST Bucket (Top Menu Speed: ", max_mouse_speed, ")")
		
	# BUCKET 2: Medium / Average Users
	elif max_mouse_speed > 1500.0:
		auto_sens = 0.1
		print("Calibrated: MEDIUM Bucket (Top Menu Speed: ", max_mouse_speed, ")")
		
	# BUCKET 3: Arm Aimers / Precise Users
	# Their menu cursor is slow, so they want precise, low 3D aiming.
	else:
		auto_sens = 0.05
		print("Calibrated: PRECISE Bucket (Top Menu Speed: ", max_mouse_speed, ")")

	# Update the slider (which automatically applies it to the player)
	sens_slider.value = auto_sens
	
	# Save it to disk so they don't get auto-calibrated again next time
	_save_sensitivity_to_disk(auto_sens)
	
func _on_exit_pressed() -> void:
	get_tree().quit()

func _on_options_pressed() -> void:
	main_buttons.visible = false
	options.visible = true
	controls_panel.visible = false

func _on_back_pressed() -> void:
	main_buttons.visible = true
	options.visible = false
	controls_panel.visible = false

func _on_contols_pressed() -> void:
	options.visible = false
	controls_panel.visible = true

func _on_back_controls_pressed() -> void:
	options.visible = true
	controls_panel.visible = false
		
func _input(event: InputEvent) -> void:
	if is_remapping:
		if event is InputEventKey or event is InputEventMouseButton:
			if event.is_pressed():
				
				# 1. Did they press the exact same key again to confirm a swap?
				if pending_swap_event != null and event.as_text() == pending_swap_event.as_text():
					execute_swap(event)
					return
				
				# 2. Check for conflicts
				var conflicting_action := get_action_with_event(event)
				
				if conflicting_action != "" and conflicting_action != action_to_remap:
					pending_swap_event = event
					pending_conflict_action = conflicting_action
					
					var key_name := event.as_text().split("(")[0].strip_edges()
					%ConflictLabel.text = action_to_remap.capitalize() + " and " + conflicting_action.capitalize() + " use the same key. \nPress [" + key_name + "] again to switch, or press a different key."
					%ConflictPanel.show()
					
					get_tree().create_timer(4.0).timeout.connect(func() -> void: %ConflictPanel.hide())
					get_viewport().set_input_as_handled()
					return 

				# 3. If no conflict, proceed as normal
				InputMap.action_erase_events(action_to_remap)
				InputMap.action_add_event(action_to_remap, event)
				
				save_controls() 
				
				is_remapping = false
				pending_swap_event = null 
				remapping_button.button_pressed = false
				update_button_text(remapping_button, action_to_remap)
				
				%ConflictPanel.hide()
				get_viewport().set_input_as_handled()
	
	# --- NEW: PASSIVE MOUSE TRACKING ---
	# Only track if it's a mouse movement and we haven't calibrated yet
	if not has_calibrated and event is InputEventMouseMotion:
		var current_speed: float = event.velocity.length()
		
		# Keep a record of the absolute fastest flick they do in the menu
		if current_speed > max_mouse_speed:
			max_mouse_speed = current_speed
			
func _on_reset_button_pressed() -> void:
	InputMap.load_from_project_settings()
	
	var dir := DirAccess.open("user://")
	if dir.file_exists("settings.cfg"):
		dir.remove("settings.cfg")
		
	sens_slider.value = DEFAULT_SENSITIVITY 
	
	# --- ADD THESE TWO LINES ---
	has_calibrated = false  # Unlock the auto-calibration
	max_mouse_speed = 0.0   # Reset the speed tracker
	
	refresh_all_button_labels()

func refresh_all_button_labels() -> void:
	var container := $ControlsPanel/VBoxContainer
	for child in container.get_children():
		if child is Button and child.has_meta("action"):
			var action_name: String = child.get_meta("action")
			update_button_text(child, action_name)

func save_controls() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH) 
	
	for action: String in my_actions:
		var events := InputMap.action_get_events(action)
		if events.size() > 0:
			config.set_value("Controls", action, events[0])
	
	config.save(SAVE_PATH)
	print("Controls saved to: ", OS.get_user_data_dir())

func load_controls() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	
	if err != OK: 
		# FIX: Ensure it falls back to the new default, not 0.5
		sens_slider.value = DEFAULT_SENSITIVITY
		return 

	# --- Load Controls ---
	for action: String in my_actions:
		if config.has_section_key("Controls", action):
			var event := config.get_value("Controls", action) as InputEvent
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)
			
	# --- Load Sensitivity ---
	if config.has_section_key("Settings", "mouse_sensitivity"):
		var saved_sens: float = config.get_value("Settings", "mouse_sensitivity")
		sens_slider.value = saved_sens 
		has_calibrated = true # <--- NEW: They already have a save file, disable auto-calibration!
			
func get_action_with_event(new_event: InputEvent) -> String:
	for action: String in my_actions:
		if InputMap.action_has_event(action, new_event):
			return action
	return ""

func execute_swap(new_event: InputEvent) -> void:
	var old_events := InputMap.action_get_events(action_to_remap)
	var old_event := old_events[0] if old_events.size() > 0 else null
	
	InputMap.action_erase_events(action_to_remap)
	InputMap.action_erase_events(pending_conflict_action)
	InputMap.action_add_event(action_to_remap, new_event)
	
	if old_event:
		InputMap.action_add_event(pending_conflict_action, old_event)
		
	save_controls()
	
	is_remapping = false
	pending_swap_event = null
	pending_conflict_action = ""
	remapping_button.button_pressed = false
	
	refresh_all_button_labels() 
	
	%ConflictLabel.text = "Keys swapped successfully!"
	%ConflictPanel.show()
	get_tree().create_timer(2.0).timeout.connect(func() -> void: %ConflictPanel.hide())
	get_viewport().set_input_as_handled()

func _on_resume_pressed() -> void:
	if get_parent().has_method("toggle_pause"):
		get_parent().toggle_pause()


# ==========================================
# SENSITIVITY SYSTEM & DISK I/O FIXES
# ==========================================

# 1. Real-time Player Updates (Fires constantly while dragging)
func _on_sensitivity_changed(value: float) -> void:
	sens_label.text = "Mouse Sensitivity: "
	
	# Sync the text box
	if not sens_input.has_focus():
		sens_input.text = "%.2f" % value

	# Update the player immediately so they feel the change
	var player := get_parent()
	if player and "mouse_sensitivity_base" in player:
		player.mouse_sensitivity_base = value
		player.mouse_sensitivity = value
		player.mouse_sensitivity_zoom = value / 10.0

# 2. Disk Saving for Slider (Fires ONCE when the player lets go of the mouse click)
func _on_sensitivity_drag_ended(value_changed: bool) -> void:
	if value_changed:
		_save_sensitivity_to_disk(sens_slider.value)

# 3. Disk Saving for Text Input (Fires ONCE when they hit Enter)
func _on_sensitivity_input_submitted(new_text: String) -> void:
	var new_val: float = new_text.to_float()
	
	# Prevent players from typing 9999 and breaking the camera
	new_val = clamp(new_val, 0.01, 1.0) 
	
	# This automatically triggers _on_sensitivity_changed to update the player
	sens_slider.value = new_val 
	sens_input.release_focus()
	
	# Save to disk!
	_save_sensitivity_to_disk(new_val)

# 4. Helper function to keep disk operations clean
func _save_sensitivity_to_disk(value: float) -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH) 
	config.set_value("Settings", "mouse_sensitivity", value)
	config.save(SAVE_PATH)
