## Horror UI button featuring wide octagon slabs, spring physics, and tilts.
@tool
class_name HorrorButton
extends Button

# --- GLOBAL CONFIGURATION ---

## Total active [HorrorButton] instances currently tracked in scene.
static var active_horror_buttons: int = 0

# --- INSPECTOR PROPERTIES ---

## Toggles complete background slab visibility for external placement flexibility.
@export var invisible_background: bool = false:
	set(value):
		invisible_background = value
		if is_instance_valid(bg_rect) and is_inside_tree():
			bg_rect.visible = not value

## Corner chamfer cut distance in pixels forming an octagon silhouette.
@export var corner_cut: float = 14.0:
	set(value):
		corner_cut = value
		if is_inside_tree():
			_update_corner_cuts()

## Button text displayed in inspector and updated live in the scene.
@export var custom_text: String = "":
	set(value):
		custom_text = value
		if is_instance_valid(text_label) and is_inside_tree():
			text_label.text = value
		if is_inside_tree():
			update_minimum_size()

## Horizontal and vertical padding for container layout calculations.
@export var text_padding: Vector2 = Vector2(32.0, 16.0):
	set(value):
		text_padding = value
		if is_inside_tree():
			update_minimum_size()

# --- ANIMATION CONFIGURATION ---

## Visual scale multiplier applied to offset transform when hovered.
@export var hover_scale: Vector2 = Vector2(1.08, 1.08)

## Spring stiffness determining bounce responsiveness for hover animations.
@export var spring_stiffness: float = 240.0

## Spring damping factor controlling bounce settling and oscillation.
@export var spring_damping: float = 14.0

## Interpolation speed for smooth hover transitions and parallax.
@export var response_speed: float = 12.0

## Visual scale multiplier applied to button while pressed down.
@export var press_scale: Vector2 = Vector2(0.94, 0.94)

## Vertical pixel translation simulating physical press depth.
@export var press_depth: float = 8.0

## Interpolation speed for button press and release animations.
@export var press_speed: float = 20.0

## Optional background textures randomly selected on ready.
@export var background_images: Array[Texture2D] = []

## Scratch and pit texture to break up specular shine sweep.
@export var scratch_texture: Texture2D

## Ambient horizontal drift speed for idle text shadows.
@export var walk_speed: float = 0.2

## Fast tracking speed for shadows chasing cursor on hover.
@export var hunt_speed: float = 6.0

## Corrupted glitch text shown during terror animation cycles.
@export var glitch_text: String = "":
	set(value):
		glitch_text = value
		can_glitch = not value.is_empty()
		if is_inside_tree():
			update_minimum_size()

## Duration in seconds that text corruption glitch remains active.
@export var glitch_duration: float = 0.666

## Minimum wait duration in seconds before next glitch sequence.
@export var min_glitch_time: float = 15.0

## Maximum wait duration in seconds before next glitch sequence.
@export var max_glitch_time: float = 20.0

## Frequency speed of text pulsing animation during hover.
@export var pulse_speed: float = 6.0

## Scale intensity multiplier for text hover pulse oscillation.
@export var pulse_intensity: float = 0.08

## Maximum rotational degrees applied during mouse parallax tilt.
@export var max_rotation_degrees: float = 8.0

## Movement scale factor applied to text parallax displacement.
@export var parallax_intensity: float = 3.0

## Mask texture used for flashlight illumination highlights.
@export var flashlight_texture: Texture2D

## Texture displayed on the button face for chapter previews and card graphics.
@export var button_image: Texture2D = null:
	set(value):
		button_image = value
		if is_inside_tree():
			_update_button_image()

## Dedicated minimum size override for card thumbnail mode.
@export var card_size: Vector2 = Vector2(240.0, 135.0)

## Default idle brightness intensity maintained for chapter card previews.
@export var card_base_brightness: float = 0.85

## Hovered brightness intensity applied when cursor enters chapter card.
@export var card_hover_brightness: float = 1.0

## Icon texture used for chapter play overlay button.
@export var play_icon: Texture2D

# --- INTERNAL STATE ---
## Internal or child texture rect representing the play icon overlay.
var play_overlay: TextureRect

## Dedicated child node rendering projected contact drop shadow.
var shadow_rect: Control

## Cached internal [Label] node presenting button text.
var text_label: Label

## Shader material handling ghosting and text drop-shadows.
var label_material: ShaderMaterial

## Internal [ColorRect] node serving as background slab.
var bg_rect: ColorRect

## Shader material controlling metal slab shine and lighting.
var bg_material: ShaderMaterial

## Internal [ColorRect] node providing the border contour.
var border_rect: ColorRect

## Shader material generating border outline hover glow.
var border_material: ShaderMaterial

