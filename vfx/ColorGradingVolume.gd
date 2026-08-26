@tool
class_name ColorGradingVolume3D
extends Area3D

enum Preset { CUSTOM, BLACK_AND_WHITE, SEPIA, COLD, WARM }
enum ShapeType { BOX, SPHERE }

@export_category("Editor Visualization")

## Determines the shape of the physical volume and its visual representation in the editor.
@export var shape_type: ShapeType = ShapeType.BOX:
	set(value):
		shape_type = value
		_update_visuals()

## Determines if the trigger visualizer mesh should be visible during active gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		_update_visuals()

## Defines the physical dimensions of the color grading volume and its visual representation.
@export var volume_size: Vector3 = Vector3(4.0, 4.0, 4.0):
	set(value):
		volume_size = value
		_update_visuals()

## Sets the visual color of the volume box in the editor to help differentiate trigger types.
@export var volume_color: Color = Color(0.2, 0.6, 1.0, 0.4):
	set(value):
		volume_color = value
		_update_visuals()

## Determines the text displayed above the volume in the editor for quick identification.
@export var volume_text: String = "COLOR GRADING":
	set(value):
		volume_text = value
		_update_visuals()

@export_category("Color Grading Volume")

## The custom color grading shader file (.gdshader) containing the AAA features.
@export var grading_shader: Shader:
	set(value):
		grading_shader = value
		_initialize_material()

## Predefined color grading settings to quickly apply specific visual moods.
@export var preset: Preset = Preset.CUSTOM:
	set(value):
		preset = value
		_apply_preset()

@export_group("Base Parameters")

## Adjusts the overall lightness or darkness of the screen image.
@export var brightness: float = 1.0:
	set(value):
		brightness = value
		_update_shader_params()

## Modifies the difference between the lightest and darkest areas of the image.
@export var contrast: float = 1.0:
	set(value):
		contrast = value
		_update_shader_params()

## Changes the intensity and vibrancy of the colors on screen.
@export var saturation: float = 1.0:
	set(value):
		saturation = value
		_update_shader_params()

@export_group("White Balance")

## Shifts the image temperature toward cool blue (negative) or warm orange (positive).
@export_range(-1.0, 1.0) var temperature: float = 0.0:
	set(value):
		temperature = value
		_update_shader_params()

## Shifts the image tint toward green (negative) or magenta (positive).
@export_range(-1.0, 1.0) var tint: float = 0.0:
	set(value):
		tint = value
		_update_shader_params()

@export_group("ASC CDL (Color Wheels)")

## Tints and adjusts the darkest parts of the image (Shadows).
@export var lift_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		lift_color = value
		_update_shader_params()

## Tints and adjusts the middle range of the image (Midtones).
@export var gamma_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		gamma_color = value
		_update_shader_params()

## Tints and adjusts the brightest areas of the image (Highlights).
@export var gain_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		gain_color = value
		_update_shader_params()

@export_group("3D LUT")

## The 3D Look-Up Table texture used for complex baked color transformations.
@export var lut_texture: Texture3D:
	set(value):
		lut_texture = value
		_update_shader_params()

## Controls how strongly the 3D LUT overrides the underlying color adjustments.
@export_range(0.0, 1.0) var lut_intensity: float = 0.0:
	set(value):
		lut_intensity = value
		_update_shader_params()

@export_group("Cinematic Lens")

## Applies red and blue color separation at the edges of the screen to simulate lens distortion.
@export_range(0.0, 0.05) var aberration_amount: float = 0.0:
	set(value):
		aberration_amount = value
		_update_shader_params()

## Darkens the edges of the screen to draw the player's eye toward the center.
@export_range(0.0, 1.0) var vignette_intensity: float = 0.0:
	set(value):
		vignette_intensity = value
		_update_shader_params()

## Adds subtle, animated noise overlay to simulate film texture and prevent color banding.
@export_range(0.0, 1.0) var grain_amount: float = 0.0:
	set(value):
		grain_amount = value
		_update_shader_params()

@export_group("World Bloom Override")

## The specific WorldEnvironment node to target for high-quality glow/bloom changes.
@export var target_environment: WorldEnvironment

