@tool
extends Button

# --- GLOBAL AI CONFIGURATION ---

## Tracks the global count of active horror buttons currently instantiated in the scene.
static var active_horror_buttons: int = 0

## The text string displayed by the button, editable from the inspector and updated live in the
## editor.
@export var custom_text: String = "":
	set(value):
		custom_text = value
		if Engine.is_editor_hint():
			for child: Node in get_children():
				if child is Label:
					child.text = value

# --- BUTTON CONFIGURATION ---

## The target visual scale multiplier applied via offset transform when the player hovers over the
## button.
@export var hover_scale : Vector2 = Vector2(1.08, 1.08)

## The interpolation speed used when transitioning to hover animations.
@export var response_speed : float = 12.0

# --- PRESS CONFIGURATION ---

## The target visual scale multiplier applied when the button is actively pressed.
@export var press_scale : Vector2 = Vector2(0.94, 0.94)

## The downward pixel offset added to the text position to simulate physical button depth when
## clicked.
@export var press_depth : float = 8.0

## The interpolation speed used for button click and release animations.
@export var press_speed : float = 20.0

# --- BACKGROUND CONFIGURATION ---

## An array of optional background textures used to randomly select unique blood/horror motifs.
@export var background_images: Array[Texture2D] = []

# --- SHADOW AI CONFIGURATION ---

## The baseline tracking movement speed for ambient text shadow drifting when idle.
@export var walk_speed : float = 0.2

## The rapid tracking movement speed for text shadows chasing the user's cursor on hover.
@export var hunt_speed : float = 6.0

# --- GLITCH CONFIGURATION ---

## Alternative frightening or corrupted text displayed temporarily during an active glitch event.
@export var glitch_text : String = ""

## The duration in seconds that a specific text corruption/glitch event lasts.
@export var glitch_duration : float = 0.666

## The minimum random threshold boundary in seconds before another text glitch triggers.
@export var min_glitch_time : float = 15.0

## The maximum random threshold boundary in seconds before another text glitch triggers.
@export var max_glitch_time : float = 20.0

# --- PULSE CONFIGURATION ---

## The speed/frequency of the pulsing text animation loop when hovered.
@export var pulse_speed : float = 6.0

## The intensity variance added to the text label scale during a hover pulse.
@export var pulse_intensity : float = 0.1

# --- 3D PARALLAX CONFIGURATION ---

## The maximum visual angular rotation in degrees allowed during mouse parallax tilting.
@export var max_rotation_degrees : float = 8.0

## The scaling factor applied to the translation offset of text layers during parallax tilting.
@export var parallax_intensity : float = 3.0

## The custom texture overlay utilized to render a simulated flashlight illumination mask.
@export var flashlight_texture: Texture2D

# --- INTERNAL REFERENCES ---

## Reference to the internal Label child node displaying the button text.
var text_label: Label

## Cached duplicate shader material instance handling spatial ghosting on the text label.
var label_material: ShaderMaterial

## Reference to the internal background ColorRect element.
var bg_rect: ColorRect

## Cached duplicate shader material instance handling blood sweep and light mapping on the
## background.
var bg_material: ShaderMaterial

## Reference to the internal frame/border ColorRect node.
var border_rect: ColorRect

## Cached duplicate shader material instance handling outline hover glows.
var border_material: ShaderMaterial

## Current blending state weight (0.0 to 1.0) governing active shader hover profiles.
var current_hover_intensity : float = 0.0

## Flag monitoring whether the player's pointer is currently inside the button layout bounds.
var is_mouse_over : bool = false

## Flag monitoring whether the player is currently clicking and holding the button down.
var is_clicking : bool = false

## Cached initial visual transform scale recorded at initialization for accurate rest states.
var original_scale: Vector2

# --- MULTIPLE AI VARIABLES ---

## Current horizontal positions of the dual haunting text drop-shadow layers.
var shadows_x: Array[float] = [0.0, 0.0]

## Target destination horizontal coordinates for wandering ambient text shadow effects.
var target_shadows_x: Array[float] = [0.0, 0.0]

## Cooldown timers determining when individual shadow layers select a new roaming target.
var pace_timers: Array[float] = [0.0, 0.0]

## Dynamically randomized drift speeds assigned to individual text shadow instances.
var walk_speeds: Array[float] = [0.0, 0.0]

## Dynamic Tween instance controlling the glowing light sweep progress across the button.
var shine_tween: Tween

## Tracked 2D vector mapping the current mouse-driven structural tilt deformation.
var current_tilt := Vector2.ZERO

# --- GLITCH VARIABLES ---

## Preserved original textual configuration string restored automatically following a corruption
## glitch.
var original_button_text : String = ""

## Ongoing count-down timer tracking the remaining duration until the next glitch cycle phase.
var glitch_timer : float = 0.0

## Flag status checking whether a terrifying text corruption sequence is actively running.
var is_glitching : bool = false

## Prerequisite safety check ensuring the component contains valid corruption text parameters to
## run.
var can_glitch : bool = false