## Current interpolation weight for active hover shaders.
var current_hover_intensity: float = 0.0

## Tracks whether mouse cursor is inside button bounds.
var is_mouse_over: bool = false

## Tracks whether mouse button is currently held pressed.
var is_clicking: bool = false

## Initial visual scale recorded at start for reset transitions.
var original_scale: Vector2

## Velocity vector governing damped spring scale oscillations.
var scale_velocity: Vector2 = Vector2.ZERO

## Current horizontal offsets of dual haunting text shadows.
var shadows_x: Array[float] = [0.0, 0.0]

## Target horizontal destination positions for roaming shadows.
var target_shadows_x: Array[float] = [0.0, 0.0]

## Cooldown timers governing when roaming shadows pick targets.
var pace_timers: Array[float] = [0.0, 0.0]

## Randomized movement drift velocities for text shadows.
var walk_speeds: Array[float] = [0.0, 0.0]

## Active tween animating light sweep across button face.
var shine_tween: Tween

## Current 2D tilt deformation applied from cursor offset.
var current_tilt: Vector2 = Vector2.ZERO

## Backed up text string restored after glitch event concludes.
var original_button_text: String = ""

## Countdown timer tracking time until next glitch trigger.
var glitch_timer: float = 0.0

## Indicates whether text glitch corruption is actively running.
var is_glitching: bool = false

## Safety status confirming glitch text parameter is defined.
var can_glitch: bool = false

## Previous control dimensions cached to detect resize changes.
var _last_known_size: Vector2 = Vector2.ZERO

## Tracks if button acts as a chapter card to skip random backgrounds.
var is_chapter_card: bool = false


## Handles engine notifications for layout resizing and theme updates.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		update_minimum_size()
		_sync_child_rects()
	elif what == NOTIFICATION_RESIZED:
		_sync_child_rects()


## Calculates required minimum [Vector2] bounds including text padding.
func _get_minimum_size() -> Vector2:
	if is_chapter_card:
		return card_size

	if not is_instance_valid(text_label):
		_find_internal_nodes()

	var required_size: Vector2 = Vector2.ZERO
	var font: Font = null
	var font_size: int = 16

	if is_instance_valid(text_label):
		font = text_label.get_theme_font(&"font", &"Label")
		font_size = text_label.get_theme_font_size(&"font_size", &"Label")
	else:
		font = get_theme_font(&"font", &"Button")
		font_size = get_theme_font_size(&"font_size", &"Button")

	if font == null:
		font = ThemeDB.fallback_font
	if font_size <= 0:
		font_size = ThemeDB.fallback_font_size

	var primary_str: String = custom_text
	if primary_str.is_empty() and is_instance_valid(text_label):
		primary_str = text_label.text
	if primary_str.is_empty():
		primary_str = text

	if font != null and not primary_str.is_empty():
		var size_primary: Vector2 = font.get_string_size(
			primary_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size
		)
		var size_glitch: Vector2 = Vector2.ZERO
		if not glitch_text.is_empty():
			size_glitch = font.get_string_size(
				glitch_text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size
			)
		required_size.x = maxf(size_primary.x, size_glitch.x)
		required_size.y = maxf(size_primary.y, size_glitch.y)

	return required_size + text_padding


## Updates background shader or rect texture when a preview image is assigned.
func _update_button_image() -> void:
	if is_instance_valid(bg_material) and button_image != null:
		bg_material.set_shader_parameter("blood_texture", button_image)