## The target glow intensity applied to the WorldEnvironment when the player enters.
@export var volume_bloom_intensity: float = 1.0

@export_group("Volume Control")

## The duration in seconds it takes for the color grading and bloom effects to fade in or out.
@export var blend_time: float = 1.0

## Toggles the color grading overlay in the editor for previewing changes.
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		_update_editor_preview()

## The CanvasLayer used to draw the color grading overlay on top of the screen UI.
var _canvas_layer: CanvasLayer

## Captures the screen texture to be processed by the color grading shader.
var _back_buffer: BackBufferCopy

## The UI element that holds the shader material and applies it across the screen.
var _color_rect: ColorRect

## Handles the smooth interpolation of the effect's opacity when a player enters or exits.
var _blend_tween: Tween

## Handles the smooth interpolation of the WorldEnvironment glow intensity.
var _bloom_tween: Tween

## The active shader material containing the color grading logic and parameters.
var _material: ShaderMaterial

## Stores the original glow intensity of the target environment to restore upon exiting.
var _original_glow_intensity: float = 0.0

## Stores the original bloom spread value of the target environment to restore upon exiting.
var _original_glow_bloom: float = 0.0


## Lifecycle method handling editor visualization setup or runtime signal connections.
func _ready() -> void:
	if Engine.is_editor_hint():
		_update_visuals()
	else:
		add_to_group("color_grading_volumes")

		if not show_in_game:
			for child: Node in get_children():
				if child.get_class() == "EditorTriggerVisualizer":
					child.queue_free()

		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

		if target_environment and target_environment.environment:
			_original_glow_intensity = target_environment.environment.glow_intensity
			_original_glow_bloom = target_environment.environment.glow_bloom
			# Force glow enabled to ensure the bloom tween has a visible impact
			target_environment.environment.glow_enabled = true

	print("ColorGradingVolume3D: Initializing node setup for screen overlay.")
	_setup_screen_ui()


func _update_visuals() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		if shape_type == ShapeType.BOX:
			if not col.shape is BoxShape3D:
				col.shape = BoxShape3D.new()

			if not col.shape.resource_local_to_scene:
				col.shape = col.shape.duplicate()
				col.shape.resource_local_to_scene = true

			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = volume_size

		elif shape_type == ShapeType.SPHERE:
			if not col.shape is SphereShape3D:
				col.shape = SphereShape3D.new()

			if not col.shape.resource_local_to_scene:
				col.shape = col.shape.duplicate()
				col.shape.resource_local_to_scene = true

			var sphere: SphereShape3D = col.shape as SphereShape3D
			sphere.radius = volume_size.x / 2.0

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if visual:
		if visual.mesh and not visual.mesh.resource_local_to_scene:
			visual.mesh = visual.mesh.duplicate(true)
			visual.mesh.resource_local_to_scene = true

		@warning_ignore("int_as_enum_without_cast")
		visual.shape_type = shape_type as int
		visual.show_in_game = show_in_game
		visual.trigger_size = volume_size
		visual.trigger_color = volume_color
		visual.trigger_text = volume_text


func _get_visualizer() -> EditorTriggerVisualizer:
	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			return child as EditorTriggerVisualizer
	return null


func _setup_screen_ui() -> void:
	print("ColorGradingVolume3D: Spawning CanvasLayer, BackBufferCopy, and ColorRect.")
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 10
	add_child(_canvas_layer)

	_back_buffer = BackBufferCopy.new()
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_canvas_layer.add_child(_back_buffer)

	_color_rect = ColorRect.new()
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.modulate.a = 0.0
	_color_rect.hide()

	_canvas_layer.add_child(_color_rect)
	_initialize_material()


func _initialize_material() -> void:
	if not is_inside_tree() or not _color_rect or not grading_shader:
		return

	if not _material:
		_material = ShaderMaterial.new()
		_color_rect.material = _material

	_material.shader = grading_shader
	_update_shader_params()
	_update_editor_preview()


