@tool
## Generates a procedural field of basalt columns in the editor with magnet support.
##
## Offloads visual rendering to a single [MultiMeshInstance3D] and static collisions
## to a single [StaticBody3D] with an aggregated [ConcavePolygonShape3D].
class_name BasaltGenerator
extends Node3D

## Name assigned to the generated [MultiMeshInstance3D] child node.
const MULTI_MESH_NAME: StringName = &"BasaltMultiMesh"

## Name assigned to the generated [StaticBody3D] child node.
const STATIC_BODY_NAME: StringName = &"BasaltStaticBody"

## Name assigned to the generated [CollisionShape3D] child node.
const COLLISION_SHAPE_NAME: StringName = &"BasaltCollisionShape"

## Toggles the manual generation of basalt columns.
@export_group("Generation Trigger")
@export var generate_basalt: bool = false:
	set(value):
		if value and is_inside_tree() and is_node_ready():
			_generate()
		generate_basalt = false

## The overall width of the generation field.
@export_group("Field Properties")
@export var field_width: float = 20.0:
	set(value):
		field_width = value
		_queue_generation()

## The overall depth of the generation field.
@export var field_depth: float = 20.0:
	set(value):
		field_depth = value
		_queue_generation()

## The total number of basalt columns to attempt to generate.
@export var amount: int = 100:
	set(value):
		amount = value
		_queue_generation()

@export_group("Basalt Properties")

## Material applied to all basalt columns rendered through the MultiMesh.
@export var material: Material = null:
	set(value):
		material = value
		_update_active_material()

## The number of sides for each generated basalt column.
@export var sides: int = 6:
	set(value):
		sides = value
		_queue_generation()

## The physics surface group to assign to the generated columns for interactions like footsteps.
@export var surface_group: String = "stone":
	set(value):
		surface_group = value
		_queue_generation()

## The number of rings for each basalt column's cylinder mesh.
@export var rings: int = 0:
	set(value):
		rings = value
		_queue_generation()

## The base radius of each generated basalt column.
@export var column_radius: float = 1.0:
	set(value):
		column_radius = value
		_queue_generation()

## The base height of each generated basalt column.
@export var base_height: float = 2.0:
	set(value):
		base_height = value
		_queue_generation()

## Positional and rotational randomness applied to each column.
@export var chaos: float = 0.5:
	set(value):
		chaos = value
		_queue_generation()

## The minimum spatial distance enforced between any two generated columns.
@export var min_spacing: float = 1.8:
	set(value):
		min_spacing = value
		_queue_generation()

## The group name assigned to generated columns for easy cleanup.
var generated_group_name: String = "generated_basalt"

## Tracks whether a new generation pass has been requested.
var _needs_generation: bool = false

## The timestamp of the last parameter edit.
var _last_edit_time: int = 0

## The delay in milliseconds before generating after an edit to debounce inputs.
var _debounce_delay_ms: int = 1000


## Debounces and triggers procedural column generation during editor frames.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _needs_generation:
		if Time.get_ticks_msec() - _last_edit_time > _debounce_delay_ms:
			_needs_generation = false
			_generate()


## Queues generation and marks timestamp when exported parameters update.
func _queue_generation() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and is_node_ready():
		_needs_generation = true
		_last_edit_time = Time.get_ticks_msec()


## Applies updated material directly to active [MultiMeshInstance3D] if present.
func _update_active_material() -> void:
	var multi_node: Node = get_node_or_null(NodePath(MULTI_MESH_NAME))
	if multi_node is MultiMeshInstance3D:
		var multi_inst: MultiMeshInstance3D = multi_node as MultiMeshInstance3D
		multi_inst.material_override = _resolve_material()


## Resolves active material, creating a vertex-shaded fallback if unspecified.
func _resolve_material() -> Material:
	if is_instance_valid(material):
		return material
	var default_mat: StandardMaterial3D = StandardMaterial3D.new()
	default_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return default_mat


## Clears legacy and active generated nodes from scene hierarchy.
func _clear_previous_generation() -> void:
	for child: Node in get_children():
		if not is_instance_valid(child):
			continue
		var child_name: String = child.name
		if (
			child.is_in_group(StringName(generated_group_name))
			or child_name == MULTI_MESH_NAME
			or child_name == STATIC_BODY_NAME
			or child_name.begins_with("BasaltColumn_")
			or child_name.begins_with("@MeshInstance3D")
			or child_name.begins_with("@StaticBody3D")
		):
			child.queue_free()


## Safely extracts a float from an untyped Variant without triggering unsafe cast warnings.
static func _to_safe_float(val: Variant) -> float:
	if typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT:
		return str(val).to_float()
	return 0.0


