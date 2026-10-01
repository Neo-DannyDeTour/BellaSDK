@tool
## 3D trigger applying color grading, LUTs, and bloom overrides to player.
class_name ColorGradingVolume3D
extends Area3D

## Visual preset options for common color grading profiles.
enum Preset { CUSTOM, BLACK_AND_WHITE, SEPIA, COLD, WARM }

## Geometry options for the 3D trigger visualizer and collision hull.
enum ShapeType { BOX, SPHERE }

## Determines the shape of the physical volume and its visual debug mesh.
@export var shape_type: ShapeType = ShapeType.BOX:
	set(value):
		shape_type = value
		_update_visuals()

## Determines if the trigger visualizer mesh should be visible in-game.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		_update_visuals()

## Defines physical dimensions of color grading volume and visualizer.
@export var volume_size: Vector3 = Vector3(4.0, 4.0, 4.0):
	set(value):
		volume_size = value
		_update_visuals()

## Sets visual color of volume debug wireframe rendered in editor.
@export var volume_color: Color = Color(0.2, 0.6, 1.0, 0.4):
	set(value):
		volume_color = value
		_update_visuals()

## Text displayed above volume wireframe in editor for identification.
@export var volume_text: String = "COLOR GRADING":
	set(value):
		volume_text = value
		_update_visuals()

## Custom color grading shader resource containing rendering passes.
@export var grading_shader: Shader:
	set(value):
		grading_shader = value
		_initialize_material()

## Predefined color grading settings to quickly apply visual moods.
@export var preset: Preset = Preset.CUSTOM:
	set(value):
		preset = value
		_apply_preset()

## Overall lightness or darkness adjustment of post-processed view.
@export var brightness: float = 1.0:
	set(value):
		brightness = value
		_update_shader_params()

## Contrast separation between dark and light tones on screen.
@export var contrast: float = 1.0:
	set(value):
		contrast = value
		_update_shader_params()

## Intensity and vibrancy of screen color channels.
@export var saturation: float = 1.0:
	set(value):
		saturation = value
		_update_shader_params()

## White balance color temperature shift between cool blue and warm orange.
@export_range(-1.0, 1.0) var temperature: float = 0.0:
	set(value):
		temperature = value
		_update_shader_params()

## White balance color tint shift between green and magenta.
@export_range(-1.0, 1.0) var tint: float = 0.0:
	set(value):
		tint = value
		_update_shader_params()

## Tints and adjusts the darkest shadow tones of screen image.
@export var lift_color: Color = Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		lift_color = value
		_update_shader_params()

## Tints and adjusts the midtone tonal range of screen image.
@export var gamma_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		gamma_color = value
		_update_shader_params()

## Tints and adjusts the brightest highlight areas of screen image.
@export var gain_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		gain_color = value
		_update_shader_params()

## Look-Up Table 3D texture resource used for baked color transformations.
@export var lut_texture: Texture3D:
	set(value):
		lut_texture = value
		_update_shader_params()

## Blend intensity scalar for 3D Look-Up Table color transform.
@export_range(0.0, 1.0) var lut_intensity: float = 0.0:
	set(value):
		lut_intensity = value
		_update_shader_params()

## Chromatic aberration color fringe separation at screen boundaries.
@export_range(0.0, 0.05) var aberration_amount: float = 0.0:
	set(value):
		aberration_amount = value
		_update_shader_params()

## Darkness attenuation factor applied around viewport periphery.
@export_range(0.0, 1.0) var vignette_intensity: float = 0.0:
	set(value):
		vignette_intensity = value
		_update_shader_params()

## Film grain noise intensity factor overlaid across screen quad.
@export_range(0.0, 1.0) var grain_amount: float = 0.0:
	set(value):
		grain_amount = value
		_update_shader_params()

## Target [WorldEnvironment] instance receiving bloom overrides.
@export var target_environment: WorldEnvironment

## Target bloom intensity applied to environment upon volume entry.
@export var volume_bloom_intensity: float = 1.0

## Duration in seconds for fading grading overlay and bloom values.
@export var blend_time: float = 1.0

## Toggles color grading overlay in editor viewport for previews.
@export var preview_in_editor: bool = false:
	set(value):
		preview_in_editor = value
		_update_editor_preview()

## Dedicated [CanvasLayer] drawing post-process pass over viewport.
var _canvas_layer: CanvasLayer = null

## Viewport copy node capturing screen texture before grading pass.
var _back_buffer: BackBufferCopy = null

## Fullscreen color rectangle applying color grading shader material.
var _color_rect: ColorRect = null