func _update_shader_params() -> void:
	if not _material:
		return

	_material.set_shader_parameter("brightness", brightness)
	_material.set_shader_parameter("contrast", contrast)
	_material.set_shader_parameter("saturation", saturation)

	_material.set_shader_parameter("temperature", temperature)
	_material.set_shader_parameter("tint", tint)

	_material.set_shader_parameter("lift_color", Vector3(lift_color.r, lift_color.g, lift_color.b))
	_material.set_shader_parameter(
		"gamma_color", Vector3(gamma_color.r, gamma_color.g, gamma_color.b)
	)
	_material.set_shader_parameter("gain_color", Vector3(gain_color.r, gain_color.g, gain_color.b))

	if lut_texture:
		_material.set_shader_parameter("lut_texture", lut_texture)
	_material.set_shader_parameter("lut_intensity", lut_intensity)

	_material.set_shader_parameter("aberration_amount", aberration_amount)
	_material.set_shader_parameter("vignette_intensity", vignette_intensity)
	_material.set_shader_parameter("grain_amount", grain_amount)


func _apply_preset() -> void:
	if preset == Preset.CUSTOM:
		return

	match preset:
		Preset.BLACK_AND_WHITE:
			brightness = 1.0
			contrast = 1.2
			saturation = 0.0
			temperature = 0.0
		Preset.SEPIA:
			brightness = 0.9
			contrast = 1.1
			saturation = 0.0
			temperature = 0.5
			lift_color = Color(0.1, 0.05, 0.0)
			gamma_color = Color(1.2, 1.0, 0.8)
		Preset.COLD:
			brightness = 1.0
			contrast = 1.05
			saturation = 0.9
			temperature = -0.6
		Preset.WARM:
			brightness = 1.05
			contrast = 1.05
			saturation = 1.1
			temperature = 0.6


func _update_editor_preview() -> void:
	if not is_inside_tree() or not _color_rect:
		return

	if Engine.is_editor_hint():
		if preview_in_editor and grading_shader:
			print("ColorGradingVolume3D: Enabling editor preview visibility.")
			_color_rect.show()
			_color_rect.modulate.a = 1.0
		else:
			print("ColorGradingVolume3D: Disabling editor preview visibility.")
			_color_rect.hide()
			_color_rect.modulate.a = 0.0


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		print("ColorGradingVolume3D: Player entered volume. Fading in color and bloom VFX.")
		_fade_effect(1.0)
		_fade_bloom(volume_bloom_intensity)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		print("ColorGradingVolume3D: Player exited volume. Fading out color and bloom VFX.")
		_fade_effect(0.0)
		_fade_bloom(_original_glow_bloom)


func _fade_effect(target_alpha: float) -> void:
	print("ColorGradingVolume3D: Executing shader alpha fade to ", target_alpha)
	if target_alpha > 0.0:
		_color_rect.show()

	if _blend_tween and _blend_tween.is_valid():
		_blend_tween.kill()

	_blend_tween = create_tween()
	_blend_tween.tween_property(_color_rect, "modulate:a", target_alpha, blend_time).set_trans(
		Tween.TRANS_SINE
	)

	if target_alpha <= 0.0:
		_blend_tween.tween_callback(_color_rect.hide)


func _fade_bloom(target_intensity: float) -> void:
	if not target_environment or not target_environment.environment:
		return

	print("ColorGradingVolume3D: Executing environment bloom fade to ", target_intensity)

	if _bloom_tween and _bloom_tween.is_valid():
		_bloom_tween.kill()

	_bloom_tween = create_tween()
	(
		_bloom_tween
		. tween_property(target_environment.environment, "glow_bloom", target_intensity, blend_time)
		. set_trans(Tween.TRANS_SINE)
	)


## Instantly resets all color grading shader overlays and restores bloom settings.
func reset_to_default() -> void:
	print("ColorGradingVolume3D: Resetting volume overlay to defaults.")
	if _blend_tween and _blend_tween.is_valid():
		_blend_tween.kill()
	if _bloom_tween and _bloom_tween.is_valid():
		_bloom_tween.kill()

	if _color_rect:
		_color_rect.modulate.a = 0.0
		_color_rect.hide()

	if target_environment and target_environment.environment:
		target_environment.environment.glow_bloom = _original_glow_bloom
