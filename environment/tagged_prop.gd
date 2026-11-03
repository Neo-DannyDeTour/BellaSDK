@tool
# class_name TaggedProp
extends Node3D

## Reshapeable level block with configurable shape, color, tag metadata, and debug label.

## Geometric primitive type supported by the level block.
enum PropShape {
	BOX,
	CYLINDER,
	SPHERE,
}

## Group name registered by all tagged props for spatial proximity queries.
const GROUP_TAGGED_PROP: StringName = &"tagged_prop"
## Metadata key read by turret raycasts.
const META_PROP_TAG: StringName = &"prop_tag"
## Shader parameter key controlling per-instance albedo color.
const PARAM_PROP_COLOR: StringName = &"prop_color"
## Preloaded lightweight spatial shader supporting instance color uniforms.
const PROP_SHADER: Shader = preload("res://shaders/tagged_prop.gdshader")

## Tactical cover category used by sensor turrets to classify blocking obstacles.
@export var prop_tag: String = "pillar":
	set(value):
		prop_tag = value
		_update_tag()

## Per-instance albedo tint applied via instance shader parameter.
@export var prop_color: Color = Color(0.2, 0.22, 0.25):
	set(value):
		prop_color = value
		_update_color()

## Primitive geometry shape for level blockout.
@export var prop_shape: PropShape = PropShape.BOX:
	set(value):
		prop_shape = value
		_update_shape()

## Dimensional extents of the prop bounding volume (XYZ).
@export var size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		size = Vector3(maxf(value.x, 0.05), maxf(value.y, 0.05), maxf(value.z, 0.05))
		_update_bounds()

## Whether the debug billboard label is displayed above the block.
@export var show_label: bool = true:
	set(value):
		show_label = value
		_update_label_visibility()

## Whether the debug billboard label is hidden when running outside the editor.
@export var editor_only_label: bool = true:
	set(value):
		editor_only_label = value
		_update_label_visibility()

## Cached shared material instance referencing [const PROP_SHADER].
var _material: ShaderMaterial
## Reference to the active CSG primitive child node.
var _active_shape: CSGPrimitive3D

## Billboard label displaying current tactical tag above the prop.
@onready var _label: Label3D = $Label3D as Label3D


## Initializes shared shader material, registers group and metadata, and configures label.
func _ready() -> void:
	add_to_group(GROUP_TAGGED_PROP)
	_ensure_material()
	_sync_active_shape()
	_update_tag()
	_update_color()
	_update_bounds()
	_update_label_visibility()


## Ensures shared [ShaderMaterial] is instantiated and bound to [const PROP_SHADER].
func _ensure_material() -> void:
	if not is_instance_valid(_material):
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = PROP_SHADER
		_material = mat


## Locates or caches the active child [CSGPrimitive3D] node.
func _sync_active_shape() -> void:
	if not is_instance_valid(_active_shape):
		_active_shape = get_node_or_null("Shape") as CSGPrimitive3D
	if not is_instance_valid(_active_shape):
		_active_shape = NodeQuery.find_first_child_of_type(self, CSGPrimitive3D) as CSGPrimitive3D
	if is_instance_valid(_active_shape):
		_configure_csg_shape(_active_shape)


## Updates tag metadata on root and active CSG node, and refreshes label text.
func _update_tag() -> void:
	if not is_inside_tree():
		return
	var clean_tag: String = prop_tag.strip_edges()
	var tag_name: StringName = StringName(clean_tag)
	set_meta(META_PROP_TAG, tag_name)
	if not is_instance_valid(_active_shape):
		_sync_active_shape()
	if is_instance_valid(_active_shape):
		_active_shape.set_meta(META_PROP_TAG, tag_name)
	if not is_instance_valid(_label):
		_label = get_node_or_null("Label3D") as Label3D
	if is_instance_valid(_label):
		_label.text = clean_tag


## Sets the per-instance color shader uniform on the active CSG primitive.
func _update_color() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_active_shape):
		_sync_active_shape()
	if is_instance_valid(_active_shape):
		_active_shape.set_instance_shader_parameter(PARAM_PROP_COLOR, prop_color)


