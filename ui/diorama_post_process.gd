## Applies screen filters and film grain effects strictly within the preview viewport.
class_name DioramaPostProcess
extends ColorRect

## Shader uniform key for screen filter mode index.
const PARAM_FILTER_MODE: StringName = &"filter_mode"
## Shader uniform key for film grain intensity.
const PARAM_GRAIN_AMOUNT: StringName = &"grain_amount"

## Reference to the active shader material.
var _post_mat: ShaderMaterial


## Lifecycle method registering viewport listeners for visual effects.
func _ready() -> void:
	print("UI: DioramaPostProcess initialized inside SubViewport.")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if material is ShaderMaterial:
		_post_mat = material as ShaderMaterial
	else:
		push_warning("DioramaPostProcess: No ShaderMaterial attached to ColorRect.")

	if is_instance_valid(Events):
		if not Events.screen_filter_changed.is_connected(_on_screen_filter_changed):
			Events.screen_filter_changed.connect(_on_screen_filter_changed)
		if not Events.film_grain_changed.is_connected(_on_film_grain_changed):
			Events.film_grain_changed.connect(_on_film_grain_changed)


## Disconnects global [Events] signals when removed from the scene tree.
func _exit_tree() -> void:
	if not is_instance_valid(Events):
		return
	if Events.screen_filter_changed.is_connected(_on_screen_filter_changed):
		Events.screen_filter_changed.disconnect(_on_screen_filter_changed)
	if Events.film_grain_changed.is_connected(_on_film_grain_changed):
		Events.film_grain_changed.disconnect(_on_film_grain_changed)


## Updates screen filter shader integer parameter.
func _on_screen_filter_changed(filter_name: String) -> void:
	var clean_filter: String = filter_name.to_lower()
	var mode_index: int = GlobalSettings.get_screen_filter_index(clean_filter)
	print(
		"Diorama: Applying screen filter '",
		clean_filter,
		"' (index: ",
		mode_index,
		") to SubViewport overlay."
	)
	if not is_instance_valid(_post_mat):
		return
	_post_mat.set_shader_parameter(PARAM_FILTER_MODE, mode_index)


## Updates film grain intensity within the viewport shader.
func _on_film_grain_changed(intensity: float) -> void:
	print("Diorama: Setting film grain intensity to: ", intensity)
	if not is_instance_valid(_post_mat):
		return
	_post_mat.set_shader_parameter(PARAM_GRAIN_AMOUNT, intensity)