## Memory tracker of the component layout boundaries to catch layout container resizing safely.
var _last_known_size := Vector2.ZERO


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	print("HorrorButton: Initializing ready sequence.")
	active_horror_buttons += 1
	flat = true

	# Enable Godot 4.7 visual-only offset transforms to keep container layouts safe
	offset_transform_enabled = true

	var empty_style : StyleBoxEmpty = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty_style)
	add_theme_stylebox_override("hover", empty_style)
	add_theme_stylebox_override("pressed", empty_style)
	add_theme_stylebox_override("disabled", empty_style)
	add_theme_stylebox_override("focus", empty_style)

	randomize()
	original_scale = offset_transform_scale

	button_down.connect(
		func() -> void:
			print("HorrorButton: button_down triggered.")
			is_clicking = true
	)
	button_up.connect(
		func() -> void:
			print("HorrorButton: button_up triggered.")
			is_clicking = false
	)

	glitch_timer = randf_range(min_glitch_time, max_glitch_time)

	for child: Node in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if child is Label:
			text_label = child
		elif child is ColorRect and child.name == "Border":
			border_rect = child
		elif child is ColorRect and child.name == "Background":
			bg_rect = child

	if is_instance_valid(bg_rect) and bg_rect.material is ShaderMaterial:
		bg_material = bg_rect.material.duplicate() as ShaderMaterial
		bg_rect.material = bg_material
		bg_material.set_shader_parameter("hover_intensity", 0.0)
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

	if is_instance_valid(border_rect) and border_rect.material is ShaderMaterial:
		border_material = border_rect.material.duplicate() as ShaderMaterial
		border_rect.material = border_material
		border_material.set_shader_parameter("hover_intensity", 0.0)

	if is_instance_valid(text_label):
		text_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		text_label.position = Vector2.ZERO
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		if custom_text != "":
			text_label.text = custom_text
			original_button_text = custom_text
			if custom_minimum_size == Vector2.ZERO:
				custom_minimum_size = text_label.get_minimum_size()
		else:
			original_button_text = text_label.text
			if custom_minimum_size == Vector2.ZERO:
				custom_minimum_size = text_label.get_minimum_size()

	text = ""
	can_glitch = (glitch_text != "")

	if is_instance_valid(text_label) and text_label.material is ShaderMaterial:
		label_material = text_label.material.duplicate() as ShaderMaterial
		text_label.material = label_material

		for i: int in 2:
			shadows_x[i] = randf_range(-0.5, 1.5)
			target_shadows_x[i] = shadows_x[i]
			pace_timers[i] = randf_range(0.0, 2.0)
			walk_speeds[i] = randf_range(walk_speed * 0.6, walk_speed * 1.4)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_update_layout_sizes)

	await get_tree().process_frame
	_update_layout_sizes()
	print("HorrorButton: Initialized configuration profile complete.")


func _update_layout_sizes() -> void:
	if size == _last_known_size:
		return

	print("HorrorButton: Layout size boundary shift captured: ", size)
	_last_known_size = size
	pivot_offset = size / 2.0

	if is_instance_valid(bg_rect):
		bg_rect.set_deferred("size", size)
	if is_instance_valid(bg_material):
		bg_material.set_shader_parameter("rect_size", size)

	if is_instance_valid(border_rect):
		border_rect.set_deferred("size", size)
	if is_instance_valid(border_material):
		border_material.set_shader_parameter("rect_size", size)

	if is_instance_valid(text_label):
		text_label.set_deferred("size", size)
		text_label.set_deferred("pivot_offset", size / 2.0)
	if is_instance_valid(label_material):
		label_material.set_shader_parameter("rect_size", size)


