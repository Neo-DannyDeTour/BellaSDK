## Visual manager rendering chapter titles and cinematic overlays via cached shaders.
class_name ChapterDisplay
extends MarginContainer

## Glitch screen-space distortion [Shader] resource.
const SHADER_GLITCH: Shader = preload("res://vfx/chapter_text_glitch.gdshader")

## Reveal wipe [Shader] resource.
const SHADER_REVEAL: Shader = preload("res://vfx/chapter_text_reveal.gdshader")

## Chromatic aberration [Shader] resource.
const SHADER_CHROMATIC: Shader = preload("res://vfx/chapter_text_chromatic.gdshader")

## Dissolve mask [Shader] resource.
const SHADER_DISSOLVE: Shader = preload("res://vfx/chapter_text_dissolve.gdshader")

## Liquid distortion [Shader] resource.
const SHADER_LIQUID: Shader = preload("res://vfx/chapter_text_liquid.gdshader")

## Holographic scanline [Shader] resource.
const SHADER_HOLOGRAM: Shader = preload("res://vfx/chapter_text_hologram.gdshader")

## Neon edge radiance [Shader] resource.
const SHADER_NEON: Shader = preload("res://vfx/chapter_text_neon.gdshader")

## Shatter fragment [Shader] resource.
const SHADER_SHATTER: Shader = preload("res://vfx/chapter_text_shatter.gdshader")

## Depth of field blur [Shader] resource.
const SHADER_BLUR: Shader = preload("res://vfx/chapter_text_blur.gdshader")

## Doom melt melt-down [Shader] resource.
const SHADER_DOOM_MELT: Shader = preload("res://vfx/chapter_text_doom_melt.gdshader")

## Retro VHS tape tracking [Shader] resource.
const SHADER_VHS: Shader = preload("res://vfx/chapter_text_vhs.gdshader")

## Light sweep specular reflection [Shader] resource.
const SHADER_LIGHT_SWEEP: Shader = preload("res://vfx/chapter_text_light_sweep.gdshader")

## Animation styles routed directly to post-processing shader pipelines.
const SHADER_ANIM_STYLES: Array[Events.ChapterAnimStyle] = [
	Events.ChapterAnimStyle.GLITCH,
	Events.ChapterAnimStyle.REVEAL,
	Events.ChapterAnimStyle.CHROMATIC,
	Events.ChapterAnimStyle.DISSOLVE,
	Events.ChapterAnimStyle.LIQUID,
	Events.ChapterAnimStyle.HOLOGRAM,
	Events.ChapterAnimStyle.NEON,
	Events.ChapterAnimStyle.SHATTER,
	Events.ChapterAnimStyle.DOOM_MELT,
	Events.ChapterAnimStyle.VHS,
	Events.ChapterAnimStyle.LIGHT_SWEEP,
]

## [SubViewportContainer] applying post-processing shaders to the text.
@onready var effect_container: SubViewportContainer = $EffectContainer

## Internal [SubViewport] rendering the text overlay texture.
@onready var _sub_viewport: SubViewport = $EffectContainer/ChapterLabelSubViewport

## [RichTextLabel] responsible for rendering chapter text and BBCode.
@onready var chapter_label: RichTextLabel = $EffectContainer/ChapterLabelSubViewport/ChapterLabel

## Active [Tween] orchestrating chapter title text animation sequences.
var _chapter_tween: Tween

## Dictionary caching pre-allocated [ShaderMaterial] instances by animation style.
var _material_cache: Dictionary[Events.ChapterAnimStyle, ShaderMaterial] = {}

## Pre-allocated [ShaderMaterial] for the bokeh text blur transition.
var _blur_material: ShaderMaterial


## Initializes UI anchors, material cache, and connects [Events] signals.
func _ready() -> void:
	print("ChapterDisplay: _ready() called. Initializing shader material cache.")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	chapter_label.bbcode_enabled = true
	chapter_label.fit_content = false
	chapter_label.clip_contents = false
	chapter_label.modulate.a = 0.0
	chapter_label.visible = false
	chapter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_init_material_cache()

	if is_instance_valid(effect_container):
		effect_container.stretch = false
		effect_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		effect_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		effect_container.material = null
		effect_container.visible = false

	if is_instance_valid(_sub_viewport):
		_sub_viewport.disable_3d = true
		_sub_viewport.transparent_bg = true
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	if not Events.chapter_triggered.is_connected(_on_chapter_triggered):
		Events.chapter_triggered.connect(_on_chapter_triggered)

	if Events.has_signal(&"wake_up_text_requested"):
		if not Events.wake_up_text_requested.is_connected(_on_wake_up_text_requested):
			Events.wake_up_text_requested.connect(_on_wake_up_text_requested)

	resized.connect(_on_resized)
	_on_resized()


