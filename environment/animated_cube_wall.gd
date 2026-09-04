@tool
## Generates a grid of cubes animated via a custom spatial shader.
##
## [AnimatedCubeWall] creates a [MultiMeshInstance3D] to efficiently render thousands
## of glowing cubes. The cubes undulate in various sine-wave patterns defined by the
## [enum AnimationMode].
class_name AnimatedCubeWall
extends Node3D

## Defines the mathematical pattern used to animate the cubes in the vertex shader.
enum AnimationMode {RANDOM, WAVE, FROM_CENTER, TOWARDS_CENTER, CHECKERBOARD, ROW_WAVE, COLUMN_WAVE}

## The internal GLSL-like shader code injected into the [ShaderMaterial].
const SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform int animation_mode = 1;
uniform float movement_speed = 2.0;
uniform float movement_amplitude = 1.0;
uniform float grid_width = 10.0;
uniform float grid_height = 10.0;
uniform vec3 emissive_color = vec3(0.0, 0.8, 1.0);

void vertex() {
	float time = TIME * movement_speed;
	float sine_val = 0.0;
	float cx = grid_width / 2.0;
	float cy = grid_height / 2.0;

	// INSTANCE_CUSTOM contains: (random_offset, x_index, y_index, unused)
	float rand_offset = INSTANCE_CUSTOM.x;
	float curr_x = INSTANCE_CUSTOM.y;
	float curr_y = INSTANCE_CUSTOM.z;

	if (animation_mode == 0) { // RANDOM
		sine_val = sin(time + rand_offset);
	} else if (animation_mode == 1) { // WAVE
		sine_val = sin(time + (curr_x * 0.5) + (curr_y * 0.5));
	} else if (animation_mode == 2) { // FROM_CENTER
		float dist = length(vec2(curr_x - cx, curr_y - cy));
		sine_val = sin(time - dist * 0.5);
	} else if (animation_mode == 3) { // TOWARDS_CENTER
		float dist = length(vec2(curr_x - cx, curr_y - cy));
		sine_val = sin(time + dist * 0.5);
	} else if (animation_mode == 4) { // CHECKERBOARD
		float check = mod(curr_x + curr_y, 2.0) * PI;
		sine_val = sin(time + check);
	} else if (animation_mode == 5) { // ROW_WAVE
		sine_val = sin(time + (curr_y * 0.5));
	} else if (animation_mode == 6) { // COLUMN_WAVE
		sine_val = sin(time + (curr_x * 0.5));
	}

	VERTEX.z += sine_val * movement_amplitude;

	float intensity = (sine_val + 1.0) / 2.0;
	COLOR = vec4(emissive_color * intensity, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb;
}
"""

## Defines the number of cubes along the X-axis. Used to determine the overall width of the grid.
@export var grid_width: int = 10:
	set(value):
		grid_width = value
		_update_shader_uniforms()
		_request_update()

## Defines the number of cubes along the Y-axis. Used to determine the overall height of the grid.
@export var grid_height: int = 10:
	set(value):
		grid_height = value
		_update_shader_uniforms()
		_request_update()

## Defines the distance between each generated cube. Used to control grid density.
@export var cube_spacing: float = 1.1:
	set(value):
		cube_spacing = value
		_request_update()

## Selects the sine wave pattern logic.
## Used to alter the visual behavior of the wall without changing data.
@export var animation_mode: AnimationMode = AnimationMode.WAVE:
	set(value):
		animation_mode = value
		print("AnimatedCubeWall: animation_mode changed to ", value)
		_update_shader_uniforms()

## Determines how fast the sine wave propagates over time.
## Used to speed up or slow down the wave effect.
@export var movement_speed: float = 2.0:
	set(value):
		movement_speed = value
		print("AnimatedCubeWall: movement_speed changed to ", value)
		_update_shader_uniforms()

## Determines the maximum depth displacement.
## Used to scale the physical push/pull distance of the cubes.
@export var movement_amplitude: float = 1.0:
	set(value):
		movement_amplitude = value
		print("AnimatedCubeWall: movement_amplitude changed to ", value)
		_update_shader_uniforms()

## Sets the baseline color of the cubes.
## Used to multiply against the sine intensity for glowing effects.
@export var emissive_color: Color = Color(0.0, 0.8, 1.0, 1.0):
	set(value):
		emissive_color = value
		print("AnimatedCubeWall: emissive_color changed to ", value)
		_update_shader_uniforms()

## An optional custom mesh to use instead of a basic box.
## Used if you want custom shapes like hexes or spheres.
@export var custom_mesh: Mesh = null:
	set(value):
		custom_mesh = value
		_request_update()

## The MultiMeshInstance3D child node that renders all the cubes efficiently.
var _multi_mesh_instance: MultiMeshInstance3D = null

## The dynamic ShaderMaterial applied to the MultiMesh to handle GPU displacement.
var _shader_material: ShaderMaterial = null


## Called when the node enters the scene tree for the first time.
## Sets up the child [MultiMeshInstance3D] and generates the grid.
func _ready() -> void:
	print("AnimatedCubeWall: _ready() called. Initializing grid.")
	_setup_child_node()
	_generate_wall()


## Locates or creates the required [MultiMeshInstance3D] child node.
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


## Triggers a regeneration of the wall if the node is fully initialized in the tree.
func _request_update() -> void:
	if is_node_ready():
		_generate_wall()


## Clears and rebuilds the [MultiMesh] data buffers, positioning all cubes in a grid.
func _generate_wall() -> void:
	var total_cubes: int = grid_width * grid_height
	print("AnimatedCubeWall: _generate_wall() called. Spawning ", total_cubes)

	if _multi_mesh_instance == null:
		return

	var mm: MultiMesh = _multi_mesh_instance.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true  # Critical: Allows passing unique data to the shader
		mm.use_colors = true
		_multi_mesh_instance.multimesh = mm

	if not mm.use_colors:
		mm.use_colors = true
	if not mm.use_custom_data:
		mm.use_custom_data = true

	# Set up the Shader Material
	if _shader_material == null:
		_shader_material = ShaderMaterial.new()
		var shader: Shader = Shader.new()
		shader.code = SHADER_CODE
		_shader_material.shader = shader
		_update_shader_uniforms()

	if custom_mesh != null:
		mm.mesh = custom_mesh
	else:
		if mm.mesh == null or not mm.mesh is BoxMesh:
			var box: BoxMesh = BoxMesh.new()
			mm.mesh = box

	# Apply material to the mesh
	mm.mesh.surface_set_material(0, _shader_material)

	mm.instance_count = 0
	mm.instance_count = total_cubes

	var instance_id: int = 0
	for x: int in range(grid_width):
		for y: int in range(grid_height):
			var pos_x: float = (float(x) - float(grid_width) / 2.0 + 0.5) * cube_spacing
			var pos_y: float = (float(y) - float(grid_height) / 2.0 + 0.5) * cube_spacing

			var tform: Transform3D = Transform3D()
			tform = tform.translated(Vector3(pos_x, pos_y, 0.0))
			mm.set_instance_transform(instance_id, tform)

			# Pass: Random Offset (x), Grid X (y), Grid Y (z), and an unused w component
			var custom_data: Color = Color(randf() * PI * 2.0, float(x), float(y), 0.0)
			mm.set_instance_custom_data(instance_id, custom_data)

			instance_id += 1


## Pushes the current exported properties to the active [ShaderMaterial] uniforms.
func _update_shader_uniforms() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("animation_mode", int(animation_mode))
	_shader_material.set_shader_parameter("movement_speed", movement_speed)
	_shader_material.set_shader_parameter("movement_amplitude", movement_amplitude)
	_shader_material.set_shader_parameter("grid_width", float(grid_width))
	_shader_material.set_shader_parameter("grid_height", float(grid_height))
	_shader_material.set_shader_parameter(
		"emissive_color", Vector3(emissive_color.r, emissive_color.g, emissive_color.b)
	)
