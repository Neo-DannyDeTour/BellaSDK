extends Panel

var is_remapping: bool = false
var action_to_remap: String = ""
var remapping_button: Button = null

var pending_swap_event: InputEvent = null
var pending_conflict_action: String = ""

var max_mouse_speed: float = 0.0
var has_calibrated: bool = false

var my_actions: Array[String] = [
	"forward", "backward", "left", "right", "jump", 
	"crouch", "interact", "flashlight", "zoom"
]

func _ready() -> void:
	print("UI: Controls Panel initialized.")
	_create_control_list()
	_load_controls()

func _create_control_list() -> void:
	print("UI: Building control remap list.")
	var container: VBoxContainer = $VBoxContainer
	var template: Button = $VBoxContainer/RemapButtonTemplate
	
	for action: String in my_actions:
		var new_button: Button = template.duplicate() as Button
		new_button.show()
		container.add_child(new_button)
		new_button.set_meta("action", action)
		_update_button_text(new_button, action)
		new_button.toggled.connect(_on_any_remap_button_toggled.bind(new_button))

func _update_button_text(button: Button, action: String) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var key_name: String = "Unassigned"
	if events.size() > 0:
		key_name = events[0].as_text().replace(" (Physical)", "").strip_edges()
	button.text = action.capitalize() + ": " + key_name

func _on_any_remap_button_toggled(toggled_on: bool, button: Button) -> void:
	if toggled_on:
		print("Player initiated key remap for: ", button.get_meta("action"))
		is_remapping = true
		remapping_button = button
		action_to_remap = button.get_meta("action")
		button.text = "Press any key..."
	else:
		is_remapping = false
		pending_swap_event = null
		_update_button_text(button, button.get_meta("action"))

func _input(event: InputEvent) -> void:
	if not self.visible:
		return
		
	if is_remapping:
		if event is InputEventKey or event is InputEventMouseButton:
			if event.is_pressed():
				print("Player pressed key for remap: ", event.as_text())
				InputMap.action_erase_events(action_to_remap)
				InputMap.action_add_event(action_to_remap, event)
				
				_save_controls()
				is_remapping = false
				remapping_button.button_pressed = false
				_update_button_text(remapping_button, action_to_remap)
				get_viewport().set_input_as_handled()

func _save_controls() -> void:
	print("System: Saving custom input mappings.")
	for action: String in my_actions:
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.size() > 0:
			GlobalSettings.save_setting("Controls", action, events[0])

func _load_controls() -> void:
	print("System: Loading custom input mappings.")
	for action: String in my_actions:
		var event: Variant = GlobalSettings.get_setting("Controls", action, null)
		if event and event is InputEvent:
			InputMap.action_erase_events(action)
			InputMap.action_add_event(action, event)
