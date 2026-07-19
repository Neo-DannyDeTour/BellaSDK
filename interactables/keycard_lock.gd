@tool
class_name KeycardLock
extends Node3D

signal access_granted

@export_category("Lock Settings")
## Type the exact ID of the required card here (e.g., "A1", "Admin")
@export var required_card_id: StringName = &"R"
## Set the visual glow color for this lock manually
@export var lock_color: Color = Color.RED
@export var reader_mesh: GeometryInstance3D
@export var status_label: Label3D
## Type this directly to your component class for better autocomplete
@export var interact_component: InteractComponent

@export_category("Transmitter Settings")
## Drag the child OutputTransmitter3D here.
@export var output_transmitter: OutputTransmitter3D:
	set(value):
		output_transmitter = value
		_update_editor_targets()

## Assign your targets here in the parent inspector.
@export var transmitter_targets: Array[Node3D] = []:
	set(value):
		transmitter_targets = value
		_update_editor_targets()

var _is_unlocked: bool = false
var _reader_material: StandardMaterial3D
var _cached_requirement_text: String = ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	print("KeycardLock: Initialized. Requires card ID: ", required_card_id)

	_cached_requirement_text = "LOCKED - requires %s card" % required_card_id

	_setup_reader_visuals()
	_setup_transmitter()

	if is_instance_valid(interact_component):
		if interact_component.has_signal("interacted"):
			interact_component.interacted.connect(_on_interacted)
		if interact_component.has_signal("focused"):
			interact_component.focused.connect(_on_focused)
		if interact_component.has_signal("unfocused"):
			interact_component.unfocused.connect(_on_unfocused)


func _update_editor_targets() -> void:
	if Engine.is_editor_hint() and is_instance_valid(output_transmitter):
		output_transmitter.targets = transmitter_targets


func _setup_transmitter() -> void:
	print("KeycardLock: Setting up transmitter targets.")
	if is_instance_valid(output_transmitter):
		output_transmitter.targets = transmitter_targets


func _setup_reader_visuals() -> void:
	print("KeycardLock: Setting up reader glow materials.")
	if is_instance_valid(reader_mesh):
		_reader_material = StandardMaterial3D.new()
		_reader_material.albedo_color = lock_color
		_reader_material.emission_enabled = true
		_reader_material.emission = lock_color
		_reader_material.emission_energy_multiplier = 2.0
		reader_mesh.material_override = _reader_material

	if is_instance_valid(status_label):
		status_label.text = ""  # Start completely blank
		status_label.modulate = lock_color


func _on_interacted(_interactor: CharacterBody3D) -> void:
	print("KeycardLock: Interacted by player.")
	if _is_unlocked:
		print("KeycardLock: Already unlocked. Ignoring.")
		return

	if KeycardSystem.has_card(required_card_id):
		print("KeycardLock: Correct card found. Unlocking.")
		KeycardSystem.consume_card(required_card_id)
		_unlock()
	else:
		print("KeycardLock: Incorrect or missing card. Access denied.")
		_deny_access()


func _on_focused() -> void:
	print("KeycardLock: Player focused lock. Displaying requirement.")
	if _is_unlocked:
		return

	if is_instance_valid(status_label):
		status_label.text = _cached_requirement_text


func _on_unfocused() -> void:
	print("KeycardLock: Player unfocused lock. Hiding text.")
	if _is_unlocked:
		return

	if is_instance_valid(status_label):
		status_label.text = ""


func _unlock() -> void:
	_is_unlocked = true
	print("KeycardLock: Access granted. Firing signals.")
	access_granted.emit()

	if is_instance_valid(output_transmitter):
		output_transmitter.power_on()

	if is_instance_valid(_reader_material):
		_reader_material.albedo_color = Color.GREEN
		_reader_material.emission = Color.GREEN

	if is_instance_valid(status_label):
		status_label.text = "GRANTED"
		status_label.modulate = Color.GREEN


func _deny_access() -> void:
	print("KeycardLock: Playing access denied animation.")
	if is_instance_valid(status_label):
		status_label.text = "DENIED"
		var tween: Tween = create_tween()
		tween.tween_property(status_label, "modulate", Color.RED, 0.1)
		tween.tween_property(status_label, "modulate", Color.WHITE, 0.1)
		tween.tween_property(status_label, "modulate", Color.RED, 0.1)

		tween.finished.connect(
			func() -> void:
				print("KeycardLock: Denied animation finished. Reverting text.")
				if not _is_unlocked and is_instance_valid(status_label):
					if (
						is_instance_valid(interact_component)
						and interact_component.is_currently_focused
					):
						status_label.text = _cached_requirement_text
					else:
						status_label.text = ""

					status_label.modulate = lock_color
		)
