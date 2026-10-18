## Deformable snow ground with procedural terrain heightmap collision.
class_name SnowGround
extends MeshInstance3D

## Emitted when [method deform_at] writes a footprint or impact impression.
signal deformed(world_position: Vector3)

const PARAM_DISPLACEMENT: StringName = &"displacement_texture"
const PARAM_DIMENSIONS: StringName = &"ground_dimensions"
const PARAM_NOISE: StringName = &"base_height_noise"
const PARAM_HEIGHT_SCALE: StringName = &"terrain_height_scale"
const HEIGHTMAP_RES: int = 64

## Physical dimensions of the ground mesh plane in world units.
@export var plane_size: Vector2 = Vector2(20.0, 20.0)

## Reference to the [SubViewport] containing the canvas painter.
@onready var deform_viewport: SubViewport = $DeformViewport

## Reference to the [SnowPainter] child node.
@onready var snow_painter: SnowPainter = $DeformViewport/SnowPainter

## Collision shape reference to update height data.
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D


## Hooks dynamic textures to shader and configures on-demand SubViewport updates.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(deform_viewport), "Missing DeformViewport child.")
	assert(is_instance_valid(snow_painter), "Missing SnowPainter child.")
	assert(is_instance_valid(collision_shape), "Missing CollisionShape3D child.")

	print("[SnowGround] Hooking viewport texture to displacement shader.")
	deform_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	deform_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var mat: ShaderMaterial = get_active_material(0) as ShaderMaterial
	if mat:
		var tex: ViewportTexture = deform_viewport.get_texture()
		mat.set_shader_parameter(PARAM_DISPLACEMENT, tex)
		mat.set_shader_parameter(PARAM_DIMENSIONS, plane_size)
		_setup_heightmap_collision(mat)


## Converts a 3D [param world_position] into UV space and commands [SnowPainter] to deform.
func deform_at(
	world_position: Vector3,
	radius_px: float = 28.0,
	intensity: float = 0.6,
	angle_rad: float = 0.0,
	is_slam: bool = false
) -> void:
	var local_pos: Vector3 = to_local(world_position)
	var half_size: Vector2 = plane_size * 0.5

	if absf(local_pos.x) > half_size.x or absf(local_pos.z) > half_size.y:
		return

	var uv: Vector2 = Vector2(
		(local_pos.x + half_size.x) / plane_size.x, (local_pos.z + half_size.y) / plane_size.y
	)
	var canvas_pos: Vector2 = uv * Vector2(deform_viewport.size)

	print("[SnowGround] Displacing snow at world coordinates: ", world_position)
	snow_painter.add_stamp(canvas_pos, radius_px, intensity, angle_rad, is_slam)
	deformed.emit(world_position)


## Generates a matching [HeightMapShape3D] from the material's noise texture.
func _setup_heightmap_collision(mat: ShaderMaterial) -> void:
	var noise_obj: Object = mat.get_shader_parameter(PARAM_NOISE)
	var noise_tex: NoiseTexture2D = noise_obj as NoiseTexture2D
	if not noise_tex or not is_instance_valid(collision_shape):
		return

	if noise_tex.get_image() == null:
		await noise_tex.changed

	var noise_img: Image = noise_tex.get_image()
	if not noise_img:
		return

	var height_scale: float = type_convert(mat.get_shader_parameter(PARAM_HEIGHT_SCALE), TYPE_FLOAT)
	noise_img.resize(HEIGHTMAP_RES, HEIGHTMAP_RES, Image.INTERPOLATE_BILINEAR)

	var map_data: PackedFloat32Array = PackedFloat32Array()
	map_data.resize(HEIGHTMAP_RES * HEIGHTMAP_RES)

	for y: int in range(HEIGHTMAP_RES):
		var row_offset: int = y * HEIGHTMAP_RES
		for x: int in range(HEIGHTMAP_RES):
			map_data[row_offset + x] = noise_img.get_pixel(x, y).r * height_scale

	var h_shape: HeightMapShape3D = HeightMapShape3D.new()
	h_shape.map_width = HEIGHTMAP_RES
	h_shape.map_depth = HEIGHTMAP_RES
	h_shape.map_data = map_data

	collision_shape.shape = h_shape
	var step_x: float = plane_size.x / float(HEIGHTMAP_RES - 1)
	var step_z: float = plane_size.y / float(HEIGHTMAP_RES - 1)
	collision_shape.scale = Vector3(step_x, 1.0, step_z)
	print("[SnowGround] Procedural heightmap collision generated successfully.")
