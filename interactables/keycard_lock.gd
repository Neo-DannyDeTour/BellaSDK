@tool
## A security terminal that validates global keycard states against a required clearance ID.
##
## On success, delegates power delivery to a bound [OutputTransmitter3D]. Manages 3D textual
## prompts and custom material glows to indicate denied or granted access states.
class_name KeycardLock
extends Node3D

## Emitted immediately when the player successfully presents the required keycard.
signal access_granted

@export_category("Lock Settings")
## The exact ID of the required card (e.g., "A1", "Admin"). Must match [KeycardData].
@export var required_card_id: StringName = &"R"
## Sets the visual glow color for this lock manually before it is solved.
@export var lock_color: Color = Color.RED
## The 3D geometry piece that receives the colored glow override material.
@export var reader_mesh: GeometryInstance3D
## The floating text label that displays lock status and prompts.
@export var status_label: Label3D
## The interaction script that casts raycasts and routes player inputs.
@export var interact_component: InteractComponent

@export_category("Transmitter Settings")
## The specific transmitter component used to send signals to connected devices.
@export var output_transmitter: OutputTransmitter3D:
	set(value):
		output_transmitter = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_editor_targets()

## Array of external nodes triggered when this lock is successfully solved.
@export var transmitter_targets: Array[Node3D] = []:
	set(value):
		transmitter_targets = value
		if is_inside_tree() and Engine.is_editor_hint():
			_update_editor_targets()

## Prevents checking the global inventory array again if the lock is already solved.
var _is_unlocked: bool = false
## Generated material instance to allow per-lock glow animations.
var _reader_material: StandardMaterial3D
## Formatted text string generated on ready to avoid string concatenation during loops.
var _cached_requirement_text: String = ""


## Initializes visual states, caches strings, and connects to the interaction system.
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


## Passes the exported target array down to the transmitter script within the editor.
func _update_editor_targets() -> void:
	if Engine.is_editor_hint() and is_instance_valid(output_transmitter):
		output_transmitter.targets = transmitter_targets


## Synchronizes the target array upon level load to ensure the puzzle logic triggers correctly.
func _setup_transmitter() -> void:
	print("KeycardLock: Setting up transmitter targets.")
	if is_instance_valid(output_transmitter):
		output_transmitter.targets = transmitter_targets


## Duplicates material to apply runtime glow properties based on [member lock_color].
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


## Verifies the global inventory singleton for the required ID upon player interaction.
## [param _interactor]: The player character.
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


## Displays the required ID text when the player aims at the lock.
func _on_focused() -> void:
	print("KeycardLock: Player focused lock. Displaying requirement.")
	if _is_unlocked:
		return

	if is_instance_valid(status_label):
		status_label.text = _cached_requirement_text


## Clears the required ID text when the player looks away.
func _on_unfocused() -> void:
	print("KeycardLock: Player unfocused lock. Hiding text.")
	if _is_unlocked:
		return

	if is_instance_valid(status_label):
		status_label.text = ""


## Triggers connected output nodes and visually shifts the lock state to permanent green.
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


## Initiates a temporary red flashing text sequence if the player lacks clearance.
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
						and interact_component.get("is_currently_focused") == true
					):
						status_label.text = _cached_requirement_text
					else:
						status_label.text = ""

					status_label.modulate = lock_color
		)