## Pre-allocates and caches all [ShaderMaterial] instances.
func _init_material_cache() -> void:
	print("ChapterDisplay: Building pre-allocated ShaderMaterial cache.")
	_material_cache[Events.ChapterAnimStyle.GLITCH] = _create_material(SHADER_GLITCH)
	_material_cache[Events.ChapterAnimStyle.REVEAL] = _create_material(SHADER_REVEAL)
	_material_cache[Events.ChapterAnimStyle.CHROMATIC] = _create_material(SHADER_CHROMATIC)
	_material_cache[Events.ChapterAnimStyle.DISSOLVE] = _create_material(SHADER_DISSOLVE)
	_material_cache[Events.ChapterAnimStyle.LIQUID] = _create_material(SHADER_LIQUID)
	_material_cache[Events.ChapterAnimStyle.HOLOGRAM] = _create_material(SHADER_HOLOGRAM)
	_material_cache[Events.ChapterAnimStyle.NEON] = _create_material(SHADER_NEON)
	_material_cache[Events.ChapterAnimStyle.SHATTER] = _create_material(SHADER_SHATTER)
	_material_cache[Events.ChapterAnimStyle.DOOM_MELT] = _create_material(SHADER_DOOM_MELT)
	_material_cache[Events.ChapterAnimStyle.VHS] = _create_material(SHADER_VHS)
	_material_cache[Events.ChapterAnimStyle.LIGHT_SWEEP] = _create_material(SHADER_LIGHT_SWEEP)

	_blur_material = _create_material(SHADER_BLUR)


## Helper creating a [ShaderMaterial] with a bound [Shader].
func _create_material(shader_res: Shader) -> ShaderMaterial:
	print("ChapterDisplay: Allocating material for ", shader_res.resource_path)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader_res
	return mat


## Recomputes structural layout constraints when window size changes.
func _on_resized() -> void:
	print("ChapterDisplay: _on_resized() called. Updating layout bounds.")
	if not is_instance_valid(chapter_label) or not is_inside_tree():
		return

	var screen_size: Vector2 = get_viewport_rect().size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		return

	if is_instance_valid(effect_container) and is_instance_valid(_sub_viewport):
		_sub_viewport.size = Vector2i(screen_size)
		effect_container.custom_minimum_size = screen_size

	var vertical_offset: float = 60.0
	var label_height: float = 120.0
	var centered_y: float = (screen_size.y * 0.5) - (label_height * 0.5) + vertical_offset

	chapter_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	chapter_label.offset_left = 0.0
	chapter_label.offset_right = 0.0
	chapter_label.offset_top = centered_y
	chapter_label.offset_bottom = centered_y + label_height
	chapter_label.pivot_offset = Vector2(screen_size.x * 0.5, label_height * 0.5)


## Handles chapter sequence triggers by delegating to animation effects.
func _on_chapter_triggered(
	chapter_name: String,
	anim_style: Events.ChapterAnimStyle,
	display_duration: float,
	text_color: Color
) -> void:
	print("ChapterDisplay: Triggered '", chapter_name, "' with style ID ", anim_style)

	visible = true
	_on_resized()

	if is_instance_valid(_chapter_tween) and _chapter_tween.is_valid():
		_chapter_tween.kill()

	if is_instance_valid(_sub_viewport):
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if is_instance_valid(effect_container):
		effect_container.modulate = Color.WHITE
		effect_container.material = null
		effect_container.visible = true

	chapter_label.add_theme_color_override("default_color", text_color)
	chapter_label.visible = true
	chapter_label.material = null

	_chapter_tween = create_tween()

	if anim_style in SHADER_ANIM_STYLES:
		_play_cached_shader(chapter_name, display_duration, anim_style)
	else:
		match anim_style:
			Events.ChapterAnimStyle.SIMPLE:
				_play_simple(chapter_name, display_duration, 1.0, 1.0)
			Events.ChapterAnimStyle.WAVE:
				_play_wave(chapter_name, display_duration)
			Events.ChapterAnimStyle.GLOW:
				_play_glow(chapter_name, display_duration)
			Events.ChapterAnimStyle.TYPEWRITER:
				_play_typewriter(chapter_name, display_duration)
			Events.ChapterAnimStyle.SLAM:
				_play_slam(chapter_name, display_duration)
			Events.ChapterAnimStyle.SPRING:
				_play_spring(chapter_name, display_duration)
			Events.ChapterAnimStyle.DRIFT:
				_play_drift(chapter_name, display_duration)
			Events.ChapterAnimStyle.HEARTBEAT:
				_play_heartbeat(chapter_name, display_duration)
			Events.ChapterAnimStyle.BLUR:
				_play_blur(chapter_name, display_duration)
			_:
				print("ChapterDisplay: Unknown style ID, triggering fallback.")
				_play_simple(chapter_name, display_duration, 1.0, 1.0)

	_chapter_tween.finished.connect(_disable_viewport)


