@tool
class_name EditorTriggerVisualizer
extends MeshInstance3D

enum ShapeType { BOX, SPHERE }

@export_category("Trigger Visuals")

## Property: Shape Type.
@export var shape_type: ShapeType = ShapeType.BOX:
	set(value):
		shape_type = value
		_update_mesh()

## Property: Show In Game.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		visible = Engine.is_editor_hint() or show_in_game

## Property: Trigger Size.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_mesh()

## Property: Trigger Color.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.4):
	set(value):
		trigger_color = value
		_update_material()

## Property: Trigger Text.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		_update_text()

## Property: Label.
var _label: Label3D


func _ready() -> void:
	_update_mesh()
	_update_material()
	_update_text()
	visible = Engine.is_editor_hint() or show_in_game


func _update_mesh() -> void:
	if shape_type == ShapeType.BOX:
		if mesh == null or not mesh is BoxMesh:
			mesh = BoxMesh.new()
		(mesh as BoxMesh).size = trigger_size
	elif shape_type == ShapeType.SPHERE:
		if mesh == null or not mesh is SphereMesh:
			mesh = SphereMesh.new()
		(mesh as SphereMesh).radius = trigger_size.x / 2.0
		(mesh as SphereMesh).height = trigger_size.x


func _update_material() -> void:
	if mesh == null:
		return

	var mat: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.surface_set_material(0, mat)

	mat.albedo_color = trigger_color


func _update_text() -> void:
	if _label == null:
		_label = get_node_or_null("VisualizerLabel") as Label3D
		if _label == null:
			_label = Label3D.new()
			_label.name = "VisualizerLabel"
			_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_label.no_depth_test = true
			add_child(_label)

	_label.text = trigger_text
