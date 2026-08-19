## Applies screen filters and film grain effects strictly within the preview viewport.
class_name DioramaPostProcess
extends ColorRect

## Reference to the active shader material.
var _post_mat: ShaderMaterial

## Mapping from screen filter string identifiers to shader integer modes.
const FILTER_NAME_TO_INDEX: Dictionary[String, int] = {
	"off": 0,
	"crt": 1,
	"vhs": 2,
	"pixelate": 3,
	"toon": 4,
	"gameboy": 5,
	"glitch": 6,
	"grain": 7,
	"halftone": 8,
	"nightvision": 9,
	"kuwahara": 10,
	"ascii": 11,
	"90anime": 12,
	"manga": 13,
	"handdrawn": 14,
	"moebius": 15,
	"obra": 16,
	"psychedelic": 17,
	"botw": 18,
	"ghibli": 19
}


## Lifecycle method registering viewport listeners for visual effects.
func _ready() -> void:
	print("UI: DioramaPostProcess initialized inside SubViewport.")
	color = Color(1.0, 1.0, 1.0, 1.0)

	if material is ShaderMaterial:
		_post_mat = material as ShaderMaterial
	else:
		push_warning("DioramaPostProcess: No ShaderMaterial attached to ColorRect.")

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("screen_filter_changed"):
			events.screen_filter_changed.connect(_on_screen_filter_changed)
		if events.has_signal("film_grain_changed"):
			events.film_grain_changed.connect(_on_film_grain_changed)


## Updates screen filter shader integer parameter.
## [param filter_name] String key of the selected filter.
func _on_screen_filter_changed(filter_name: String) -> void:
	var clean_filter: String = filter_name.to_lower()
	var mode_index: int = FILTER_NAME_TO_INDEX.get(clean_filter, 0)
	print(
		"Diorama: Applying screen filter '",
		clean_filter,
		"' (index: ",
		mode_index,
		") to SubViewport overlay."
	)
	if not _post_mat:
		return
	_post_mat.set_shader_parameter("filter_mode", mode_index)


## Updates film grain intensity within the viewport shader.
## [param intensity] Active grain multiplier.
func _on_film_grain_changed(intensity: float) -> void:
	print("Diorama: Setting film grain intensity to: ", intensity)
	if not _post_mat:
		return
	_post_mat.set_shader_parameter("grain_amount", intensity)
