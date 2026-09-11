## Generates procedural density maps for Variable Rate Shading (VRS).
class_name VrsTextureGenerator
extends RefCounted


## Generates a radial falloff texture for [member Viewport.vrs_texture].
## [param size] Pixel resolution of the density map.
## [return] Configured [ImageTexture] resource.
static func create_radial_density_map(size: Vector2i = Vector2i(128, 128)) -> ImageTexture:
	print("VrsTextureGenerator: Generating radial VRS density map.")
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var center: Vector2 = Vector2(size) * 0.5
	var max_dist: float = center.length()

	for y: int in range(size.y):
		for x: int in range(size.x):
			var dist: float = Vector2(x, y).distance_to(center)
			var factor: float = clampf(1.0 - (dist / max_dist), 0.0, 1.0)
			var density: float = smoothstep(0.0, 0.6, factor)
			img.set_pixel(x, y, Color(density, density, density, 1.0))

	return ImageTexture.create_from_image(img)