## Active [Tween] interpolating grading rect opacity during entry/exit.
var _blend_tween: Tween = null

## Active [Tween] interpolating environment glow bloom intensity.
var _bloom_tween: Tween = null

## Instantiated [ShaderMaterial] holding grading logic and uniforms.
var _material: ShaderMaterial = null

## Cached original glow intensity of target [WorldEnvironment].
var _original_glow_intensity: float = 0.0

## Cached original glow bloom value of target [WorldEnvironment].
var _original_glow_bloom: float = 0.0

## Cached collision shape child node defining volume trigger area.
var _collision_shape: CollisionShape3D = null


## Configures player collision masks, caches baseline bloom, and sets up UI.
func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if Engine.is_editor_hint():
		_update_visuals()
	else:
		collision_layer = CollisionLayers.MASK_NONE
		collision_mask = CollisionLayers.MASK_PLAYER
		add_to_group(&"color_grading_volumes")

		if not show_in_game:
			for child: Node in get_children():
				if child.get_class() == "EditorTriggerVisualizer":
					child.queue_free()

		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

		if is_instance_valid(target_environment) and target_environment.environment != null:
			_original_glow_intensity = target_environment.environment.glow_intensity
			_original_glow_bloom = target_environment.environment.glow_bloom
			target_environment.environment.glow_enabled = true

	print("ColorGradingVolume3D: Initializing post-processing volume: ", name)
	_setup_screen_ui()


## Rebuilds collision shapes and visual debug meshes in editor viewport.
func _update_visuals() -> void:
	if not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if is_instance_valid(_collision_shape):
		if shape_type == ShapeType.BOX:
			if not _collision_shape.shape is BoxShape3D:
				_collision_shape.shape = BoxShape3D.new()
			if Engine.is_editor_hint() and not _collision_shape.shape.resource_local_to_scene:
				_collision_shape.shape = _collision_shape.shape.duplicate()
				_collision_shape.shape.resource_local_to_scene = true
			(_collision_shape.shape as BoxShape3D).size = volume_size
		elif shape_type == ShapeType.SPHERE:
			if not _collision_shape.shape is SphereShape3D:
				_collision_shape.shape = SphereShape3D.new()
			if Engine.is_editor_hint() and not _collision_shape.shape.resource_local_to_scene:
				_collision_shape.shape = _collision_shape.shape.duplicate()
				_collision_shape.shape.resource_local_to_scene = true
			(_collision_shape.shape as SphereShape3D).radius = volume_size.x * 0.5

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		if (
			Engine.is_editor_hint()
			and visual.mesh != null
			and not visual.mesh.resource_local_to_scene
		):
			visual.mesh = visual.mesh.duplicate(true)
			visual.mesh.resource_local_to_scene = true
		@warning_ignore("int_as_enum_without_cast")
		visual.shape_type = shape_type as int
		visual.show_in_game = show_in_game
		visual.trigger_size = volume_size
		visual.trigger_color = volume_color
		visual.trigger_text = volume_text


## Retrieves the visualizer child node responsible for wireframe display.
func _get_visualizer() -> EditorTriggerVisualizer:
	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			return child as EditorTriggerVisualizer
	return null


## Creates dedicated CanvasLayer, BackBufferCopy, and ColorRect components.
func _setup_screen_ui() -> void:
	if not is_inside_tree():
		return

	print("ColorGradingVolume3D: Setting up screen quad hierarchy for: ", name)
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "ColorGradingCanvasLayer"
	_canvas_layer.layer = 10
	_canvas_layer.visible = false
	add_child(_canvas_layer)

	_back_buffer = BackBufferCopy.new()
	_back_buffer.name = "VolumeBackBuffer"
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_canvas_layer.add_child(_back_buffer)

	_color_rect = ColorRect.new()
	_color_rect.name = "GradingColorRect"
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.modulate.a = 0.0
	_color_rect.hide()
	_canvas_layer.add_child(_color_rect)

	_initialize_material()


## Instantiates [ShaderMaterial] and loads grading shader resource.
func _initialize_material() -> void:
	if not is_inside_tree() or not is_instance_valid(_color_rect) or grading_shader == null:
		return

	if _material == null:
		_material = ShaderMaterial.new()
		_color_rect.material = _material

	_material.shader = grading_shader
	_update_shader_params()
	_update_editor_preview()


