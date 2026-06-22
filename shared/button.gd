@tool
extends StaticBody3D

@export_category("Button References")
# Drag the node you want to physically move down here (e.g., the 'button' Node3D)
@export var pressable_part: Node3D
# Drag the actual mesh you want to glow here (e.g., 'Circle_017')
@export var mesh_to_highlight: MeshInstance3D
@export var outline_material: ShaderMaterial

@export_category("Connections")
@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		_sync_transmitter()

# The targets are back on the parent for easy level design access.
# Whenever this changes in the Inspector, it updates the child.
@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_sync_transmitter()

@export var click_sound: AudioStreamPlayer3D

var press_tween: Tween
var can_press: bool = true

@onready var interact_component: Interact_Component = $Interact_Component
@onready var highlight_component: HighlightComponent = $HighlightComponent
@onready var label_interact: Label3D = $LabelInteract


func _ready() -> void:
	_sync_transmitter()
	
	if is_instance_valid(interact_component) and not Engine.is_editor_hint():
		interact_component.focused.connect(_on_focus)
		interact_component.unfocused.connect(_on_unfocus)

		if not interact_component.interacted.is_connected(_on_interact):
			interact_component.interacted.connect(_on_interact)

	if is_instance_valid(label_interact):
		label_interact.hide()


func _sync_transmitter() -> void:
	# Automatically pass the targets to the transmitter so it can handle the logic
	if is_instance_valid(transmitter):
		transmitter.targets = targets


func _on_focus() -> void:
	if is_instance_valid(label_interact):
		label_interact.show()
	if is_instance_valid(mesh_to_highlight) and is_instance_valid(outline_material):
		mesh_to_highlight.material_overlay = outline_material


func _on_unfocus() -> void:
	if is_instance_valid(label_interact):
		label_interact.hide()
	if is_instance_valid(mesh_to_highlight):
		mesh_to_highlight.material_overlay = null


func _on_interact(_player: CharacterBody3D) -> void:
	if not is_instance_valid(pressable_part) or not can_press:
		return

	print("Button pressed: Initiating sequence.")
	can_press = false

	if is_instance_valid(click_sound):
		click_sound.play()
	# ---------------------------

	if is_instance_valid(highlight_component):
		highlight_component.suppress(true)

	if press_tween and press_tween.is_valid():
		press_tween.kill()

	press_tween = create_tween()

	var base_y: float = pressable_part.position.y

	(
		press_tween
		.tween_property(pressable_part, "position:y", base_y - 0.02, 0.1)
		.set_trans(Tween.TRANS_CUBIC)
		.set_ease(Tween.EASE_OUT)
	)
	(
		press_tween
		.tween_property(pressable_part, "position:y", base_y, 0.15)
		.set_trans(Tween.TRANS_CUBIC)
		.set_ease(Tween.EASE_IN_OUT)
	)

	if is_instance_valid(transmitter):
		print("Button executing: Toggling transmitter state.")
		if transmitter.is_active:
			transmitter.power_off()
		else:
			transmitter.power_on()
	else:
		print("Button executing: Warning - No transmitter assigned.")

	await get_tree().create_timer(1.0).timeout
	can_press = true

	if is_instance_valid(highlight_component):
		highlight_component.suppress(false)
