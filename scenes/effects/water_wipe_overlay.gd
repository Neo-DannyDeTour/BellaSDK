class_name WaterOverlayController
extends CanvasLayer

@export var overlay_rect: ColorRect
@export var fade_time: float = 1.0

var _tween: Tween


func _ready() -> void:
	if overlay_rect != null:
		_set_progress(0.0)


func trigger_water_exit() -> void:
	if overlay_rect == null:
		return

	var mat: Material = overlay_rect.material
	if not mat is ShaderMaterial:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_set_progress(1.0)

	var tweener: MethodTweener = _tween.tween_method(_set_progress, 1.0, 0.0, fade_time)

	# Easing out cubic makes the wipe start fast and smoothly trail off
	tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_progress(value: float) -> void:
	var mat: Material = overlay_rect.material
	if mat is ShaderMaterial:
		mat.set_shader_parameter("progress", value)