## Synchronizes inspector parameters to active [ShaderMaterial] uniforms.
func _update_shader_params() -> void:
	if not is_instance_valid(_material):
		return

	_material.set_shader_parameter(&"brightness", brightness)
	_material.set_shader_parameter(&"contrast", contrast)
	_material.set_shader_parameter(&"saturation", saturation)
	_material.set_shader_parameter(&"temperature", temperature)
	_material.set_shader_parameter(&"tint", tint)

	_material.set_shader_parameter(&"lift_color", Vector3(lift_color.r, lift_color.g, lift_color.b))
	_material.set_shader_parameter(
		&"gamma_color", Vector3(gamma_color.r, gamma_color.g, gamma_color.b)
	)
	_material.set_shader_parameter(&"gain_color", Vector3(gain_color.r, gain_color.g, gain_color.b))

	if lut_texture != null:
		_material.set_shader_parameter(&"lut_texture", lut_texture)
	_material.set_shader_parameter(&"lut_intensity", lut_intensity)

	_material.set_shader_parameter(&"aberration_amount", aberration_amount)
	_material.set_shader_parameter(&"vignette_intensity", vignette_intensity)
	_material.set_shader_parameter(&"grain_amount", grain_amount)


## Applies calibrated color values corresponding to selected [param preset].
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


## Toggles canvas layer visibility inside editor viewport for previews.
func _update_editor_preview() -> void:
	if (
		not is_inside_tree()
		or not is_instance_valid(_color_rect)
		or not is_instance_valid(_canvas_layer)
	):
		return

	if Engine.is_editor_hint():
		if preview_in_editor and grading_shader != null:
			print("ColorGradingVolume3D: Enabling editor preview on: ", name)
			_canvas_layer.show()
			_color_rect.show()
			_color_rect.modulate.a = 1.0
		else:
			print("ColorGradingVolume3D: Disabling editor preview on: ", name)
			_color_rect.modulate.a = 0.0
			_color_rect.hide()
			_canvas_layer.hide()


## Initiates smooth fade-in transitions when player enters volume.
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		print("ColorGradingVolume3D: Player entered volume: ", name)
		_fade_effect(1.0)
		_fade_bloom(volume_bloom_intensity)


## Initiates smooth fade-out transitions when player exits volume.
func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		print("ColorGradingVolume3D: Player exited volume: ", name)
		_fade_effect(0.0)
		_fade_bloom(_original_glow_bloom)


## Tweens opacity of screen grading quad and gates canvas visibility.
func _fade_effect(target_alpha: float) -> void:
	if not is_instance_valid(_color_rect) or not is_instance_valid(_canvas_layer):
		return

	print("ColorGradingVolume3D: Fading shader alpha to: ", target_alpha)
	if target_alpha > 0.0:
		_canvas_layer.show()
		_color_rect.show()

	if _blend_tween != null and _blend_tween.is_valid():
		_blend_tween.kill()

	_blend_tween = create_tween()
	_blend_tween.tween_property(_color_rect, "modulate:a", target_alpha, blend_time).set_trans(
		Tween.TRANS_SINE
	)

	if target_alpha <= 0.0:
		_blend_tween.tween_callback(_on_fade_out_finished)


## Callback hiding canvas layer once fade-out tween concludes.
func _on_fade_out_finished() -> void:
	if is_instance_valid(_color_rect):
		_color_rect.hide()
	if is_instance_valid(_canvas_layer):
		_canvas_layer.hide()


## Tweens target [WorldEnvironment] glow bloom intensity.
func _fade_bloom(target_intensity: float) -> void:
	if not is_instance_valid(target_environment) or target_environment.environment == null:
		return

	print("ColorGradingVolume3D: Fading environment bloom to: ", target_intensity)
	if _bloom_tween != null and _bloom_tween.is_valid():
		_bloom_tween.kill()

	_bloom_tween = create_tween()
	(
		_bloom_tween
		. tween_property(target_environment.environment, "glow_bloom", target_intensity, blend_time)
		. set_trans(Tween.TRANS_SINE)
	)


## Resets all color grading overlays and restores default environment glow.
func reset_to_default() -> void:
	print("ColorGradingVolume3D: Resetting volume overlay to defaults.")
	if _blend_tween != null and _blend_tween.is_valid():
		_blend_tween.kill()
	if _bloom_tween != null and _bloom_tween.is_valid():
		_bloom_tween.kill()

	if is_instance_valid(_color_rect):
		_color_rect.modulate.a = 0.0
		_color_rect.hide()

	if is_instance_valid(_canvas_layer):
		_canvas_layer.hide()

	if is_instance_valid(target_environment) and target_environment.environment != null:
		target_environment.environment.glow_bloom = _original_glow_bloom
