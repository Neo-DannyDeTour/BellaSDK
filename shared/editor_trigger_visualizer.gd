## Visualizes 3D trigger zones in the editor and in-game debug sessions.
@tool
class_name EditorTriggerVisualizer
extends MeshInstance3D

enum ShapeType { BOX, SPHERE }

@export_category("Trigger Visuals")

## Property: Shape Type.
@export var shape_type: ShapeType = ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_mesh()

## Property: Show In Game.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			visible = (Engine.is_editor_hint() or show_in_game or debug_force_visible)

## Property: Trigger Size.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_update_mesh()

## Property: Trigger Color.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.4):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_material()

## Property: Trigger Text.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_text()

## Reference to 3D label displaying trigger name text.
var _label: Label3D

## Static debug flag overriding runtime visibility for triggers.
static var debug_force_visible: bool = false


## Lifecycle initialization configuring visualizers and signal bindings.
func _ready() -> void:
	print("EditorTriggerVisualizer: _ready() called.")
	_update_mesh()
	_update_material()
	_update_text()
	add_to_group(&"trigger_visualizers")
	visible = (Engine.is_editor_hint() or show_in_game or debug_force_visible)

	if not Engine.is_editor_hint() and has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("trigger_visibility_toggled"):
			events.trigger_visibility_toggled.connect(set_debug_visibility)


## Builds mesh geometry according to selected shape and dimensions.
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


## Configures unshaded translucent material with assigned tint.
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


## Instantiates and updates the billboarded 3D text label node.
func _update_text() -> void:
	if not is_instance_valid(_label):
		_label = get_node_or_null("VisualizerLabel") as Label3D
		if not is_instance_valid(_label):
			_label = Label3D.new()
			_label.name = "VisualizerLabel"
			_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_label.no_depth_test = true
			add_child(_label)

	if is_instance_valid(_label):
		_label.text = trigger_text


## Updates node visibility state from global trigger toggle signal.
func set_debug_visibility(is_active: bool) -> void:
	print("EditorTriggerVisualizer: Debug visibility updated -> ", is_active)
	visible = (Engine.is_editor_hint() or show_in_game or is_active)


## Sets static debug visibility state across all visualizer nodes.
static func set_global_debug_visibility(is_active: bool) -> void:
	print("EditorTriggerVisualizer: Global debug visibility -> ", is_active)
	debug_force_visible = is_active
