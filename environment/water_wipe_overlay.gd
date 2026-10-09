## Controls screen-space water exit wipe shader transitions.
class_name WaterOverlayController
extends CanvasLayer

@export var overlay_rect: ColorRect
@export var fade_time: float = 1.0

var _tween: Tween


## Resets the overlay progress to zero on node initialization.
func _ready() -> void:
	print("WaterOverlayController: Initializing overlay state")
	if overlay_rect != null:
		_set_progress(0.0)


## Triggers the cubic water screen wipe when leaving water.
func trigger_water_exit() -> void:
	print("WaterOverlayController: Triggering water exit wipe")
	if overlay_rect == null:
		return

	var mat: Material = overlay_rect.material
	if not (mat is ShaderMaterial):
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_set_progress(1.0)

	var tweener: MethodTweener = _tween.tween_method(_set_progress, 1.0, 0.0, fade_time)
	tweener.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Updates the progress uniform on the underlying [ShaderMaterial].
func _set_progress(value: float) -> void:
	print("WaterOverlayController: Setting progress to " + str(value))
	var shader_mat: ShaderMaterial = overlay_rect.material as ShaderMaterial
	if shader_mat != null:
		shader_mat.set_shader_parameter("progress", value)
