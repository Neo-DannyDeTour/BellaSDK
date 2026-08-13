extends Area3D

## Defines the geometric shape of the trigger and its visualizer.
enum ShapeType { BOX, SPHERE }

@export_category("Level Design")

## Changes the size of the trigger box or radius of the sphere directly from the inspector.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_visuals()

@export_category("Visualizer Settings")

## The physical and visual shape of the trigger area.
@export var shape_type: ShapeType = ShapeType.BOX:
	set(value):
		shape_type = value
		_update_visuals()

## Determines if the trigger visualizer remains visible during active gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		_update_visuals()

## The color of the trigger's debug visual mesh.
@export var trigger_color: Color = Color(0.9, 0.5, 0.1, 0.4):
	set(value):
		trigger_color = value
		_update_visuals()

## The text displayed on the trigger's label inside the editor.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		_update_visuals()

@export_category("Trigger Settings")

## Determines if the effect should only happen the first time a player enters.
@export var trigger_once: bool = true

@export_category("Fade Timings")

## Duration in seconds for the screen to fade to the target color.
@export var fade_in_duration: float = 1.0

## Duration in seconds the screen remains fully faded before returning.
@export var hold_duration: float = 0.5

## Duration in seconds for the screen to return to normal.
@export var fade_out_duration: float = 1.0

@export_category("Visual Effects")

## The target color the screen will fade towards.
@export var fade_color: Color = Color.BLACK

## Enables a blur effect during the fade transition.
@export var use_blur: bool = true

## The maximum intensity of the blur effect.
@export var max_blur: float = 2.5

## Enables a blinking effect during the transition.
@export var use_blink: bool = false

## The number of times the screen blinks during the fade sequence.
@export_range(1, 10) var blink_count: int = 1

## Tracks whether this trigger has already been activated by a player.
var _triggered: bool = false

## Stores the currently running animation tween so it can be interrupted if needed.
var _active_tween: Tween

## Reference to the screen overlay node used for visual effects.
@onready var overlay: ColorRect = $CanvasLayer/ColorRect


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_visuals()
		return

	# Optimization: Delete the visual mesh so it costs zero performance in the compiled game
	var editor_mesh: EditorTriggerVisualizer = _get_visualizer()
	if editor_mesh:
		if not show_in_game:
			editor_mesh.queue_free()

	# Optimization: Disable visibility to save GPU fill rate when inactive
	overlay.visible = false
	var mat: ShaderMaterial = overlay.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("fade_amount", 0.0)
		mat.set_shader_parameter("blur_amount", 0.0)
		mat.set_shader_parameter("blink_openness", 1.0)
		mat.set_shader_parameter("fade_color", fade_color)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _update_visuals() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		if shape_type == ShapeType.BOX:
			if not col.shape or not col.shape is BoxShape3D:
				col.shape = BoxShape3D.new()

			if not col.shape.resource_local_to_scene:
				col.shape = col.shape.duplicate()
				col.shape.resource_local_to_scene = true

			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = trigger_size

		elif shape_type == ShapeType.SPHERE:
			if not col.shape or not col.shape is SphereShape3D:
				col.shape = SphereShape3D.new()

			if not col.shape.resource_local_to_scene:
				col.shape = col.shape.duplicate()
				col.shape.resource_local_to_scene = true

			var sphere: SphereShape3D = col.shape as SphereShape3D
			sphere.radius = trigger_size.x / 2.0

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if visual:
		# Cast explicitly to the expected enum type to resolve INT_AS_ENUM_WITHOUT_CAST
		visual.shape_type = shape_type as EditorTriggerVisualizer.ShapeType
		visual.show_in_game = show_in_game
		visual.trigger_size = trigger_size
		visual.trigger_color = trigger_color
		visual.trigger_text = trigger_text


func _get_visualizer() -> EditorTriggerVisualizer:
	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			return child as EditorTriggerVisualizer
	return null


func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if not body.is_in_group("player"):
		return

	if trigger_once and _triggered:
		return

	_triggered = true
	print("FadeTrigger activated by: ", body.name, ". Starting screen fade sequence.")
	_start_effect_sequence()


func _start_effect_sequence() -> void:
	print("FadeTrigger: Executing visual effect sequence overlays.")
	var mat: ShaderMaterial = overlay.material as ShaderMaterial
	if not mat:
		push_error("ColorRect is missing a ShaderMaterial.")
		return

	overlay.visible = true

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	_active_tween = create_tween()

	# --- Phase 1: FADE IN ---
	(
		_active_tween
		. tween_method(_set_fade.bind(mat), 0.0, 1.0, fade_in_duration)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	if use_blur:
		(
			_active_tween
			. parallel()
			. tween_method(_set_blur.bind(mat), 0.0, max_blur, fade_in_duration)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	if use_blink:
		var single_blink_time: float = fade_in_duration / float(blink_count)

		for i: int in range(blink_count):
			var delay: float = i * single_blink_time
			var is_last: bool = i == blink_count - 1

			if not is_last:
				# Close eyes
				(
					_active_tween
					. parallel()
					. tween_method(_set_blink.bind(mat), 1.0, 0.0, single_blink_time * 0.5)
					. set_delay(delay)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_IN_OUT)
				)

				# Open eyes
				(
					_active_tween
					. parallel()
					. tween_method(_set_blink.bind(mat), 0.0, 1.0, single_blink_time * 0.5)
					. set_delay(delay + single_blink_time * 0.5)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_IN_OUT)
				)
			else:
				# Final blink stays closed for the hold phase
				(
					_active_tween
					. parallel()
					. tween_method(_set_blink.bind(mat), 1.0, 0.0, single_blink_time)
					. set_delay(delay)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_IN_OUT)
				)

	# --- Phase 2: HOLD ---
	_active_tween.tween_interval(hold_duration)

	# --- Phase 3: FADE OUT ---
	(
		_active_tween
		. tween_method(_set_fade.bind(mat), 1.0, 0.0, fade_out_duration)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)

	if use_blur:
		(
			_active_tween
			. parallel()
			. tween_method(_set_blur.bind(mat), max_blur, 0.0, fade_out_duration)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	if use_blink:
		(
			_active_tween
			. parallel()
			. tween_method(_set_blink.bind(mat), 0.0, 1.0, fade_out_duration)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

	# --- Phase 4: CLEANUP ---
	_active_tween.tween_callback(_on_sequence_finished)


func _set_fade(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("fade_amount", value)


func _set_blur(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("blur_amount", value)


func _set_blink(value: float, mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("blink_openness", value)


func _on_sequence_finished() -> void:
	print("FadeTrigger: Sequence finished, resetting.")
	overlay.visible = false
	if not trigger_once:
		_triggered = false
