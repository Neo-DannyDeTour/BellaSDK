## Updraft trigger volume that applies lift and drives wind visual effects.
@tool
class_name UpdraftVolume
extends Area3D

## Upward velocity applied to entities entering the updraft volume.
@export var lift_strength: float = 12.0

@export_group("Wind Column")
## Vertical UV scroll speed for the wind cylinder (supports negative values).
@export_range(-10.0, 10.0, 0.1) var column_scroll_speed: float = 3.0:
	set(value):
		column_scroll_speed = value
		_update_column_material()

## Overall visibility multiplier for the semi-transparent wind column.
@export_range(0.0, 1.0, 0.01) var column_opacity: float = 0.08:
	set(value):
		column_opacity = value
		_update_column_material()

## Albedo tint applied to the wind column mesh.
@export var column_color: Color = Color(0.6, 0.85, 1.0, 1.0):
	set(value):
		column_color = value
		_update_column_material()

@export_group("Paper Ribbons")
## Flutter speed of the paper ribbons reacting to the updraft air current.
@export_range(0.0, 50.0, 0.5) var paper_wind_speed: float = 15.0:
	set(value):
		paper_wind_speed = value
		_update_ribbon_materials()

## Maximum displacement distance for fluttering paper ribbon strips.
@export_range(0.0, 0.5, 0.01) var paper_amplitude: float = 0.08:
	set(value):
		paper_amplitude = value
		_update_ribbon_materials()

## Color tint applied to all paper ribbon meshes.
@export var paper_color: Color = Color(0.95, 0.85, 0.2, 1.0):
	set(value):
		paper_color = value
		_update_ribbon_materials()


## Initializes nodes, hides debug visual, and applies inspector settings.
func _ready() -> void:
	print("UpdraftVolume: Initialized on: ", name)
	var debug_mesh: Node3D = (
		get_node_or_null("MeshInstance3D") if get_node_or_null("MeshInstance3D") is Node3D else null
	)
	if is_instance_valid(debug_mesh) and not Engine.is_editor_hint():
		debug_mesh.hide()

	_update_column_material()
	_update_ribbon_materials()


## Handles entity entry, computes lift boundary, and triggers updraft.
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if body.has_method("enter_updraft"):
		print("UpdraftVolume: Entity entered updraft: ", body.name)
		var top_height: float = _calculate_top_height()
		body.call("enter_updraft", lift_strength, top_height)


## Handles entity exit and notifies the entity via [method exit_updraft].
func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	if body.has_method("exit_updraft"):
		print("UpdraftVolume: Entity exited updraft: ", body.name)
		body.call("exit_updraft")


## Computes the world top Y coordinate based on child [CollisionShape3D].
func _calculate_top_height() -> float:
	var top_height: float = global_position.y
	for child: Node in get_children():
		if child is CollisionShape3D:
			var col_shape: CollisionShape3D = child as CollisionShape3D
			if not is_instance_valid(col_shape.shape):
				continue

			if col_shape.shape is BoxShape3D:
				var box: BoxShape3D = col_shape.shape as BoxShape3D
				top_height = col_shape.global_position.y + (box.size.y * 0.5)
				break
			elif col_shape.shape is CylinderShape3D:
				var cyl: CylinderShape3D = col_shape.shape as CylinderShape3D
				top_height = col_shape.global_position.y + (cyl.height * 0.5)
				break
	return top_height


## Applies exported column properties to the wind column [ShaderMaterial].
func _update_column_material() -> void:
	if not is_inside_tree():
		return
	var col_node: MeshInstance3D = get_node_or_null("WindColumnMesh") as MeshInstance3D
	if not is_instance_valid(col_node):
		return

	var mat: ShaderMaterial = col_node.get_active_material(0) as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("scroll_speed", column_scroll_speed)
		mat.set_shader_parameter("column_opacity", column_opacity)
		mat.set_shader_parameter("wind_color", column_color)


## Applies exported ribbon properties to all ribbon [ShaderMaterial] nodes.
func _update_ribbon_materials() -> void:
	if not is_inside_tree():
		return
	var ribbons_root: Node3D = get_node_or_null("PaperRibbons") as Node3D
	if not is_instance_valid(ribbons_root):
		return

	for child: Node in ribbons_root.get_children():
		if child is MeshInstance3D:
			var mesh_inst: MeshInstance3D = child as MeshInstance3D
			var mat: ShaderMaterial = mesh_inst.get_active_material(0) as ShaderMaterial
			if is_instance_valid(mat):
				mat.set_shader_parameter("wind_speed", paper_wind_speed)
				mat.set_shader_parameter("flutter_amplitude", paper_amplitude)
				mat.set_shader_parameter("ribbon_color", paper_color)
