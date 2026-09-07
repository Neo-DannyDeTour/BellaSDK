@tool
## Generates a procedural field of basalt columns.
##
## This tool script creates a field of basalt columns in the editor based on various
## parameters such as width, depth, and density. It also supports magnetic nodes
## that push columns upwards when nearby.
class_name BasaltGenerator
extends Node3D

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
var _debounce_delay_ms: int = 1000  # 1 second


## Process loop that handles debounced generation in the editor.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _needs_generation:
		if Time.get_ticks_msec() - _last_edit_time > _debounce_delay_ms:
			_needs_generation = false
			_generate()


## Queues a generation pass, resetting the debounce timer.
func _queue_generation() -> void:
	if Engine.is_editor_hint() and is_inside_tree() and is_node_ready():
		_needs_generation = true
		_last_edit_time = Time.get_ticks_msec()


## Generates the field of basalt columns, clearing any previous ones.
func _generate() -> void:
	if not is_inside_tree():
		return

	# 1. Clear previous generation
	for child: Node in get_children():
		if child.is_in_group(generated_group_name) or child.name.begins_with("BasaltColumn_"):
			child.queue_free()

	# Wait a frame for cleanup (important in tool scripts)
	await get_tree().process_frame

	if not is_inside_tree():
		return

	# Find magnets by checking for properties
	var magnets: Array[Node] = []
	for child: Node in get_children():
		if "push_force" in child and "effect_radius" in child:
			magnets.append(child)

	var placed_positions: Array[Vector2] = []

	# 2. Generate new columns
	for i: int in range(amount):
		var valid_position: bool = false
		var col_position: Vector3 = Vector3.ZERO
		var attempts: int = 0
		var max_attempts: int = 50

		while not valid_position and attempts < max_attempts:
			attempts += 1
			var x_pos: float = randf_range(-field_width / 2.0, field_width / 2.0)
			var z_pos: float = randf_range(-field_depth / 2.0, field_depth / 2.0)

			x_pos += randf_range(-chaos, chaos)
			z_pos += randf_range(-chaos, chaos)

			var max_x: float = max(0.0, (field_width / 2.0) - column_radius)
			var max_z: float = max(0.0, (field_depth / 2.0) - column_radius)

			x_pos = clampf(x_pos, -max_x, max_x)
			z_pos = clampf(z_pos, -max_z, max_z)

			var test_pos: Vector2 = Vector2(x_pos, z_pos)
			var is_far_enough: bool = true

			for placed: Vector2 in placed_positions:
				if test_pos.distance_squared_to(placed) < (min_spacing * min_spacing):
					is_far_enough = false
					break

			if is_far_enough:
				valid_position = true
				col_position = Vector3(test_pos.x, 0.0, test_pos.y)
				placed_positions.append(test_pos)

		if not valid_position:
			continue

		var column: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()

		mesh.radial_segments = max(4, sides)
		mesh.rings = int(rings)
		mesh.bottom_radius = column_radius
		mesh.top_radius = column_radius

		var final_height: float = base_height
		var col_global_pos: Vector3 = to_global(col_position)

		# Apply Magnets
		for magnet: Node in magnets:
			if not is_instance_valid(magnet):
				continue
			var dist_sq: float = Vector2(col_global_pos.x, col_global_pos.z).distance_squared_to(
				Vector2(magnet.global_position.x, magnet.global_position.z)
			)
			var effect_rad_sq: float = magnet.effect_radius * magnet.effect_radius
			if dist_sq < effect_rad_sq:
				var dist: float = sqrt(dist_sq)
				var influence: float = 1.0 - (dist / magnet.effect_radius)
				influence = smoothstep(0.0, 1.0, influence)
				final_height += magnet.push_force * influence

		mesh.height = max(0.1, final_height)
		column.mesh = mesh
		column.position = Vector3(col_position.x, mesh.height / 2.0, col_position.z)

		column.rotation.y = randf_range(-chaos, chaos)
		column.rotation.x = randf_range(-chaos * 0.2, chaos * 0.2)
		column.rotation.z = randf_range(-chaos * 0.2, chaos * 0.2)

		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		column.set_surface_override_material(0, material)

		column.add_to_group(generated_group_name, true)
		column.name = "BasaltColumn_" + str(i)
		add_child(column)

		var static_body: StaticBody3D = StaticBody3D.new()
		var collision_shape: CollisionShape3D = CollisionShape3D.new()

		if surface_group != "":
			static_body.add_to_group(surface_group, true)

		collision_shape.shape = mesh.create_convex_shape()
		static_body.add_child(collision_shape)
		column.add_child(static_body)

		if Engine.is_editor_hint():
			var root: Node = get_tree().edited_scene_root
			if is_instance_valid(root):
				column.owner = root
				static_body.owner = root
				collision_shape.owner = root
