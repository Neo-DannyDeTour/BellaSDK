@tool
## Physical label creating dynamic collision box for TTS and screen readers.
## Uses [Label3D] visual bounds and interacts via [InteractionManager].
class_name AccessibleLabel
extends StaticBody3D

## The visual text string displayed on the child [Label3D] node.
@export_multiline var display_text: String = "Accessible Label":
	set(value):
		display_text = value
		if is_inside_tree():
			_update_label_text()
			_update_collision_shape()

## Phonetic alternative text read by the TTS engine instead of [member display_text].
@export_multiline var tts_alt_text: String = "":
	set(value):
		tts_alt_text = value
		if is_inside_tree():
			_update_tts_text()

## Controls whether the child [Label3D] automatically faces the active camera.
@export var billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_DISABLED:
	set(value):
		billboard_mode = value
		if is_inside_tree():
			_update_billboard_mode()

## Cached reference to the child [Label3D] node.
@onready var _label_node: Label3D = NodeQuery.find_first_child_of_type(self, Label3D) as Label3D

## Cached reference to the child [CollisionShape3D] bounding shape.
@onready var _col_shape: CollisionShape3D = (
	NodeQuery.find_first_child_of_type(self, CollisionShape3D) as CollisionShape3D
)

## Cached reference to the child interaction component node.
@onready var _interact_comp: Node = _resolve_interact_component()

## Guard flag tracking lifecycle readiness for editor updates.
var _is_ready: bool = false


## Initializes cached nodes, sets physics layer, and recalculates bounds.
func _ready() -> void:
	print("AccessibleLabel: Initializing on physics interactive layer.")
	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = 0
	_is_ready = true
	_update_label_text()
	_update_billboard_mode()
	_update_tts_text()
	_update_collision_shape()


## Updates visual text displayed on the child [Label3D].
func _update_label_text() -> void:
	print("AccessibleLabel: Updating visual label text to: ", display_text)
	var label: Label3D = _get_label_node()
	if is_instance_valid(label):
		label.text = display_text


## Synchronizes phonetic override text with the child interaction component.
func _update_tts_text() -> void:
	print("AccessibleLabel: Synchronizing TTS text override.")
	var interact_comp: Node = _get_interact_component()
	if is_instance_valid(interact_comp):
		interact_comp.set("alt_text_override", tts_alt_text)


## Updates billboard camera-facing orientation on the child [Label3D].
func _update_billboard_mode() -> void:
	print("AccessibleLabel: Setting billboard mode to: ", billboard_mode)
	var label: Label3D = _get_label_node()
	if is_instance_valid(label):
		label.billboard = billboard_mode


## Resizes [BoxShape3D] to match visual text bounds without runtime reallocations.
func _update_collision_shape() -> void:
	print("AccessibleLabel: Updating collision shape bounds.")
	if not is_inside_tree():
		return

	var col_shape: CollisionShape3D = _get_collision_shape()
	var label_node: Label3D = _get_label_node()
	if not is_instance_valid(col_shape) or not is_instance_valid(label_node):
		return

	var tree: SceneTree = get_tree()
	if is_instance_valid(tree):
		await tree.process_frame

	if not is_inside_tree():
		return
	if not is_instance_valid(col_shape) or not is_instance_valid(label_node):
		return

	var box: BoxShape3D = col_shape.shape as BoxShape3D
	if not is_instance_valid(box):
		box = BoxShape3D.new()
		col_shape.shape = box

	var aabb: AABB = label_node.get_aabb()
	var new_size: Vector3 = Vector3(maxf(aabb.size.x, 0.1), maxf(aabb.size.y, 0.1), 0.25)
	box.size = new_size
	col_shape.position = aabb.position + (aabb.size * 0.5)

	print("AccessibleLabel: Resized collision shape bounds to: ", box.size)


## Resolves and returns the child [Label3D] using cached reference or [NodeQuery].
func _get_label_node() -> Label3D:
	print("AccessibleLabel: Resolving [Label3D] reference.")
	if not is_instance_valid(_label_node):
		_label_node = NodeQuery.find_first_child_of_type(self, Label3D) as Label3D
	return _label_node


## Resolves and returns the child [CollisionShape3D] using cache or [NodeQuery].
func _get_collision_shape() -> CollisionShape3D:
	print("AccessibleLabel: Resolving [CollisionShape3D] reference.")
	if not is_instance_valid(_col_shape):
		_col_shape = (
			NodeQuery.find_first_child_of_type(self, CollisionShape3D) as CollisionShape3D
		)
	return _col_shape


## Resolves and returns the interaction component using cached reference.
func _get_interact_component() -> Node:
	print("AccessibleLabel: Resolving interaction component reference.")
	if not is_instance_valid(_interact_comp):
		_interact_comp = _resolve_interact_component()
	return _interact_comp


## Locates the interaction component child node without string path lookups.
func _resolve_interact_component() -> Node:
	print("AccessibleLabel: Resolving child interaction component.")
	for child: Node in get_children():
		if child.name == &"InteractComponent" or child.is_class("InteractComponent"):
			return child
	return null


## Sets the display text and recalculates collision bounding box.
func set_text(new_text: String) -> void:
	print("AccessibleLabel: Setting text programmatically to: ", new_text)
	display_text = new_text