## Initializes node components, materials, styling, and signal hooks.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_find_internal_nodes()
	_configure_child_anchors()

	if is_instance_valid(bg_rect):
		bg_rect.visible = not invisible_background

	if Engine.is_editor_hint():
		return

	print("HorrorButton: [", name, "] initializing runtime state.")
	active_horror_buttons += 1
	flat = true
	offset_transform_enabled = true
	z_as_relative = true

	var empty_style: StyleBoxEmpty = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty_style)
	add_theme_stylebox_override("hover", empty_style)
	add_theme_stylebox_override("pressed", empty_style)
	add_theme_stylebox_override("disabled", empty_style)
	add_theme_stylebox_override("focus", empty_style)

	randomize()
	original_scale = offset_transform_scale

	button_down.connect(
		func() -> void:
			print("HorrorButton: [", name, "] pressed.")
			is_clicking = true
	)
	button_up.connect(
		func() -> void:
			print("HorrorButton: [", name, "] released.")
			is_clicking = false
	)

	glitch_timer = randf_range(min_glitch_time, max_glitch_time)

	if is_instance_valid(bg_rect) and bg_rect.material is ShaderMaterial:
		bg_material = bg_rect.material.duplicate() as ShaderMaterial
		bg_rect.material = bg_material
		bg_material.set_shader_parameter("hover_intensity", 0.0)
		bg_material.set_shader_parameter(
			"blood_offset", Vector2(randf_range(0.0, 100.0), randf_range(0.0, 100.0))
		)
		bg_material.set_shader_parameter("custom_light_texture", flashlight_texture)
		if scratch_texture != null:
			bg_material.set_shader_parameter("scratch_texture", scratch_texture)

		if not is_chapter_card and not background_images.is_empty():
			var random_index: int = randi() % background_images.size()
			bg_material.set_shader_parameter("blood_texture", background_images[random_index])
	else:
		bg_material = null

	if is_instance_valid(border_rect) and border_rect.material is ShaderMaterial:
		border_material = border_rect.material.duplicate() as ShaderMaterial
		border_rect.material = border_material
		border_material.set_shader_parameter("hover_intensity", 0.0)
	else:
		border_material = null

	if is_instance_valid(text_label):
		if not custom_text.is_empty():
			text_label.text = custom_text
			original_button_text = custom_text
		else:
			original_button_text = text_label.text

	can_glitch = not glitch_text.is_empty()

	if is_instance_valid(text_label) and text_label.material is ShaderMaterial:
		label_material = text_label.material.duplicate() as ShaderMaterial
		text_label.material = label_material

		for i: int in 2:
			shadows_x[i] = randf_range(-0.5, 1.5)
			target_shadows_x[i] = shadows_x[i]
			pace_timers[i] = randf_range(0.0, 2.0)
			walk_speeds[i] = randf_range(walk_speed * 0.6, walk_speed * 1.4)
	else:
		label_material = null

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	update_minimum_size()
	_sync_child_rects()
	_update_corner_cuts()


## Locates internal child nodes and enforces input passthrough filters.
func _find_internal_nodes() -> void:
	for child: Node in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if child is Label:
			text_label = child as Label
		elif child is ColorRect and child.name == "Border":
			border_rect = child as ColorRect
		elif child is ColorRect and child.name == "Background":
			bg_rect = child as ColorRect
		elif child is TextureRect and child.name == "PlayOverlay":
			play_overlay = child as TextureRect
		elif child is TextureRect or child.name == "Shadow":
			shadow_rect = child as Control


## Sets full rect anchoring and centering presets for internal children.
func _configure_child_anchors() -> void:
	for node: Control in [bg_rect, border_rect, text_label, shadow_rect]:
		if is_instance_valid(node):
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node.set_anchors_preset(Control.PRESET_FULL_RECT)
			node.offset_left = 0.0
			node.offset_top = 0.0
			node.offset_right = 0.0
			node.offset_bottom = 0.0

	if is_instance_valid(shadow_rect):
		shadow_rect.show_behind_parent = true
		shadow_rect.modulate.a = 0.0

	if is_instance_valid(text_label):
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Synchronizes dimensions and pivots to child shaders and nodes.
func _sync_child_rects() -> void:
	if size == _last_known_size:
		return

	_last_known_size = size
	pivot_offset = size / 2.0

	if is_instance_valid(shadow_rect):
		shadow_rect.pivot_offset = size / 2.0
	if is_instance_valid(text_label):
		text_label.pivot_offset = size / 2.0

	if is_instance_valid(bg_material):
		bg_material.set_shader_parameter("rect_size", size)
	if is_instance_valid(border_material):
		border_material.set_shader_parameter("rect_size", size)
	if is_instance_valid(label_material):
		label_material.set_shader_parameter("rect_size", size)


## Updates corner cut parameters across internal shader materials.
func _update_corner_cuts() -> void:
	if is_instance_valid(bg_material):
		bg_material.set_shader_parameter("corner_cut", corner_cut)
	if is_instance_valid(border_material):
		border_material.set_shader_parameter("corner_cut", corner_cut)


## Triggers hover transitions, elevates z-index, and starts sweep tween.
func _on_mouse_entered() -> void:
	print("HorrorButton: [", name, "] mouse hover entered.")
	is_mouse_over = true
	z_index = 2
	if is_instance_valid(play_overlay):
		play_overlay.visible = true

	if is_instance_valid(bg_material):
		if is_instance_valid(shine_tween) and shine_tween.is_valid():
			shine_tween.kill()

		shine_tween = create_tween()
		bg_material.set_shader_parameter("sweep_progress", -0.3)
		(
			shine_tween
			. tween_method(
				func(val: float) -> void:
					if is_instance_valid(bg_material):
						bg_material.set_shader_parameter("sweep_progress", val),
				-0.3,
				1.8,
				0.55
			)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)


