@tool
class_name AnimatedCubeWall
extends Node3D

enum AnimationMode {RANDOM, WAVE, FROM_CENTER, TOWARDS_CENTER, CHECKERBOARD, ROW_WAVE, COLUMN_WAVE}

@export var grid_width: int = 10:
	set(value):
		grid_width = value
		_request_update()

@export var grid_height: int = 10:
	set(value):
		grid_height = value
		_request_update()

@export var cube_spacing: float = 1.1:
	set(value):
		cube_spacing = value
		_request_update()

@export var animation_mode: AnimationMode = AnimationMode.WAVE:
	set(value):
		animation_mode = value
		print("AnimatedCubeWall: animation_mode changed to ", value)

@export var movement_speed: float = 2.0:
	set(value):
		movement_speed = value
		print("AnimatedCubeWall: movement_speed changed to ", value)

@export var movement_amplitude: float = 1.0:
	set(value):
		movement_amplitude = value
		print("AnimatedCubeWall: movement_amplitude changed to ", value)

@export var emissive_color: Color = Color(0.0, 0.8, 1.0, 1.0):
	set(value):
		emissive_color = value
		print("AnimatedCubeWall: emissive_color changed to ", value)

@export var custom_mesh: Mesh = null:
	set(value):
		custom_mesh = value
		_request_update()

var _multi_mesh_instance: MultiMeshInstance3D = null
var _time_passed: float = 0.0
var _random_offsets: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_setup_child_node()
	_generate_wall()


func _setup_child_node() -> void:
	print("AnimatedCubeWall: Setting up MultiMeshInstance3D child.")
	for child: Node in get_children():
		if child is MultiMeshInstance3D:
			_multi_mesh_instance = child as MultiMeshInstance3D
			break

	if _multi_mesh_instance == null:
		_multi_mesh_instance = MultiMeshInstance3D.new()
		_multi_mesh_instance.name = "MultiMeshInstance3D"
		add_child(_multi_mesh_instance)
		if Engine.is_editor_hint():
			_multi_mesh_instance.owner = get_tree().edited_scene_root


func _request_update() -> void:
	if is_node_ready():
		_generate_wall()


func _process(delta: float) -> void:
	if _multi_mesh_instance == null or _multi_mesh_instance.multimesh == null:
		return

	if _multi_mesh_instance.multimesh.instance_count == 0:
		return

	_time_passed += delta * movement_speed

	var instance_id: int = 0
	for x: int in range(grid_width):
		for y: int in range(grid_height):
			var raw_sine: float = _calculate_raw_sine(instance_id, x, y)
			_update_cube_transform_and_color(instance_id, x, y, raw_sine)
			instance_id += 1


func _generate_wall() -> void:
	var total_cubes: int = grid_width * grid_height
	print("AnimatedCubeWall: _generate_wall() called. Spawning ", total_cubes)

	if _multi_mesh_instance == null:
		return

	var mm: MultiMesh = _multi_mesh_instance.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		_multi_mesh_instance.multimesh = mm

	if not mm.use_colors:
		mm.use_colors = true

	if custom_mesh != null:
		mm.mesh = custom_mesh
	else:
		if mm.mesh == null or not mm.mesh is BoxMesh:
			var box: BoxMesh = BoxMesh.new()
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_operator = StandardMaterial3D.EMISSION_OP_MULTIPLY
			box.material = mat
			mm.mesh = box

	mm.instance_count = 0
	mm.instance_count = total_cubes

	_random_offsets.resize(total_cubes)

	var instance_id: int = 0
	for x: int in range(grid_width):
		for y: int in range(grid_height):
			_random_offsets[instance_id] = randf() * PI * 2.0
			_update_cube_transform_and_color(instance_id, x, y, 0.0)
			instance_id += 1


func _calculate_raw_sine(instance_id: int, x: int, y: int) -> float:
	var sine_val: float = 0.0
	var center_x: float = float(grid_width) / 2.0
	var center_y: float = float(grid_height) / 2.0
	var current_x: float = float(x)
	var current_y: float = float(y)

	match animation_mode:
		AnimationMode.RANDOM:
			sine_val = sin(_time_passed + _random_offsets[instance_id])
		AnimationMode.WAVE:
			sine_val = sin(_time_passed + (current_x * 0.5) + (current_y * 0.5))
		AnimationMode.FROM_CENTER:
			var dist: float = Vector2(current_x - center_x, current_y - center_y).length()
			sine_val = sin(_time_passed - dist * 0.5)
		AnimationMode.TOWARDS_CENTER:
			var dist: float = Vector2(current_x - center_x, current_y - center_y).length()
			sine_val = sin(_time_passed + dist * 0.5)
		AnimationMode.CHECKERBOARD:
			var check: float = float((x + y) % 2) * PI
			sine_val = sin(_time_passed + check)
		AnimationMode.ROW_WAVE:
			sine_val = sin(_time_passed + (current_y * 0.5))
		AnimationMode.COLUMN_WAVE:
			sine_val = sin(_time_passed + (current_x * 0.5))

	return sine_val


func _update_cube_transform_and_color(instance_id: int, x: int, y: int, raw_sine: float) -> void:
	var pos_x: float = (float(x) - float(grid_width) / 2.0 + 0.5) * cube_spacing
	var pos_y: float = (float(y) - float(grid_height) / 2.0 + 0.5) * cube_spacing
	var z_offset: float = raw_sine * movement_amplitude

	var tform: Transform3D = Transform3D()
	tform = tform.translated(Vector3(pos_x, pos_y, z_offset))
	_multi_mesh_instance.multimesh.set_instance_transform(instance_id, tform)

	var intensity: float = (raw_sine + 1.0) / 2.0
	var current_color: Color = emissive_color * intensity
	current_color.a = 1.0
	_multi_mesh_instance.multimesh.set_instance_color(instance_id, current_color)
