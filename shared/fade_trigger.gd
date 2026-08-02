@tool
extends Area3D

@export_category("Level Design")
## Changes the size of the trigger box directly from the inspector.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_bounds()

@export_category("Trigger Settings")
@export var trigger_once: bool = true

@export_category("Fade Timings")
@export var fade_in_duration: float = 1.0
@export var hold_duration: float = 0.5
@export var fade_out_duration: float = 1.0

@export_category("Visual Effects")
@export var fade_color: Color = Color.BLACK
@export var use_blur: bool = true
@export var max_blur: float = 2.5
@export var use_blink: bool = false
@export_range(1, 10) var blink_count: int = 1

var _triggered: bool = false
var _active_tween: Tween

@onready var overlay: ColorRect = $CanvasLayer/ColorRect


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Optimization: Delete the visual mesh so it costs zero performance in the compiled game
	var editor_mesh: MeshInstance3D = get_node_or_null("EditorVisual") as MeshInstance3D
	if editor_mesh:
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


func _update_bounds() -> void:
	# 1. Update the invisible physics collision shape
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		if not col.shape:
			col.shape = BoxShape3D.new()

		# Duplicate the shape so resizing one trigger doesn't resize all of them!
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true

		if col.shape is BoxShape3D:
			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = trigger_size

	# 2. Update the visible editor mesh (if it exists)
	var mesh: MeshInstance3D = get_node_or_null("EditorVisual") as MeshInstance3D
	if mesh and mesh.mesh is BoxMesh:
		var box_mesh: BoxMesh = mesh.mesh as BoxMesh
		box_mesh.size = trigger_size


func _on_body_entered(body: Node3D) -> void:
	# Prevent the editor from executing gameplay code if the player is somehow simulated
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
	var mat: ShaderMaterial = overlay.material as ShaderMaterial
	if not mat:
		push_error("ColorRect is missing a ShaderMaterial.")
		return

	overlay.visible = true

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	print("FadeTrigger: Executing sequence. Blinks calculated: ", blink_count if use_blink else 0)

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


# Helper methods required by tween_method to update shader uniforms
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
