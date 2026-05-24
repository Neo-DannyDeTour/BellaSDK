extends Button

# --- BUTTON CONFIGURATION ---
@export var hover_scale := Vector2(1.08, 1.08)
@export var response_speed := 12.0

# --- PRESS CONFIGURATION ---
@export var press_scale := Vector2(0.94, 0.94)
@export var press_depth := 8.0
@export var press_speed := 20.0

# --- BACKGROUND CONFIGURATION ---
@export var background_images: Array[Texture2D] = []

# --- SHADOW AI CONFIGURATION ---
@export var walk_speed := 0.2
@export var hunt_speed := 6.0

# --- GLITCH CONFIGURATION ---
@export var glitch_text := ""
@export var glitch_duration := 0.666
@export var min_glitch_time := 15.0
@export var max_glitch_time := 20.0

# --- PULSE CONFIGURATION ---
@export var pulse_speed := 6.0
@export var pulse_intensity := 0.1

# --- 3D PARALLAX CONFIGURATION ---
@export var max_rotation_degrees := 8.0
@export var parallax_intensity := 3.0

@export var flashlight_texture: Texture2D

# --- GLOBAL AI CONFIGURATION ---
static var active_horror_buttons: int = 0
# --- INTERNAL REFERENCES ---
var text_label: Label
var label_material: ShaderMaterial
var bg_rect: ColorRect
var bg_material: ShaderMaterial
var border_rect: ColorRect
var border_material: ShaderMaterial
var current_hover_intensity := 0.0
var is_mouse_over := false
var is_clicking := false
var original_scale: Vector2

# --- MULTIPLE AI VARIABLES ---
var shadows_x: Array[float] = [0.0, 0.0]
var target_shadows_x: Array[float] = [0.0, 0.0]
var pace_timers: Array[float] = [0.0, 0.0]
var walk_speeds: Array[float] = [0.0, 0.0]
var shine_tween: Tween
var current_tilt := Vector2.ZERO

# --- GLITCH VARIABLES ---
var original_button_text := ""
var glitch_timer := 0.0
var is_glitching := false
var can_glitch := false


func _ready() -> void:
	active_horror_buttons += 1
	flat = true

	var empty_style := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty_style)
	add_theme_stylebox_override("hover", empty_style)
	add_theme_stylebox_override("pressed", empty_style)
	add_theme_stylebox_override("disabled", empty_style)
	add_theme_stylebox_override("focus", empty_style)

	# Use Godot 4's global randomization
	randomize()
	pivot_offset = size / 2.0
	original_scale = scale

	button_down.connect(func() -> void: is_clicking = true)
	button_up.connect(func() -> void: is_clicking = false)

	glitch_timer = randf_range(min_glitch_time, max_glitch_time)

	for child in get_children():
		# FIX 1: Prevent children from stealing the mouse events from the Button
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if child is Label:
			text_label = child
		elif child is ColorRect and child.name == "Border":
			border_rect = child
		elif child is ColorRect and child.name == "Background":
			bg_rect = child

	# --- SETUP SHADER BACKGROUND & RANDOM TEXTURE ---
	if bg_rect and bg_rect.material is ShaderMaterial:
		bg_material = bg_rect.material.duplicate()
		bg_rect.material = bg_material
		bg_material.set_shader_parameter("hover_intensity", 0.0)
		bg_material.set_shader_parameter("rect_size", size)
		bg_material.set_shader_parameter(
			"blood_offset", Vector2(randf_range(0.0, 100.0), randf_range(0.0, 100.0))
		)
		bg_material.set_shader_parameter("custom_light_texture", flashlight_texture)

		if background_images.size() > 0:
			var random_index: int = randi() % background_images.size()
			bg_material.set_shader_parameter("blood_texture", background_images[random_index])
	else:
		printerr(
			"Button script could not find a ColorRect named 'Background' with a ShaderMaterial."
		)

	if border_rect and border_rect.material is ShaderMaterial:
		border_material = border_rect.material.duplicate()
		border_rect.material = border_material
		border_material.set_shader_parameter("hover_intensity", 0.0)
		border_material.set_shader_parameter("rect_size", size)

	if text_label != null:
		text_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		text_label.size = size
		text_label.position = Vector2.ZERO
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if text != "" and text_label != null:
		text_label.text = text
		original_button_text = text

		# --- FIX: Prevent Container Crush ---
		# Lock in the minimum size before clearing the text so
		# VBox/HBox containers don't crush the button to 0 pixels.
		if custom_minimum_size == Vector2.ZERO:
			custom_minimum_size = get_minimum_size()

		text = ""
	elif text_label != null:
		original_button_text = text_label.text
		if custom_minimum_size == Vector2.ZERO:
			custom_minimum_size = text_label.get_minimum_size()

	can_glitch = (glitch_text != "")

	if text_label and text_label.material is ShaderMaterial:
		label_material = text_label.material.duplicate()
		text_label.material = label_material
		label_material.set_shader_parameter("rect_size", size)

		for i in 2:
			shadows_x[i] = randf_range(-0.5, 1.5)
			target_shadows_x[i] = shadows_x[i]
			pace_timers[i] = randf_range(0.0, 2.0)
			walk_speeds[i] = randf_range(walk_speed * 0.6, walk_speed * 1.4)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)


func _on_resized() -> void:
	pivot_offset = size / 2.0

	if text_label:
		text_label.set_deferred("size", size)
		text_label.set_deferred("pivot_offset", size / 2.0)

	if bg_rect:
		bg_rect.set_deferred("size", size)

	if border_rect:
		border_rect.set_deferred("size", size)

	if bg_material:
		bg_material.set_shader_parameter("rect_size", size)
	if border_material:
		border_material.set_shader_parameter("rect_size", size)
	if label_material:
		label_material.set_shader_parameter("rect_size", size)


