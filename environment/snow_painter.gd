## Canvas painter stamping detailed boot print textures into the deformation buffer.
class_name SnowPainter
extends Node2D

## Maximum number of persistent footprint stamps retained in the deformation buffer.
const MAX_STAMPS: int = 500

## Assign your grayscale boot print texture in the Inspector.
@export var footprint_texture: Texture2D

## The calculated scale needed to fit the footprint in the SubViewport.
var _texture_scale: Vector2 = Vector2.ONE

## Persistent buffer storing active stamps rasterized on redraw.
var _stamps: Array[Dictionary] = []


## Generates the radial gradient brush and requests the initial canvas clear.
func _ready() -> void:
	print("[SnowPainter] Initializing radial footprint brush texture.")
	if footprint_texture:
		var tex_size: Vector2 = footprint_texture.get_size()
		var vp_rect: Vector2 = get_viewport_rect().size
		var target_width: float = vp_rect.y * 0.5
		var scale_factor: float = target_width / tex_size.y
		_texture_scale = Vector2(scale_factor, scale_factor)
	else:
		push_error(
			(
				"[SnowPainter] Critical Error: 'footprint_texture' is missing. "
				+ "Assign it in the editor."
			)
		)

	queue_redraw()


## Renders all persistent footprint stamps directly into the frame buffer.
func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color.BLACK)

	if not footprint_texture:
		return

	for stamp: Dictionary in _stamps:
		var pos: Vector2 = stamp["position"]
		var radius_px: float = stamp["radius"]
		var intensity: float = stamp["intensity"]
		var angle_rad: float = stamp["angle"]

		var modulate_color: Color = Color(1.0, 1.0, 1.0, intensity)
		var stamp_rect: Rect2 = Rect2(
			pos - Vector2(radius_px, radius_px), Vector2(radius_px * 2.0, radius_px * 2.0)
		)

		draw_texture_rect_rotated(
			footprint_texture, stamp_rect, modulate_color, angle_rad, Vector2(0.5, 0.5)
		)


## Renders a texture with specific rotation, modulation, and target size.
func draw_texture_rect_rotated(
	texture: Texture2D, rect: Rect2, color: Color, angle_rad: float, pivot_ratio: Vector2
) -> void:
	var tex_size: Vector2 = texture.get_size()
	var scale_vec: Vector2 = Vector2(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var pivot: Vector2 = rect.size * pivot_ratio

	var draw_xform: Transform2D = Transform2D()
	draw_xform = draw_xform.translated(-pivot)
	draw_xform = draw_xform.scaled(scale_vec)
	draw_xform = draw_xform.rotated(angle_rad)
	draw_xform = draw_xform.translated(rect.position + pivot)

	draw_set_transform_matrix(draw_xform)
	draw_texture(texture, Vector2.ZERO, color)
	draw_set_transform_matrix(Transform2D())


## Appends a footprint stamp at [param canvas_pos] coordinates and requests redraw.
func add_stamp(
	canvas_pos: Vector2, radius: float, intensity: float, angle_rad: float = 0.0
) -> void:
	print(
		"[SnowPainter] Stamping footprint at pos: ", canvas_pos, " angle: ", rad_to_deg(angle_rad)
	)
	_stamps.append(
		{"position": canvas_pos, "radius": radius, "intensity": intensity, "angle": angle_rad}
	)
	if _stamps.size() > MAX_STAMPS:
		_stamps.pop_front()
	queue_redraw()
