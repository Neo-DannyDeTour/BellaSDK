extends Panel
class_name ControlsPanel

## Indicates if the player is currently pressing a key to remap an action.
var is_remapping: bool = false

## The specific input action string (e.g., "forward") currently being remapped.
var action_to_remap: String = ""

## Reference to the UI button currently waiting for player input.
var remapping_button: Button = null

## List of all input actions available for the player to remap in the UI.
var my_actions: Array[String] = [
	"forward", "backward", "left", "right", "jump", 
	"crouch", "sprint", "interact", "flashlight", "zoom"
]

## Container that holds the generated list of remappable actions.
@onready var grid_container: GridContainer = %GridContainer

## Template label used to display the action name.
@onready var action_label_template: Label = %ActionLabelTemplate

## Template button used to trigger the remapping process.
@onready var remap_button_template: Button = %RemapButtonTemplate


func _ready() -> void:
	print("UI: Controls Panel initialized.")
	_create_control_list()


func _create_control_list() -> void:
	print("UI: Building GridContainer control list.")
	for action: String in my_actions:
		var action_label: Label = action_label_template.duplicate() as Label
		var remap_btn: Button = remap_button_template.duplicate() as Button

		action_label.show()
		remap_btn.show()

		grid_container.add_child(action_label)
		grid_container.add_child(remap_btn)

		action_label.text = action.capitalize()
		remap_btn.set_meta("action", action)

		_update_button_text(remap_btn, action)
		remap_btn.toggled.connect(_on_any_remap_button_toggled.bind(remap_btn))

	action_label_template.queue_free()
	remap_button_template.queue_free()


func _update_button_text(button: Button, action: String) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var key_name: String = "Unassigned"

	if events.size() > 0:
		key_name = events[0].as_text().replace(" (Physical)", "").strip_edges()

	button.text = key_name


func _on_any_remap_button_toggled(toggled_on: bool, button: Button) -> void:
	if toggled_on:
		print("UI: Player initiated key remap for: ", button.get_meta("action"))
		is_remapping = true
		remapping_button = button
		action_to_remap = button.get_meta("action")
		button.text = "Press any key..."
	else:
		print("UI: Player canceled key remap for: ", button.get_meta("action"))
		is_remapping = false
		_update_button_text(button, button.get_meta("action"))


func _input(event: InputEvent) -> void:
	if not self.visible:
		return

	if is_remapping:
		if event is InputEventKey or event is InputEventMouseButton:
			if event.is_pressed():
				print("System: Player pressed key for remap: ", event.as_text())
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