func _on_mouse_entered() -> void:
	is_mouse_over = true

	if bg_material:
		current_hover_intensity = 1.0
		if shine_tween and shine_tween.is_valid():
			shine_tween.kill()
		shine_tween = create_tween()
		bg_material.set_shader_parameter("sweep_progress", -0.3)
		(
			shine_tween
			. tween_method(
				func(val: float) -> void: bg_material.set_shader_parameter("sweep_progress", val),
				-0.3,
				1.8,
				0.6
			)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)


func _on_mouse_exited() -> void:
	is_mouse_over = false
	is_clicking = false

	for i in 2:
		pace_timers[i] = 0.0


func _process(delta: float) -> void:
	# Halt process until Godot's container system actually gives the button a size.
	# Prevents math from dividing by 0 and breaking the vectors permanently.
	if size.x <= 0.1 or size.y <= 0.1:
		return

	var target_rotation := 0.0

	var mouse_pos := get_local_mouse_position()
	var center_x := size.x / 2.0
	var center_y := size.y / 2.0

	if is_mouse_over:
		current_hover_intensity = move_toward(current_hover_intensity, 1.0, 3.0 * delta)

		var normalized_x := clampf((mouse_pos.x - center_x) / center_x, -1.0, 1.0)
		var normalized_y := clampf((mouse_pos.y - center_y) / center_y, -1.0, 1.0)

		target_rotation = deg_to_rad(max_rotation_degrees * normalized_x)

		if is_clicking:
			scale = scale.lerp(press_scale, press_speed * delta)

			if text_label:
				var target_text_pos := Vector2(-normalized_x, -normalized_y) * parallax_intensity
				target_text_pos.y += press_depth
				text_label.position = text_label.position.lerp(target_text_pos, press_speed * delta)
				text_label.scale = text_label.scale.lerp(Vector2(1.0, 1.0), press_speed * delta)
		else:
			var pitch_scale_modifier: float = 1.0 - (abs(normalized_y) * 0.04)
			var final_target_scale := hover_scale * Vector2(1.0, pitch_scale_modifier)
			scale = scale.lerp(final_target_scale, response_speed * delta)

			if text_label:
				var target_text_pos := Vector2(-normalized_x, -normalized_y) * parallax_intensity
				text_label.position = text_label.position.lerp(
					target_text_pos, response_speed * delta
				)

				var time_sec := Time.get_ticks_msec() / 1000.0
				var pulse := pow(sin(time_sec * pulse_speed), 4.0)
				var current_text_scale := 1.0 + (pulse * pulse_intensity)
				text_label.scale = Vector2(current_text_scale, current_text_scale)

	else:
		current_hover_intensity = move_toward(current_hover_intensity, 0.0, 3.0 * delta)
		scale = scale.lerp(original_scale, response_speed * delta)
		target_rotation = 0.0

		if text_label:
			text_label.position = text_label.position.lerp(Vector2.ZERO, response_speed * delta)
			text_label.scale = text_label.scale.lerp(Vector2(1.0, 1.0), response_speed * delta)

	rotation = lerpf(rotation, target_rotation, response_speed * delta)

	var tilt_target := Vector2.ZERO

	if is_mouse_over:
		var normalized_x := clampf((mouse_pos.x - center_x) / center_x, -1.0, 1.0)
		var normalized_y := clampf((mouse_pos.y - center_y) / center_y, -1.0, 1.0)
		tilt_target = Vector2(normalized_x, normalized_y)

	current_tilt = current_tilt.lerp(tilt_target, response_speed * delta)

	if bg_rect and bg_material:
		bg_material.set_shader_parameter("hover_intensity", current_hover_intensity)
		bg_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)

		var local_mouse_pos := bg_rect.get_local_mouse_position()
		var mouse_uv := Vector2(
			local_mouse_pos.x / bg_rect.size.x, local_mouse_pos.y / bg_rect.size.y
		)
		bg_material.set_shader_parameter("mouse_pos_uv", mouse_uv)

	if border_material:
		border_material.set_shader_parameter("hover_intensity", current_hover_intensity)
		border_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)

	if label_material:
		label_material.set_shader_parameter("hover_intensity", current_hover_intensity)
		label_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)

		for i in 2:
			if is_mouse_over:
				var uv_target := clampf(mouse_pos.x / size.x, -0.2, 1.2)
				shadows_x[i] = move_toward(shadows_x[i], uv_target, hunt_speed * delta)
			else:
				pace_timers[i] -= delta
				if pace_timers[i] <= 0:
					pace_timers[i] = randf_range(1.0, 3.0)
					target_shadows_x[i] = randf_range(-0.2, 1.2)
					walk_speeds[i] = randf_range(walk_speed * 0.5, walk_speed * 1.5)
				shadows_x[i] = move_toward(
					shadows_x[i], target_shadows_x[i], walk_speeds[i] * delta
				)

			label_material.set_shader_parameter("shadow_" + str(i + 1) + "_x", shadows_x[i])

	if can_glitch and text_label:
		glitch_timer -= delta
		if glitch_timer <= 0.0:
			if is_glitching:
				is_glitching = false
				text_label.text = original_button_text
				glitch_timer = randf_range(min_glitch_time, max_glitch_time)
			else:
				is_glitching = true
				text_label.text = glitch_text
				glitch_timer = glitch_duration