## Handles cinematic text requests from wake-up triggers with custom timings.
func _on_wake_up_text_requested(text: String, fade_in: float, hold: float, fade_out: float) -> void:
	print("ChapterDisplay: Playing wake-up text sequence: '", text, "'")
	visible = true
	_on_resized()

	if is_instance_valid(_chapter_tween) and _chapter_tween.is_valid():
		_chapter_tween.kill()

	if is_instance_valid(_sub_viewport):
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if is_instance_valid(effect_container):
		effect_container.modulate = Color.WHITE
		effect_container.material = null
		effect_container.visible = true

	chapter_label.add_theme_color_override("default_color", Color.WHITE)
	chapter_label.visible = true
	chapter_label.material = null

	_chapter_tween = create_tween()
	_play_simple(text, hold, fade_in, fade_out)
	_chapter_tween.finished.connect(_disable_viewport)


## Shuts down the [SubViewport] rendering pipeline once animations conclude.
func _disable_viewport() -> void:
	print("ChapterDisplay: Disabling SubViewport render target.")
	if is_instance_valid(chapter_label):
		chapter_label.hide()
	if is_instance_valid(effect_container):
		effect_container.hide()
		effect_container.material = null
	if is_instance_valid(_sub_viewport):
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()


## Displays text statically with configurable fade and hold durations.
func _play_simple(
	chapter_name: String, duration: float, fade_in: float = 1.0, fade_out: float = 1.0
) -> void:
	print("ChapterDisplay: Playing SIMPLE animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0

	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, fade_in)
	_chapter_tween.tween_interval(duration)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, fade_out)


## Applies a continuous sine wave undulation effect to text characters.
func _play_wave(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing WAVE animation.")
	var wave_tag: String = "[wave amp=50.0 freq=5.0 connected=1]"
	chapter_label.text = "[center]" + wave_tag + chapter_name + "[/wave][/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0

	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
	_chapter_tween.tween_interval(duration)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)


## Iteratively reveals characters simulating terminal typewriter text.
func _play_typewriter(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing TYPEWRITER animation.")
	chapter_label.modulate.a = 1.0
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 0.0

	var time_per_char: float = 0.05
	var total_time: float = float(chapter_name.length()) * time_per_char

	_chapter_tween.tween_property(chapter_label, "visible_ratio", 1.0, total_time)
	_chapter_tween.tween_interval(duration)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)


## Drives a physical slam animation with anticipation and bounce.
func _play_slam(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing SLAM animation with anticipation jump.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE

	var base_pos: Vector2 = chapter_label.position
	var drop_offset: float = 120.0
	var final_drop_offset: float = 350.0
	var anticipation_height: float = 40.0

	chapter_label.position = base_pos + Vector2(0.0, -drop_offset)

	var intro_time: float = 0.4
	var anticipation_time: float = 0.15
	var outro_time: float = 0.25
	var hold_time: float = maxf(0.0, duration - intro_time - anticipation_time - outro_time)

	_chapter_tween.set_parallel(true)
	(
		_chapter_tween
		. tween_property(chapter_label, "position", base_pos, intro_time)
		. set_trans(Tween.TRANS_BOUNCE)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_chapter_tween
		. tween_property(chapter_label, "modulate:a", 1.0, intro_time)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	_chapter_tween.set_parallel(false)
	_chapter_tween.tween_interval(hold_time)

	var peak_pos: Vector2 = base_pos + Vector2(0.0, -anticipation_height)
	(
		_chapter_tween
		. tween_property(chapter_label, "position", peak_pos, anticipation_time)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	_chapter_tween.set_parallel(true)
	var end_pos: Vector2 = base_pos + Vector2(0.0, final_drop_offset)
	(
		_chapter_tween
		. tween_property(chapter_label, "position", end_pos, outro_time)
		. set_trans(Tween.TRANS_EXPO)
		. set_ease(Tween.EASE_IN)
	)
	(
		_chapter_tween
		. tween_property(chapter_label, "modulate:a", 0.0, outro_time)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)

	_chapter_tween.set_parallel(false)
	_chapter_tween.tween_callback(func() -> void: chapter_label.position = base_pos)


## Expands text scale aggressively outward using spring easing.
func _play_spring(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing SPRING animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 1.0
	chapter_label.scale = Vector2.ZERO

	var intro_time: float = 0.8
	var outro_time: float = 0.5
	var hold_time: float = maxf(0.0, duration - intro_time - outro_time)

	(
		_chapter_tween
		. tween_property(chapter_label, "scale", Vector2.ONE, intro_time)
		. set_trans(Tween.TRANS_SPRING)
		. set_ease(Tween.EASE_OUT)
	)

	_chapter_tween.tween_interval(hold_time)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, outro_time)
	_chapter_tween.tween_callback(func() -> void: chapter_label.scale = Vector2.ONE)


## Drifts text smoothly across the screen diagonally.
func _play_drift(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing DRIFT animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE

	var base_pos: Vector2 = chapter_label.position
	var start_pos: Vector2 = base_pos + Vector2(0.0, 50.0)
	var end_pos: Vector2 = base_pos - Vector2(0.0, 50.0)

	chapter_label.position = start_pos

	_chapter_tween.set_parallel(true)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
	(
		_chapter_tween
		. tween_property(chapter_label, "position", end_pos, duration)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	_chapter_tween.chain().tween_property(chapter_label, "modulate:a", 0.0, 1.0)
	_chapter_tween.chain().tween_callback(func() -> void: chapter_label.position = base_pos)


## Applies a pre-cached [ShaderMaterial] and animates its progress uniform.
func _play_cached_shader(
	chapter_name: String, duration: float, anim_style: Events.ChapterAnimStyle
) -> void:
	print("ChapterDisplay: Playing cached shader effect for style ", anim_style)
	var mat: ShaderMaterial = _material_cache.get(anim_style)
	if not is_instance_valid(mat):
		_play_simple(chapter_name, duration, 1.0, 1.0)
		return

	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 1.0

	effect_container.scale = Vector2.ONE
	effect_container.modulate.a = 1.0
	effect_container.visible = true

	mat.set_shader_parameter("progress", 0.0)
	effect_container.material = mat

	_chapter_tween.tween_method(
		func(val: float) -> void: mat.set_shader_parameter("progress", val), 0.0, 1.0, duration
	)


## Fades out and blurs text using the cached depth-of-field [ShaderMaterial].
func _play_blur(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing BLUR animation with cached material.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.scale = Vector2.ONE
	chapter_label.modulate.a = 1.0

	var mat: ShaderMaterial = _blur_material
	chapter_label.material = mat

	var max_blur: float = 4.0
	var transition_time: float = duration * 0.25
	var hold_time: float = duration * 0.5

	mat.set_shader_parameter("blur_amount", max_blur)
	mat.set_shader_parameter("fade_amount", 0.0)

	_chapter_tween.tween_property(mat, "shader_parameter/fade_amount", 1.0, transition_time * 0.4)
	(
		_chapter_tween
		. parallel()
		. tween_property(mat, "shader_parameter/blur_amount", 0.0, transition_time)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)

	_chapter_tween.tween_interval(hold_time)

	(
		_chapter_tween
		. tween_property(mat, "shader_parameter/blur_amount", max_blur, transition_time)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		_chapter_tween
		. parallel()
		. tween_property(mat, "shader_parameter/fade_amount", 0.0, transition_time * 0.5)
		. set_delay(transition_time * 0.5)
	)


## Manipulates text stroke borders to create a pulsating neon light halo.
func _play_glow(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing GLOW animation via outline tween.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE
	chapter_label.material = null

	var text_color: Color = chapter_label.get_theme_color("default_color")
	chapter_label.add_theme_constant_override("outline_size", 16)

	var fade_time: float = duration * 0.15
	var active_time: float = duration - (fade_time * 2.0)
	var pulse_duration: float = 0.6
	var pulse_count: int = int(active_time / pulse_duration)

	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, fade_time)

	for i: int in range(pulse_count):
		var start_alpha: float = 0.1 if i % 2 == 0 else 0.6
		var end_alpha: float = 0.6 if i % 2 == 0 else 0.1

		(
			_chapter_tween
			. tween_method(
				func(alpha: float) -> void:
					var pulse_color: Color = text_color
					pulse_color.a = alpha
					chapter_label.add_theme_color_override("font_outline_color", pulse_color),
				start_alpha,
				end_alpha,
				pulse_duration
			)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, fade_time)
	_chapter_tween.tween_callback(
		func() -> void:
			chapter_label.remove_theme_constant_override("outline_size")
			chapter_label.remove_theme_color_override("font_outline_color")
	)


## Animates text scale repetitively mimicking a heartbeat pulse.
func _play_heartbeat(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing HEARTBEAT animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE

	var fade_time: float = 0.5
	var pulse_time: float = 0.35
	var active_time: float = maxf(0.0, duration - (fade_time * 2.0))
	var loops: int = int(active_time / (pulse_time * 2.0))

	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, fade_time)

	for i: int in range(loops):
		(
			_chapter_tween
			. tween_property(chapter_label, "scale", Vector2(1.08, 1.08), pulse_time)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			_chapter_tween
			. tween_property(chapter_label, "scale", Vector2.ONE, pulse_time)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, fade_time)
	_chapter_tween.tween_callback(func() -> void: chapter_label.scale = Vector2.ONE)