func _on_mouse_entered() -> void:
	print("HorrorButton: Hover status entered.")
	is_mouse_over = true

	if is_instance_valid(bg_material):
		current_hover_intensity = 1.0
		if is_instance_valid(shine_tween) and shine_tween.is_valid():
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
	print("HorrorButton: Hover status terminated.")
	is_mouse_over = false
	is_clicking = false

	for i: int in 2:
		pace_timers[i] = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if size.x <= 0.1 or size.y <= 0.1:
		return

	if size != _last_known_size:
		_update_layout_sizes()

	# Godot 4.7 visual-only state checks mapping safely to offset transforms
	var is_settled: bool = (
		not is_mouse_over
		and current_hover_intensity < 0.001
		and offset_transform_scale.is_equal_approx(original_scale)
		and current_tilt.length_squared() < 0.0001
		and absf(offset_transform_rotation) < 0.001
	)

	var mouse_pos := get_local_mouse_position()
	var center_x := size.x / 2.0
	var center_y := size.y / 2.0

	if not is_settled:
		var target_rotation : float = 0.0
		var tilt_target := Vector2.ZERO

		if is_mouse_over:
			current_hover_intensity = move_toward(current_hover_intensity, 1.0, 3.0 * delta)

			var normalized_x := clampf((mouse_pos.x - center_x) / center_x, -1.0, 1.0)
			var normalized_y := clampf((mouse_pos.y - center_y) / center_y, -1.0, 1.0)

			target_rotation = deg_to_rad(max_rotation_degrees * normalized_x)
			tilt_target = Vector2(normalized_x, normalized_y)

			if is_clicking:
				offset_transform_scale = offset_transform_scale.lerp(
					press_scale, press_speed * delta
				)

				if is_instance_valid(text_label):
					var target_text_pos := (
						Vector2(-normalized_x, -normalized_y) * parallax_intensity
					)
					target_text_pos.y += press_depth
					text_label.position = text_label.position.lerp(
						target_text_pos, press_speed * delta
					)
					text_label.scale = text_label.scale.lerp(Vector2(1.0, 1.0), press_speed * delta)
			else:
				var pitch_scale_modifier: float = 1.0 - (absf(normalized_y) * 0.04)
				var final_target_scale := hover_scale * Vector2(1.0, pitch_scale_modifier)
				offset_transform_scale = offset_transform_scale.lerp(
					final_target_scale, response_speed * delta
				)

				if is_instance_valid(text_label):
					var target_text_pos := (
						Vector2(-normalized_x, -normalized_y) * parallax_intensity
					)
					text_label.position = text_label.position.lerp(
						target_text_pos, response_speed * delta
					)

					var time_sec := Time.get_ticks_msec() / 1000.0
					var pulse := pow(sin(time_sec * pulse_speed), 4.0)
					var current_text_scale := 1.0 + (pulse * pulse_intensity)
					text_label.scale = Vector2(current_text_scale, current_text_scale)

		else:
			current_hover_intensity = move_toward(current_hover_intensity, 0.0, 3.0 * delta)
			offset_transform_scale = offset_transform_scale.lerp(
				original_scale, response_speed * delta
			)

			if is_instance_valid(text_label):
				text_label.position = text_label.position.lerp(Vector2.ZERO, response_speed * delta)
				text_label.scale = text_label.scale.lerp(Vector2(1.0, 1.0), response_speed * delta)

		offset_transform_rotation = lerpf(
			offset_transform_rotation, target_rotation, response_speed * delta
		)
		current_tilt = current_tilt.lerp(tilt_target, response_speed * delta)

		if not is_mouse_over and current_hover_intensity < 0.001:
			current_hover_intensity = 0.0
			offset_transform_rotation = 0.0
			offset_transform_scale = original_scale
			current_tilt = Vector2.ZERO
			if is_instance_valid(text_label):
				text_label.position = Vector2.ZERO
				text_label.scale = Vector2(1.0, 1.0)

		if is_instance_valid(bg_material):
			bg_material.set_shader_parameter("hover_intensity", current_hover_intensity)
			bg_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)
			if is_mouse_over and is_instance_valid(bg_rect):
				var local_mouse_pos := bg_rect.get_local_mouse_position()
				var mouse_uv : Vector2 = Vector2(
					local_mouse_pos.x / bg_rect.size.x, local_mouse_pos.y / bg_rect.size.y
				)
				bg_material.set_shader_parameter("mouse_pos_uv", mouse_uv)

		if is_instance_valid(border_material):
			border_material.set_shader_parameter("hover_intensity", current_hover_intensity)
			border_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)

		if is_instance_valid(label_material):
			label_material.set_shader_parameter("hover_intensity", current_hover_intensity)
			label_material.set_shader_parameter("ui_tilt", current_tilt * current_hover_intensity)

	if is_instance_valid(label_material):
		var shadows_moved: bool = false
		for i: int in 2:
			if is_mouse_over:
				var uv_target := clampf(mouse_pos.x / size.x, -0.2, 1.2)
				if not is_equal_approx(shadows_x[i], uv_target):
					shadows_x[i] = move_toward(shadows_x[i], uv_target, hunt_speed * delta)
					shadows_moved = true
			else:
				pace_timers[i] -= delta
				if pace_timers[i] <= 0.0:
					pace_timers[i] = randf_range(1.0, 3.0)
					target_shadows_x[i] = randf_range(-0.2, 1.2)
					walk_speeds[i] = randf_range(walk_speed * 0.5, walk_speed * 1.5)

				if not is_equal_approx(shadows_x[i], target_shadows_x[i]):
					shadows_x[i] = move_toward(
						shadows_x[i], target_shadows_x[i], walk_speeds[i] * delta
					)
					shadows_moved = true

		if shadows_moved:
			label_material.set_shader_parameter("shadow_1_x", shadows_x[0])
			label_material.set_shader_parameter("shadow_2_x", shadows_x[1])

	if can_glitch and is_instance_valid(text_label):
		glitch_timer -= delta
		if glitch_timer <= 0.0:
			if is_glitching:
				print(
					"HorrorButton: Glitch execution window complete. Restoring text string profiles."
				)
				is_glitching = false
				text_label.text = original_button_text
				glitch_timer = randf_range(min_glitch_time, max_glitch_time)
			else:
				print("HorrorButton: Glitch activation state achieved.")
				is_glitching = true
				text_label.text = glitch_text
				glitch_timer = glitch_duration