## Swaps the active CSG child node to match the selected [enum PropShape].
func _update_shape() -> void:
	if not is_inside_tree():
		return
	_ensure_material()
	if not is_instance_valid(_active_shape):
		_sync_active_shape()

	var needs_new_shape: bool = false
	if not is_instance_valid(_active_shape):
		needs_new_shape = true
	elif prop_shape == PropShape.BOX and not (_active_shape is CSGBox3D):
		needs_new_shape = true
	elif prop_shape == PropShape.CYLINDER and not (_active_shape is CSGCylinder3D):
		needs_new_shape = true
	elif prop_shape == PropShape.SPHERE and not (_active_shape is CSGSphere3D):
		needs_new_shape = true

	if not needs_new_shape:
		_update_bounds()
		return

	for child: Node in get_children():
		if child is CSGPrimitive3D:
			remove_child(child)
			child.queue_free()
	_active_shape = null

	var new_shape: CSGPrimitive3D
	match prop_shape:
		PropShape.BOX:
			new_shape = CSGBox3D.new()
		PropShape.CYLINDER:
			new_shape = CSGCylinder3D.new()
		PropShape.SPHERE:
			new_shape = CSGSphere3D.new()

	new_shape.name = "Shape"
	add_child(new_shape)
	var scene_root: Node = get_tree().edited_scene_root
	if Engine.is_editor_hint() and is_instance_valid(scene_root):
		new_shape.owner = scene_root
	_active_shape = new_shape
	_configure_csg_shape(_active_shape)
	_update_bounds()


## Configures geometry dimensions on active shape and recalculates label position.
func _update_bounds() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_active_shape):
		_sync_active_shape()
	if not is_instance_valid(_active_shape):
		return

	if _active_shape is CSGBox3D:
		var box: CSGBox3D = _active_shape as CSGBox3D
		box.size = size
	elif _active_shape is CSGCylinder3D:
		var cyl: CSGCylinder3D = _active_shape as CSGCylinder3D
		cyl.radius = maxf(size.x, size.z) * 0.5
		cyl.height = size.y
	elif _active_shape is CSGSphere3D:
		var sph: CSGSphere3D = _active_shape as CSGSphere3D
		sph.radius = maxf(size.x, maxf(size.y, size.z)) * 0.5

	_update_label_position()


## Configures physics layers, material, and instance color on [param shape].
func _configure_csg_shape(shape: CSGPrimitive3D) -> void:
	shape.use_collision = true
	shape.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	shape.collision_mask = CollisionLayers.MASK_NONE
	_ensure_material()
	if shape is CSGBox3D:
		(shape as CSGBox3D).material = _material
	elif shape is CSGCylinder3D:
		(shape as CSGCylinder3D).material = _material
	elif shape is CSGSphere3D:
		(shape as CSGSphere3D).material = _material
	shape.set_instance_shader_parameter(PARAM_PROP_COLOR, prop_color)
	shape.set_meta(META_PROP_TAG, StringName(prop_tag.strip_edges()))


## Synchronizes visibility of [Label3D] according to flags and runtime context.
func _update_label_visibility() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_label):
		_label = get_node_or_null("Label3D") as Label3D
	if not is_instance_valid(_label):
		return
	if editor_only_label and not Engine.is_editor_hint():
		_label.visible = false
		return
	_label.visible = show_label


## Adjusts vertical position and counter-scales [Label3D] to prevent distortion.
func _update_label_position() -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_label):
		_label = get_node_or_null("Label3D") as Label3D
	if not is_instance_valid(_label):
		return

	var current_scale: Vector3 = scale
	if (
		absf(current_scale.x) > 0.001
		and absf(current_scale.y) > 0.001
		and absf(current_scale.z) > 0.001
	):
		_label.scale = Vector3(1.0 / current_scale.x, 1.0 / current_scale.y, 1.0 / current_scale.z)

	var half_height: float = size.y * 0.5
	_label.position = Vector3(0.0, half_height + 0.35, 0.0)
