## Canvas painter stamping detailed boot print textures into the deformation buffer.
class_name SnowPainter
extends Node2D

## Assign your grayscale boot print texture in the Inspector.
@export var footprint_texture: Texture2D

## The calculated scale needed to fit the footprint in the SubViewport.
var _texture_scale: Vector2 = Vector2.ONE

## Tracks whether the initial black canvas clear has been drawn.
var _needs_initial_clear: bool = true

## Queue of new stamps to rasterize on the next [SubViewport.UPDATE_ONCE] pass.
var _pending_stamps: Array[Dictionary] = []


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


## Renders only newly queued footprint stamps into the persistent frame buffer.
func _draw() -> void:
	if _needs_initial_clear:
		var viewport_size: Vector2 = get_viewport_rect().size
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color.BLACK)
		_needs_initial_clear = false

	if not footprint_texture or _pending_stamps.is_empty():
		return

	for stamp: Dictionary in _pending_stamps:
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

	_pending_stamps.clear()


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


## Queues a single footprint stamp at [param canvas_pos] and wakes the SubViewport.
func add_stamp(
	canvas_pos: Vector2, radius: float, intensity: float, angle_rad: float = 0.0
) -> void:
	print(
		"[SnowPainter] Stamping footprint at pos: ", canvas_pos, " angle: ", rad_to_deg(angle_rad)
	)
	(
		_pending_stamps
		. append(
			{
				"position": canvas_pos,
				"radius": radius,
				"intensity": intensity,
				"angle": angle_rad,
			}
		)
	)
	queue_redraw()
	var vp: Viewport = get_viewport()
	if vp is SubViewport:
		(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
