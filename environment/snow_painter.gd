## Canvas painter stamping boot prints and slam craters into the deformation buffer.
class_name SnowPainter
extends Node2D

const STAMP_STRIDE: int = 5

## Grayscale boot print texture assigned in the Inspector.
@export var footprint_texture: Texture2D

## Optional grayscale impact crater texture for butt slams (auto-generated if null).
@export var slam_texture: Texture2D

## Tracks whether the initial black canvas clear has been drawn.
var _needs_initial_clear: bool = true

## Flat float buffer storing [x, y, radius, intensity, angle] per queued stamp.
var _stamp_data: PackedFloat32Array = PackedFloat32Array()

## Parallel texture array matching each queued stamp entry.
var _stamp_textures: Array[Texture2D] = []

## Cached parent [SubViewport] reference to trigger single-frame updates.
@onready var _viewport: SubViewport = get_viewport() as SubViewport


## Validates brush textures, generates radial slam fallback if empty, and clears canvas.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(footprint_texture), "Missing footprint_texture in SnowPainter.")

	if not is_instance_valid(slam_texture):
		slam_texture = _create_radial_crater_texture()

	print("[SnowPainter] Initializing footprint and slam brush textures.")
	queue_redraw()


## Renders only newly queued stamps into the persistent SubViewport frame buffer.
func _draw() -> void:
	if _needs_initial_clear:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color.BLACK)
		_needs_initial_clear = false

	var count: int = _stamp_textures.size()
	if count == 0:
		return

	for i: int in range(count):
		var tex: Texture2D = _stamp_textures[i]
		if not is_instance_valid(tex):
			continue

		var base_idx: int = i * STAMP_STRIDE
		var pos: Vector2 = Vector2(_stamp_data[base_idx], _stamp_data[base_idx + 1])
		var radius_px: float = _stamp_data[base_idx + 2]
		var intensity: float = _stamp_data[base_idx + 3]
		var angle_rad: float = _stamp_data[base_idx + 4]

		var tex_size: Vector2 = tex.get_size()
		var diameter: float = radius_px * 2.0
		var scale_vec: Vector2 = Vector2(diameter / tex_size.x, diameter / tex_size.y)

		draw_set_transform(pos, angle_rad, scale_vec)
		draw_texture(tex, -tex_size * 0.5, Color(1.0, 1.0, 1.0, intensity))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_stamp_data.clear()
	_stamp_textures.clear()


## Queues a footprint or slam crater stamp at [param canvas_pos] and wakes the SubViewport.
func add_stamp(
	canvas_pos: Vector2,
	radius: float,
	intensity: float,
	angle_rad: float = 0.0,
	is_slam: bool = false
) -> void:
	var active_tex: Texture2D = slam_texture if is_slam else footprint_texture
	if not is_instance_valid(active_tex):
		return

	print(
		"[SnowPainter] Stamping at pos: ",
		canvas_pos,
		" slam: ",
		is_slam,
		" angle: ",
		rad_to_deg(angle_rad)
	)
	_stamp_data.append(canvas_pos.x)
	_stamp_data.append(canvas_pos.y)
	_stamp_data.append(radius)
	_stamp_data.append(intensity)
	_stamp_data.append(angle_rad)
	_stamp_textures.append(active_tex)

	queue_redraw()
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Builds a procedural soft radial [GradientTexture2D] when no custom slam texture is set.
func _create_radial_crater_texture() -> GradientTexture2D:
	var grad: Gradient = Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	grad.add_point(0.65, Color(0.85, 0.85, 0.85, 0.8))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex
