class_name ChapterDisplay
extends MarginContainer

@onready var chapter_label: RichTextLabel = $ChapterLabel
var _chapter_tween: Tween


func _ready() -> void:
	print("ChapterDisplay: _ready() called. Hooking into Events bus.")
	chapter_label.modulate.a = 0.0
	chapter_label.visible = false
	
	if not Events.chapter_triggered.is_connected(_on_chapter_triggered):
		Events.chapter_triggered.connect(_on_chapter_triggered)


func _on_chapter_triggered(
	chapter_name: String,
	anim_style: int,
	display_duration: float,
	text_color: Color
) -> void:
	print(
		"ChapterDisplay: Triggered sequence for '", chapter_name,
		"' with style ID ", anim_style
	)
	
	chapter_label.add_theme_color_override("default_color", text_color)
	chapter_label.visible = true
	chapter_label.material = null
	chapter_label.pivot_offset = chapter_label.size / 2.0 
	
	if _chapter_tween and _chapter_tween.is_valid():
		_chapter_tween.kill()

	_chapter_tween = create_tween()

	match anim_style as Events.ChapterAnimStyle:
		Events.ChapterAnimStyle.SIMPLE:
			_play_simple(chapter_name, display_duration)
		Events.ChapterAnimStyle.WAVE:
			_play_wave(chapter_name, display_duration)
		Events.ChapterAnimStyle.GLOW:
			print("ChapterDisplay: Triggering GLOW shader.")
			_play_glow(chapter_name, display_duration)
		Events.ChapterAnimStyle.GLITCH:
			print("ChapterDisplay: Triggering GLITCH shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_glitch.gdshader")
			)
		Events.ChapterAnimStyle.REVEAL:
			print("ChapterDisplay: Triggering REVEAL shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_reveal.gdshader")
			)
		Events.ChapterAnimStyle.CHROMATIC:
			print("ChapterDisplay: Triggering CHROMATIC shader animation.")
			_play_shader_effect(
				chapter_name, 
				display_duration, 
				preload("res://vfx/chapter_text_chromatic.gdshader")
			)
		Events.ChapterAnimStyle.DRIFT:
			_play_drift(chapter_name, display_duration)
		Events.ChapterAnimStyle.DISSOLVE:
			print("ChapterDisplay: Triggering DISSOLVE shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_dissolve.gdshader")
			)
		Events.ChapterAnimStyle.LIQUID:
			print("ChapterDisplay: Triggering LIQUID shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_liquid.gdshader")
			)
		Events.ChapterAnimStyle.HOLOGRAM:
			print("ChapterDisplay: Triggering HOLOGRAM shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_hologram.gdshader")
			)
		Events.ChapterAnimStyle.TYPEWRITER:
			_play_typewriter(chapter_name, display_duration)
		Events.ChapterAnimStyle.SLAM:
			_play_slam(chapter_name, display_duration)
		Events.ChapterAnimStyle.SPRING:
			_play_spring(chapter_name, display_duration)
		Events.ChapterAnimStyle.NEON:
			print("ChapterDisplay: Triggering NEON shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_neon.gdshader")
			)
		Events.ChapterAnimStyle.SHATTER:
			print("ChapterDisplay: Triggering SHATTER shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_shatter.gdshader")
			)
		Events.ChapterAnimStyle.BLUR:
			print("ChapterDisplay: Triggering BLUR shader.")
			_play_blur(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_blur.gdshader")
			)
		Events.ChapterAnimStyle.DOOM_MELT:
			print("ChapterDisplay: Triggering DOOM MELT shader.")
			_play_shader_effect(
				chapter_name,
				display_duration,
				preload("res://vfx/chapter_text_doom_melt.gdshader")
			)
		_:
			print("ChapterDisplay: Unknown style ID, triggering fallback.")
			_play_simple(chapter_name, display_duration)


func _play_simple(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing SIMPLE animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	
	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
	_chapter_tween.tween_interval(duration)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)
	_chapter_tween.tween_callback(chapter_label.hide)


func _play_wave(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing WAVE animation.")
	var wave_tag: String = "[wave amp=50.0 freq=5.0 connected=1]"
	chapter_label.text = "[center]" + wave_tag + chapter_name + "[/wave][/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	
	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
	_chapter_tween.tween_interval(duration)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)
	_chapter_tween.tween_callback(chapter_label.hide)


func _play_typewriter(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing TYPEWRITER animation.")
	chapter_label.modulate.a = 1.0
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 0.0
	
	var time_per_char: float = 0.05
	var total_time: float = chapter_name.length() * time_per_char
	
	_chapter_tween.tween_property(chapter_label, "visible_ratio", 1.0, total_time)
	_chapter_tween.tween_interval(duration)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 1.0)
	_chapter_tween.tween_callback(chapter_label.hide)


func _play_slam(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing SLAM (falling) animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE
	
	var base_pos: Vector2 = chapter_label.position
	var drop_offset: float = 120.0
	chapter_label.position = base_pos + Vector2(0.0, -drop_offset)
	
	var fall_time: float = 0.4
	var hold_time: float = maxf(0.1, duration - (fall_time * 2.0))
	
	# Phase 1: Fall in from above and fade in
	_chapter_tween.set_parallel(true)
	_chapter_tween.tween_property(
		chapter_label, "position", base_pos, fall_time
	).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	
	_chapter_tween.tween_property(
		chapter_label, "modulate:a", 1.0, fall_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Phase 2: Hold position
	_chapter_tween.set_parallel(false)
	_chapter_tween.tween_interval(hold_time)
	
	# Phase 3: Fall down completely and fade out
	_chapter_tween.set_parallel(true)
	_chapter_tween.tween_property(
		chapter_label, "position", base_pos + Vector2(0.0, drop_offset), fall_time
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	_chapter_tween.tween_property(
		chapter_label, "modulate:a", 0.0, fall_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Cleanup: Hide and restore original position for future animations
	_chapter_tween.set_parallel(false)
	_chapter_tween.tween_callback(chapter_label.hide)
	_chapter_tween.tween_callback(
		func() -> void: chapter_label.position = base_pos
	)


func _play_spring(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing SPRING animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 1.0
	chapter_label.scale = Vector2.ZERO
	
	_chapter_tween.tween_property(chapter_label, "scale", Vector2.ONE, 0.8) \
		.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, 0.5) \
		.set_delay(duration - 1.3)
	_chapter_tween.tween_callback(chapter_label.hide)


func _play_drift(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing DRIFT animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE
	
	var start_pos: Vector2 = chapter_label.position + Vector2(0.0, 50.0)
	var end_pos: Vector2 = chapter_label.position - Vector2(0.0, 50.0)
	chapter_label.position = start_pos
	
	_chapter_tween.set_parallel(true)
	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, 1.0)
	_chapter_tween.tween_property(chapter_label, "position", end_pos, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	_chapter_tween.chain().tween_property(chapter_label, "modulate:a", 0.0, 1.0)
	_chapter_tween.chain().tween_callback(chapter_label.hide)


func _play_shader_effect(chapter_name: String, duration: float, shader_res: Shader) -> void:
	print("ChapterDisplay: Playing SHADER effect -> ", shader_res.resource_path)
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.scale = Vector2.ONE
	chapter_label.modulate.a = 1.0
	
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader_res
	chapter_label.material = mat
	
	mat.set_shader_parameter("progress", 0.0)
	
	_chapter_tween.tween_method(
		func(val: float) -> void: mat.set_shader_parameter("progress", val),
		0.0,
		1.0,
		duration
	)
	
	_chapter_tween.tween_callback(chapter_label.hide)


func _play_blur(chapter_name: String, duration: float, shader_res: Shader) -> void:
	print("ChapterDisplay: Playing BLUR/BOKEH animation.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.scale = Vector2.ONE
	chapter_label.modulate.a = 1.0
	
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader_res
	chapter_label.material = mat
	
	var max_blur: float = 4.0
	
	var transition_time: float = duration * 0.25
	var hold_time: float = duration * 0.5
	
	# Start fully invisible and maximally blurred
	mat.set_shader_parameter("blur_amount", max_blur)
	mat.set_shader_parameter("fade_amount", 0.0)
	
	# Phase 1: Appear as a light blob, then focus
	_chapter_tween.tween_property(mat, "shader_parameter/fade_amount", 1.0, transition_time * 0.4)
	_chapter_tween.parallel().tween_property(
		mat, "shader_parameter/blur_amount", 0.0, transition_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Phase 2: Hold sharp text
	_chapter_tween.tween_interval(hold_time)
	
	# Phase 3: Unfocus back into a light blob and fade out
	_chapter_tween.tween_property(
		mat, "shader_parameter/blur_amount", max_blur, transition_time
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_chapter_tween.parallel().tween_property(
		mat, "shader_parameter/fade_amount", 0.0, transition_time * 0.5
	).set_delay(transition_time * 0.5)
	
	_chapter_tween.chain().tween_callback(chapter_label.hide)


func _play_glow(chapter_name: String, duration: float) -> void:
	print("ChapterDisplay: Playing GLOW animation via native outline tween.")
	chapter_label.text = "[center]" + chapter_name + "[/center]"
	chapter_label.visible_ratio = 1.0
	chapter_label.modulate.a = 0.0
	chapter_label.scale = Vector2.ONE
	chapter_label.material = null
	
	# Extract the base text color you passed in during _on_chapter_triggered
	var text_color: Color = chapter_label.get_theme_color("default_color")
	
	# Hijack the outline to act as our glow halo (adjust thickness as needed)
	chapter_label.add_theme_constant_override("outline_size", 16)
	
	var fade_time: float = duration * 0.15
	var active_time: float = duration - (fade_time * 2.0)
	var pulse_duration: float = 0.6
	var pulse_count: int = int(active_time / pulse_duration)
	
	# 1. Fade the whole container in
	_chapter_tween.tween_property(chapter_label, "modulate:a", 1.0, fade_time)
	
	# 2. Pulse the outline alpha dynamically using tween_method
	for i in range(pulse_count):
		var start_alpha: float = 0.1 if i % 2 == 0 else 0.6
		var end_alpha: float = 0.6 if i % 2 == 0 else 0.1
		
		_chapter_tween.tween_method(
			func(alpha: float) -> void:
				var pulse_color: Color = text_color
				pulse_color.a = alpha
				chapter_label.add_theme_color_override("font_outline_color", pulse_color),
			start_alpha,
			end_alpha,
			pulse_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 3. Fade out
	_chapter_tween.tween_property(chapter_label, "modulate:a", 0.0, fade_time)
	_chapter_tween.tween_callback(chapter_label.hide)
	
	# Cleanup: remove the outline when the animation finishes so it doesn't leak to other styles
	_chapter_tween.tween_callback(
		func() -> void:
			chapter_label.remove_theme_constant_override("outline_size")
			chapter_label.remove_theme_color_override("font_outline_color")
	)
