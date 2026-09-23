## Deformable snow ground with procedural terrain heightmap collision.
class_name SnowGround
extends MeshInstance3D

## Emitted when [method deform_at] writes a footprint impression.
signal deformed(world_position: Vector3)

## Physical dimensions of the ground mesh plane in world units.
@export var plane_size: Vector2 = Vector2(20.0, 20.0)

## Reference to the [SubViewport] containing the canvas painter.
@onready var deform_viewport: SubViewport = $DeformViewport

## Reference to the [SnowPainter] child node.
@onready var snow_painter: SnowPainter = $DeformViewport/SnowPainter

## Collision shape reference to update height data.
@onready var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D


## Hooks dynamic textures to shader and generates uneven collision geometry.
func _ready() -> void:
	print("[SnowGround] Hooking viewport texture to displacement shader.")
	var mat: ShaderMaterial = get_active_material(0) as ShaderMaterial
	if mat:
		var tex: ViewportTexture = deform_viewport.get_texture()
		mat.set_shader_parameter("displacement_texture", tex)
		mat.set_shader_parameter("ground_dimensions", plane_size)
		_setup_heightmap_collision(mat)


## Converts a 3D [param world_position] into UV space and commands [SnowPainter] to deform.
func deform_at(
	world_position: Vector3, radius_px: float = 28.0, intensity: float = 0.6, angle_rad: float = 0.0
) -> void:
	var local_pos: Vector3 = to_local(world_position)
	var half_size: Vector2 = plane_size * 0.5

	if absf(local_pos.x) > half_size.x or absf(local_pos.z) > half_size.y:
		return

	var uv: Vector2 = Vector2(
		(local_pos.x + half_size.x) / plane_size.x, (local_pos.z + half_size.y) / plane_size.y
	)

	var vp_size: Vector2 = Vector2(deform_viewport.size)
	var canvas_pos: Vector2 = uv * vp_size

	print("[SnowGround] Displacing snow at world coordinates: ", world_position)
	# Forward the angle to the painter.
	snow_painter.add_stamp(canvas_pos, radius_px, intensity, angle_rad)
	deformed.emit(world_position)


## Generates a matching [HeightMapShape3D] from the material's noise texture.
func _setup_heightmap_collision(mat: ShaderMaterial) -> void:
	var noise_tex: NoiseTexture2D = mat.get_shader_parameter("base_height_noise") as NoiseTexture2D
	if not noise_tex or not is_instance_valid(collision_shape):
		return

	if noise_tex.get_image() == null:
		await noise_tex.changed

	var noise_img: Image = noise_tex.get_image()
	if not noise_img:
		return

	var height_scale: float = mat.get_shader_parameter("terrain_height_scale") as float
	var map_size: int = 64
	noise_img.resize(map_size, map_size, Image.INTERPOLATE_BILINEAR)

	var map_data: PackedFloat32Array = PackedFloat32Array()
	map_data.resize(map_size * map_size)

	for y: int in range(map_size):
		for x: int in range(map_size):
			var idx: int = y * map_size + x
			var val: float = noise_img.get_pixel(x, y).r * height_scale
			map_data[idx] = val

	var h_shape: HeightMapShape3D = HeightMapShape3D.new()
	h_shape.map_width = map_size
	h_shape.map_depth = map_size
	h_shape.map_data = map_data

	collision_shape.shape = h_shape
	var step_x: float = plane_size.x / float(map_size - 1)
	var step_z: float = plane_size.y / float(map_size - 1)
	collision_shape.scale = Vector3(step_x, 1.0, step_z)
	print("[SnowGround] Procedural heightmap collision generated successfully.")
