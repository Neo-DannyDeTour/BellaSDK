## Generates procedural density maps for Variable Rate Shading (VRS).
class_name VrsTextureGenerator
extends RefCounted

## Cached radial VRS texture instance preventing redundant generation.
static var _cached_vrs_texture: ImageTexture = null


## Generates or returns a cached radial falloff texture for VRS.
## [param size] Pixel resolution of the density map.
## [return] Configured [ImageTexture] resource.
static func create_radial_density_map(size: Vector2i = Vector2i(128, 128)) -> ImageTexture:
	if is_instance_valid(_cached_vrs_texture):
		print("VrsTextureGenerator: Returning cached radial VRS map.")
		return _cached_vrs_texture

	print("VrsTextureGenerator: Generating radial VRS density map.")
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var center: Vector2 = Vector2(size) * 0.5
	var max_dist_sq: float = center.length_squared()

	for y: int in range(size.y):
		for x: int in range(size.x):
			var dist_sq: float = Vector2(x, y).distance_squared_to(center)
			var factor: float = (
				clampf(1.0 - (dist_sq / max_dist_sq), 0.0, 1.0) if max_dist_sq > 0.0 else 0.0
			)
			var density: float = smoothstep(0.0, 0.6, factor)
			img.set_pixel(x, y, Color(density, density, density, 1.0))

	_cached_vrs_texture = ImageTexture.create_from_image(img)
	return _cached_vrs_texture
