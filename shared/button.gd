@tool
## An interactable button that players can press to send power signals globally or locally.
##
## Animates a physical depression, plays sound, and relays state via an [OutputTransmitter3D].
## Can also broadcast global events across scenes.
class_name LogicButton
extends StaticBody3D

@export_category("Button References")
# Drag the node you want to physically move down here (e.g., the 'button' Node3D)
## The visual part of the button that moves down when pressed.
@export var pressable_part: Node3D
# Drag the actual mesh you want to glow here (e.g., 'Circle_017')
## The specific mesh instance that receives the highlight effect.
@export var mesh_to_highlight: MeshInstance3D
## The shader material applied to outline the button.
@export var outline_material: ShaderMaterial

## If populated, this button will broadcast this string to the Event Bus across all scenes.
@export_category("Global Architecture")
@export var global_event_name: String = ""

## The component used to send signals to local targets.
@export_category("Local Connections")
@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		_sync_transmitter()

# The targets are back on the parent for easy level design access.
# Whenever this changes in the Inspector, it updates the child.
## List of target nodes to activate when the button is pressed.
@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_sync_transmitter()

## The audio player for the mechanical click sound.
@export var click_sound: AudioStreamPlayer3D

## Internal tween handling the physical button press animation.
var press_tween: Tween
## State flag indicating if the button is currently available to be pressed.
var can_press: bool = true

## Reference to the internal interaction handler.
@onready var interact_component: InteractComponent = $InteractComponent
## Reference to the internal highlighting handler.
@onready var highlight_component: HighlightComponent = $HighlightComponent
## Reference to the 3D label displaying interaction prompts.
@onready var label_interact: Label3D = $LabelInteract


## Connects the interact component signals and synchronizes the target list.
func _ready() -> void:
	_sync_transmitter()

	if is_instance_valid(interact_component) and not Engine.is_editor_hint():
		interact_component.focused.connect(_on_focus)
		interact_component.unfocused.connect(_on_unfocus)

		if not interact_component.interacted.is_connected(_on_interact):
			interact_component.interacted.connect(_on_interact)

	if is_instance_valid(label_interact):
		label_interact.hide()


## Pushes the assigned targets list to the connected transmitter.
func _sync_transmitter() -> void:
	# Automatically pass the targets to the transmitter so it can handle the local logic
	if is_instance_valid(transmitter):
		transmitter.targets = targets


## Displays interact label and highlighting material when focused.
func _on_focus() -> void:
	if is_instance_valid(label_interact):
		label_interact.show()
	if is_instance_valid(mesh_to_highlight) and is_instance_valid(outline_material):
		mesh_to_highlight.material_overlay = outline_material


## Hides interact label and removes highlighting material when unfocused.
func _on_unfocus() -> void:
	if is_instance_valid(label_interact):
		label_interact.hide()
	if is_instance_valid(mesh_to_highlight):
		mesh_to_highlight.material_overlay = null


## Receives the interaction signal from the player and toggles the button state.
func _on_interact(_player: CharacterBody3D) -> void:
	if not is_instance_valid(pressable_part) or not can_press:
		return

	print("Button pressed: Initiating sequence.")
	can_press = false

	if is_instance_valid(click_sound):
		click_sound.play()

	if is_instance_valid(highlight_component):
		highlight_component.suppress(true)

	if press_tween and press_tween.is_valid():
		press_tween.kill()

	press_tween = create_tween()

	var base_y: float = pressable_part.position.y

	(
		press_tween
		. tween_property(pressable_part, "position:y", base_y - 0.02, 0.1)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	(
		press_tween
		. tween_property(pressable_part, "position:y", base_y, 0.15)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)

	var is_turning_on: bool = true

	# 1. Local Legacy Trigger
	if is_instance_valid(transmitter):
		print("Button executing: Toggling local transmitter state.")
		if transmitter.is_active:
			is_turning_on = false
			transmitter.power_off()
		else:
			is_turning_on = true
			transmitter.power_on()
	else:
		print("Button executing: No local transmitter assigned.")

	# 2. Global Event Bus Trigger (Cross-Scene Decoupling)
	if global_event_name != "":
		print("Button executing: Broadcasting global event -> ", global_event_name)
		Events.level_event_triggered.emit(global_event_name, is_turning_on)

	await get_tree().create_timer(1.0).timeout
	can_press = true

	if is_instance_valid(highlight_component):
		highlight_component.suppress(false)
