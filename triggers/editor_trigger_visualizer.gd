@tool
## Visualizes 3D trigger zones with wireframes, orientation arrows, and editor metrics.
## Provides production-grade gizmo visualization for level designers in the editor.
class_name EditorTriggerVisualizer
extends MeshInstance3D

enum ShapeType { BOX, SPHERE }

@export_category("Geometry & Shape")

## Primitive geometry used to represent the trigger boundary.
@export var shape_type: ShapeType = ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_rebuild_all()

## 3D dimensions of the trigger volume.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_rebuild_all()

@export_category("Visual Appearance")

## Base tint and opacity applied to the volumetric inner fill.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree():
			_update_materials()

## Edge color for the outline wireframe.
@export var outline_color: Color = Color(1.0, 0.8, 0.3, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_materials()

## Allows the visualizer to remain visible through walls and solid geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_materials()

@export_category("Level Design Gizmos")

## Displays a forward-facing arrow along the local -Z axis indicating orientation.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_arrow()

## Appends bounding box dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_text()

## Primary debug text displayed above the trigger volume.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		if is_inside_tree():
			_update_text()

## Allows visualization to persist during runtime debug playtests.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_visibility()

## Global static toggle overriding visibility for all visualizer instances.
static var debug_force_visible: bool = false

## Internal reference to child wireframe outline mesh node.
var _wireframe_node: MeshInstance3D

## Internal reference to child orientation arrow mesh node.
var _arrow_node: MeshInstance3D

## Internal reference to billboarded 3D text label.
var _label: Label3D


## Lifecycle initialization building meshes, materials, and runtime signal links.
func _ready() -> void:
	print("EditorTriggerVisualizer: Initializing visualizer at ", name)
	_ensure_child_nodes()
	_rebuild_all()
	add_to_group(&"trigger_visualizers")
	_update_visibility()

	if not Engine.is_editor_hint() and is_instance_valid(Events):
		if Events.has_signal(&"trigger_visibility_toggled"):
			if not Events.trigger_visibility_toggled.is_connected(set_debug_visibility):
				Events.trigger_visibility_toggled.connect(set_debug_visibility)


## Refreshes geometry, materials, gizmo arrows, and labels simultaneously.
func _rebuild_all() -> void:
	_update_fill_mesh()
	_update_wireframe_mesh()
	_update_materials()
	_update_arrow()
	_update_text()


## Instantiates child nodes if missing to prevent null reference errors.
func _ensure_child_nodes() -> void:
	if not is_instance_valid(_wireframe_node):
		_wireframe_node = get_node_or_null("Wireframe") as MeshInstance3D
		if not is_instance_valid(_wireframe_node):
			_wireframe_node = MeshInstance3D.new()
			_wireframe_node.name = "Wireframe"
			add_child(_wireframe_node)

	if not is_instance_valid(_arrow_node):
		_arrow_node = get_node_or_null("DirectionArrow") as MeshInstance3D
		if not is_instance_valid(_arrow_node):
			_arrow_node = MeshInstance3D.new()
			_arrow_node.name = "DirectionArrow"
			add_child(_arrow_node)

	if not is_instance_valid(_label):
		_label = get_node_or_null("VisualizerLabel") as Label3D
		if not is_instance_valid(_label):
			_label = Label3D.new()
			_label.name = "VisualizerLabel"
			_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_label.no_depth_test = true
			add_child(_label)


## Generates or resizes the inner volumetric fill mesh.
func _update_fill_mesh() -> void:
	if shape_type == ShapeType.BOX:
		if mesh == null or not mesh is BoxMesh:
			mesh = BoxMesh.new()
		else:
			mesh = mesh.duplicate()
		(mesh as BoxMesh).size = trigger_size
	elif shape_type == ShapeType.SPHERE:
		if mesh == null or not mesh is SphereMesh:
			mesh = SphereMesh.new()
		else:
			mesh = mesh.duplicate()
		(mesh as SphereMesh).radius = trigger_size.x / 2.0
		(mesh as SphereMesh).height = trigger_size.x


## Constructs an ImmediateMesh wireframe cage outlining the active shape.
func _update_wireframe_mesh() -> void:
	if not is_instance_valid(_wireframe_node):
		return

	var imm_mesh: ImmediateMesh = ImmediateMesh.new()

	if shape_type == ShapeType.BOX:
		var half: Vector3 = trigger_size * 0.5
		imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		# Bottom square
		_draw_line(imm_mesh, Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z))
		_draw_line(imm_mesh, Vector3(half.x, -half.y, -half.z), Vector3(half.x, -half.y, half.z))
		_draw_line(imm_mesh, Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z))
		_draw_line(imm_mesh, Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z))
		# Top square
		_draw_line(imm_mesh, Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z))
		_draw_line(imm_mesh, Vector3(half.x, half.y, -half.z), Vector3(half.x, half.y, half.z))
		_draw_line(imm_mesh, Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z))
		_draw_line(imm_mesh, Vector3(-half.x, half.y, half.z), Vector3(-half.x, half.y, -half.z))
		# Vertical pillars
		_draw_line(imm_mesh, Vector3(-half.x, -half.y, -half.z), Vector3(-half.x, half.y, -half.z))
		_draw_line(imm_mesh, Vector3(half.x, -half.y, -half.z), Vector3(half.x, half.y, -half.z))
		_draw_line(imm_mesh, Vector3(half.x, -half.y, half.z), Vector3(half.x, half.y, half.z))
		_draw_line(imm_mesh, Vector3(-half.x, -half.y, half.z), Vector3(-half.x, half.y, half.z))
		imm_mesh.surface_end()
	elif shape_type == ShapeType.SPHERE:
		var radius: float = trigger_size.x * 0.5
		var segments: int = 24
		imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for axis: int in range(3):
			for i: int in range(segments):
				var a1: float = (float(i) / segments) * TAU
				var a2: float = (float(i + 1) / segments) * TAU
				var p1: Vector3 = Vector3.ZERO
				var p2: Vector3 = Vector3.ZERO
				match axis:
					0:  # X-Y ring
						p1 = Vector3(cos(a1), sin(a1), 0.0) * radius
						p2 = Vector3(cos(a2), sin(a2), 0.0) * radius
					1:  # X-Z ring
						p1 = Vector3(cos(a1), 0.0, sin(a1)) * radius
						p2 = Vector3(cos(a2), 0.0, sin(a2)) * radius
					2:  # Y-Z ring
						p1 = Vector3(0.0, cos(a1), sin(a1)) * radius
						p2 = Vector3(0.0, cos(a2), sin(a2)) * radius
				_draw_line(imm_mesh, p1, p2)
		imm_mesh.surface_end()

	_wireframe_node.mesh = imm_mesh