## Resets hover state, lowers z-index, and clears click tracker.
func _on_mouse_exited() -> void:
	print("HorrorButton: [", name, "] mouse hover exited.")
	is_mouse_over = false
	is_clicking = false
	z_index = 0
	if is_instance_valid(play_overlay):
		play_overlay.visible = false

	for i: int in 2:
		pace_timers[i] = 0.0


## Drives damped spring physics toward target scale vectors.
func _update_spring_scale(delta: float, target_scale: Vector2) -> void:
	var delta_pos: Vector2 = offset_transform_scale - target_scale
	var spring_force: Vector2 = (-spring_stiffness * delta_pos) - (spring_damping * scale_velocity)
	scale_velocity += spring_force * delta
	offset_transform_scale += scale_velocity * delta


## Updates contact shadow position and alpha based on tilt and lift.
func _update_shadow_projection() -> void:
	if not is_instance_valid(shadow_rect):
		return

	var lift: float = current_hover_intensity
	var drop: float = press_depth if is_clicking else 0.0
	var offset: Vector2 = Vector2(
		current_tilt.x * 10.0, (14.0 * lift) + (current_tilt.y * 6.0) - (drop * 0.4)
	)
	shadow_rect.position = offset
	shadow_rect.modulate.a = lift * 0.8
	var shadow_scale: float = 1.0 + (0.04 * lift)
	shadow_rect.scale = Vector2(shadow_scale, shadow_scale)


## Processes 3D parallax tilting, spring scales, and glitch timers.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if size.x <= 0.1 or size.y <= 0.1:
		return

	var mouse_pos: Vector2 = get_local_mouse_position()
	var center_x: float = size.x / 2.0
	var center_y: float = size.y / 2.0

	var target_rotation: float = 0.0
	var tilt_target: Vector2 = Vector2.ZERO
	var target_scale: Vector2 = original_scale

	if is_mouse_over:
		current_hover_intensity = move_toward(current_hover_intensity, 1.0, 3.5 * delta)
		var norm_x: float = clampf((mouse_pos.x - center_x) / center_x, -1.0, 1.0)
		var norm_y: float = clampf((mouse_pos.y - center_y) / center_y, -1.0, 1.0)
		target_rotation = deg_to_rad(max_rotation_degrees * norm_x)
		tilt_target = Vector2(norm_x, norm_y)

		if is_clicking:
			target_scale = press_scale
		else:
			var pitch: float = 1.0 - (absf(norm_y) * 0.04)
			target_scale = hover_scale * Vector2(1.0, pitch)
	else:
		current_hover_intensity = move_toward(current_hover_intensity, 0.0, 3.0 * delta)
		target_scale = original_scale

	_update_spring_scale(delta, target_scale)
	offset_transform_rotation = lerpf(
		offset_transform_rotation, target_rotation, response_speed * delta
	)
	current_tilt = current_tilt.lerp(tilt_target, response_speed * delta)
	_update_shadow_projection()

	if is_instance_valid(bg_material):
		bg_material.set_shader_parameter("hover_intensity", current_hover_intensity)
		bg_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)
		if is_mouse_over and is_instance_valid(bg_rect):
			var local_mouse_pos: Vector2 = bg_rect.get_local_mouse_position()
			var mouse_uv: Vector2 = Vector2(
				local_mouse_pos.x / bg_rect.size.x, local_mouse_pos.y / bg_rect.size.y
			)
			bg_material.set_shader_parameter("mouse_pos_uv", mouse_uv)

	if is_instance_valid(border_material):
		border_material.set_shader_parameter("hover_intensity", current_hover_intensity)
		border_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)


## Configures button as a chapter card using [ChapterData] properties.
func setup_chapter_card(chapter: ChapterData) -> void:
	print("HorrorButton: [", name, "] setup chapter card executed.")
	is_chapter_card = true
	corner_cut = 0.0
	custom_text = ""
	text = ""
	glitch_text = ""
	can_glitch = false
	custom_minimum_size = card_size

	if not is_inside_tree():
		await ready

	_find_internal_nodes()

	if is_instance_valid(text_label):
		text_label.visible = false

	if is_instance_valid(bg_material):
		bg_material.set_shader_parameter("is_card_mode", true)
		bg_material.set_shader_parameter("corner_cut", 0.0)
		bg_material.set_shader_parameter("hover_intensity", 0.0)
		if chapter != null and chapter.image != null:
			bg_material.set_shader_parameter("blood_texture", chapter.image)

	if is_instance_valid(border_material):
		border_material.set_shader_parameter("hover_intensity", 0.0)
		border_material.set_shader_parameter("corner_cut", 0.0)

	if is_instance_valid(play_overlay):
		play_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		play_overlay.z_index = 1
		play_overlay.visible = false
		if play_icon != null:
			play_overlay.texture = play_icon

	_update_corner_cuts()
	_sync_child_rects()