## Clears existing geometry and generates unified MultiMesh and static trimesh.
func _generate() -> void:
	if not is_inside_tree():
		return

	_clear_previous_generation()

	# Wait a frame for queue_free cleanup to complete cleanly
	await get_tree().process_frame

	if not is_inside_tree():
		return

	var prop_push: StringName = &"push_force"
	var prop_rad: StringName = &"effect_radius"

	var magnets: Array[Node3D] = []
	for child: Node in get_children():
		if child is Node3D and prop_push in child and prop_rad in child:
			magnets.append(child as Node3D)

	var placed_positions: Array[Vector2] = []
	var column_transforms: Array[Transform3D] = []
	var max_attempts: int = 50

	var base_mesh: CylinderMesh = CylinderMesh.new()
	base_mesh.radial_segments = maxi(4, sides)
	base_mesh.rings = rings
	base_mesh.bottom_radius = column_radius
	base_mesh.top_radius = column_radius
	base_mesh.height = 1.0

	var half_width: float = field_width * 0.5
	var half_depth: float = field_depth * 0.5
	var max_x: float = maxf(0.0, half_width - column_radius)
	var max_z: float = maxf(0.0, half_depth - column_radius)
	var min_spacing_sq: float = min_spacing * min_spacing

	for i: int in range(amount):
		var valid_position: bool = false
		var col_position: Vector3 = Vector3.ZERO
		var attempts: int = 0

		while not valid_position and attempts < max_attempts:
			attempts += 1
			var x_pos: float = randf_range(-half_width, half_width)
			var z_pos: float = randf_range(-half_depth, half_depth)

			x_pos += randf_range(-chaos, chaos)
			z_pos += randf_range(-chaos, chaos)

			x_pos = clampf(x_pos, -max_x, max_x)
			z_pos = clampf(z_pos, -max_z, max_z)

			var test_pos: Vector2 = Vector2(x_pos, z_pos)
			var is_far_enough: bool = true

			for placed: Vector2 in placed_positions:
				if test_pos.distance_squared_to(placed) < min_spacing_sq:
					is_far_enough = false
					break

			if is_far_enough:
				valid_position = true
				col_position = Vector3(test_pos.x, 0.0, test_pos.y)
				placed_positions.append(test_pos)

		if not valid_position:
			continue

		var final_height: float = base_height
		var col_global_pos: Vector3 = to_global(col_position)
		var col_flat: Vector2 = Vector2(col_global_pos.x, col_global_pos.z)

		for magnet: Node3D in magnets:
			if not is_instance_valid(magnet):
				continue

			var magnet_radius: float = _to_safe_float(magnet.get(prop_rad))
			var magnet_push: float = _to_safe_float(magnet.get(prop_push))
			var magnet_pos: Vector3 = magnet.global_position
			var mag_flat: Vector2 = Vector2(magnet_pos.x, magnet_pos.z)

			var dist_sq: float = col_flat.distance_squared_to(mag_flat)
			var effect_rad_sq: float = magnet_radius * magnet_radius

			if dist_sq < effect_rad_sq and magnet_radius > 0.0:
				var dist: float = sqrt(dist_sq)
				var influence: float = 1.0 - (dist / magnet_radius)
				influence = smoothstep(0.0, 1.0, influence)
				final_height += magnet_push * influence

		var clamped_height: float = maxf(0.1, final_height)
		var rot_euler: Vector3 = Vector3(
			randf_range(-chaos * 0.2, chaos * 0.2),
			randf_range(-chaos, chaos),
			randf_range(-chaos * 0.2, chaos * 0.2)
		)
		var rot_basis: Basis = Basis.from_euler(rot_euler)
		var scale_vec: Vector3 = Vector3(1.0, clamped_height, 1.0)
		var col_basis: Basis = rot_basis.scaled(scale_vec)
		var col_origin: Vector3 = Vector3(col_position.x, clamped_height * 0.5, col_position.z)

		column_transforms.append(Transform3D(col_basis, col_origin))

	if column_transforms.is_empty():
		return

	# Build single MultiMeshInstance3D for 1-draw-call visual rendering
	var multi_inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multi_inst.name = MULTI_MESH_NAME
	multi_inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	multi_inst.add_to_group(StringName(generated_group_name), true)

	var multi_mesh: MultiMesh = MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.use_colors = false
	multi_mesh.use_custom_data = false
	multi_mesh.mesh = base_mesh
	multi_mesh.instance_count = column_transforms.size()

	for idx: int in range(column_transforms.size()):
		multi_mesh.set_instance_transform(idx, column_transforms[idx])

	multi_inst.multimesh = multi_mesh
	multi_inst.material_override = _resolve_material()
	add_child(multi_inst)

	# Build single StaticBody3D with concatenated ConcavePolygonShape3D trimesh
	var static_body: StaticBody3D = StaticBody3D.new()
	static_body.name = STATIC_BODY_NAME
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	static_body.add_to_group(StringName(generated_group_name), true)
	if surface_group != "":
		static_body.add_to_group(StringName(surface_group), true)

	var unit_faces: PackedVector3Array = base_mesh.get_faces()
	var total_faces: PackedVector3Array = PackedVector3Array()
	total_faces.resize(column_transforms.size() * unit_faces.size())

	var write_idx: int = 0
	for t: Transform3D in column_transforms:
		for v: Vector3 in unit_faces:
			total_faces[write_idx] = t * v
			write_idx += 1

	var concave_shape: ConcavePolygonShape3D = ConcavePolygonShape3D.new()
	concave_shape.set_faces(total_faces)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = COLLISION_SHAPE_NAME
	collision_shape.shape = concave_shape
	static_body.add_child(collision_shape)
	add_child(static_body)

	# Assign owners in editor mode so nodes serialize into the scene file
	if Engine.is_editor_hint():
		var scene_root: Node = get_tree().edited_scene_root
		if is_instance_valid(scene_root):
			multi_inst.owner = scene_root
			static_body.owner = scene_root
			collision_shape.owner = scene_root