## Helper method emitting line vertex segments to an [ImmediateMesh].
func _draw_line(target_mesh: ImmediateMesh, from: Vector3, to: Vector3) -> void:
	target_mesh.surface_add_vertex(from)
	target_mesh.surface_add_vertex(to)


## Updates fill and wireframe shaders with depth testing, tint, and opacity.
func _update_materials() -> void:
	if mesh != null:
		var fill_mat: StandardMaterial3D = (
			mesh.surface_get_material(0)
			if mesh.surface_get_material(0) is StandardMaterial3D
			else null
		)
		if fill_mat == null:
			fill_mat = StandardMaterial3D.new()
			fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			fill_mat = fill_mat.duplicate() as StandardMaterial3D

		fill_mat.albedo_color = trigger_color
		fill_mat.no_depth_test = x_ray_mode
		mesh.surface_set_material(0, fill_mat)

	if is_instance_valid(_wireframe_node) and _wireframe_node.mesh != null:
		var wire_mat: StandardMaterial3D = StandardMaterial3D.new()
		wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wire_mat.albedo_color = outline_color
		wire_mat.no_depth_test = x_ray_mode
		_wireframe_node.set_surface_override_material(0, wire_mat)


## Draws a local -Z directional arrow indicating trigger entry or facing angle.
func _update_arrow() -> void:
	if not is_instance_valid(_arrow_node):
		return

	_arrow_node.visible = show_orientation
	if not show_orientation:
		return

	var arrow_mesh: ImmediateMesh = ImmediateMesh.new()
	var forward_len: float = (trigger_size.z * 0.5) + 0.8
	var head_len: float = 0.35
	var head_width: float = 0.2

	arrow_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	# Shaft pointing towards -Z
	_draw_line(arrow_mesh, Vector3.ZERO, Vector3(0.0, 0.0, -forward_len))
	# Arrow Head
	var tip: Vector3 = Vector3(0.0, 0.0, -forward_len)
	_draw_line(arrow_mesh, tip, Vector3(-head_width, 0.0, -forward_len + head_len))
	_draw_line(arrow_mesh, tip, Vector3(head_width, 0.0, -forward_len + head_len))
	_draw_line(arrow_mesh, tip, Vector3(0.0, head_width, -forward_len + head_len))
	_draw_line(arrow_mesh, tip, Vector3(0.0, -head_width, -forward_len + head_len))
	arrow_mesh.surface_end()

	_arrow_node.mesh = arrow_mesh

	var arrow_mat: StandardMaterial3D = StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = outline_color
	arrow_mat.no_depth_test = x_ray_mode
	_arrow_node.set_surface_override_material(0, arrow_mat)


## Formats and positions the 3D billboard text label with metric dimensions.
func _update_text() -> void:
	if not is_instance_valid(_label):
		return

	var text_output: String = trigger_text
	if show_metric_dimensions:
		if shape_type == ShapeType.BOX:
			text_output += (
				"\n[%.1fm × %.1fm × %.1fm]" % [trigger_size.x, trigger_size.y, trigger_size.z]
			)
		elif shape_type == ShapeType.SPHERE:
			text_output += "\n[R: %.1fm]" % [trigger_size.x * 0.5]

	_label.text = text_output
	_label.position = Vector3(0.0, (trigger_size.y * 0.5) + 0.5, 0.0)


## Evaluates current engine context and sets visibility flags.
func _update_visibility() -> void:
	visible = (Engine.is_editor_hint() or show_in_game or debug_force_visible)


## Updates visibility state dynamically from debug signal triggers.
## [param is_active] Whether debug visibility is enabled.
func set_debug_visibility(is_active: bool) -> void:
	print("EditorTriggerVisualizer: Debug visibility toggle -> ", is_active)
	visible = (Engine.is_editor_hint() or show_in_game or is_active)


## Sets static debug visibility state across all visualizer nodes in the scene.
## [param is_active] Global visibility flag.
static func set_global_debug_visibility(is_active: bool) -> void:
	print("EditorTriggerVisualizer: Global debug visibility -> ", is_active)
	debug_force_visible = is_active
