@tool
## A physical label that can be interacted with to support TTS and screen readers.
##
## [AccessibleLabel] creates a dynamic collision box that matches the visual size of the text.
## When a player looks at it using the [InteractionScanner], it can read the text aloud
## via the [TTSInteractComponent], or use an alternative phonetic text.
class_name AccessibleLabel
extends StaticBody3D

## The text displayed visually on the in-game Label3D.
@export_multiline var display_text: String = "Accessible Label":
	set(value):
		display_text = value
		if is_inside_tree() and has_node("Label3D"):
			var label: Node = get_node("Label3D")
			if is_instance_valid(label):
				label.set("text", display_text)
			_update_collision_shape()

## The phonetic text read by the TTS engine. If empty, the system reads display_text.
@export_multiline var tts_alt_text: String = "":
	set(value):
		tts_alt_text = value
		if is_inside_tree() and has_node("InteractComponent"):
			var interact_comp: Node = get_node("InteractComponent")
			if is_instance_valid(interact_comp):
				interact_comp.set("alt_text_override", tts_alt_text)

## Controls whether the label automatically faces the camera.
@export var billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_DISABLED:
	set(value):
		billboard_mode = value
		if is_inside_tree() and has_node("Label3D"):
			var label: Node = get_node("Label3D")
			if is_instance_valid(label):
				label.set("billboard", billboard_mode)


## Called when the node enters the scene tree for the first time.
## Sets initial properties and resizes the collision shape.
func _ready() -> void:
	print("AccessibleLabel: Initializing...")
	$Label3D.text = display_text
	$Label3D.billboard = billboard_mode

	if has_node("InteractComponent"):
		$InteractComponent.alt_text_override = tts_alt_text

	_update_collision_shape()


## Dynamically resizes a unique collision shape to match the visual dimensions of the Label3D text.
func _update_collision_shape() -> void:
	if not is_inside_tree():
		return

	var col_shape: CollisionShape3D = $CollisionShape3D
	var label_node: Label3D = $Label3D

	if not is_instance_valid(col_shape) or not is_instance_valid(label_node):
		return

	await get_tree().process_frame

	# Create a completely new BoxShape3D so instances do not share the same resource
	var box: BoxShape3D = BoxShape3D.new()
	col_shape.shape = box

	var aabb: AABB = label_node.get_aabb()

	var new_size: Vector3 = Vector3(maxf(aabb.size.x, 0.1), maxf(aabb.size.y, 0.1), 0.25)
	box.size = new_size
	col_shape.position = aabb.position + (aabb.size / 2.0)

	print("AccessibleLabel: Created unique collision shape resized to: ", box.size)
