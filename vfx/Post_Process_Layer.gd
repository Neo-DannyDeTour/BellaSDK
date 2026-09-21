## Manages fullscreen post-processing shaders, colorblind filters, and overlays.
#class_name PostProcessLayer
extends CanvasLayer

## Fullscreen color rectangle hosting the colorblind compensation shader.
var colorblind_rect: ColorRect
## Fullscreen color rectangle hosting high-contrast edge overlays.
var high_contrast_rect: ColorRect
## Fullscreen color rectangle hosting general screen filter shaders.
var screen_filter_rect: ColorRect

## Internal cache mapping filter keys to preloaded [Shader] resources.
var cached_shaders: Dictionary = {}


## Sets layer priority, process mode, and initializes overlays and listeners.
func _ready() -> void:
	print("PostProcessLayer: Initializing post-processing layers.")
	layer = 127
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_rects()
	_connect_signals()


## Builds and configures all fullscreen overlay [ColorRect] instances.
func _build_rects() -> void:
	print("PostProcessLayer: Building screen filter overlays.")
	colorblind_rect = ColorRect.new()
	colorblind_rect.name = "ColorblindRect"
	colorblind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	colorblind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var cb_mat: ShaderMaterial = ShaderMaterial.new()
	cb_mat.shader = preload("res://vfx/colorblind.gdshader")
	colorblind_rect.material = cb_mat
	add_child(colorblind_rect)

	high_contrast_rect = ColorRect.new()
	high_contrast_rect.name = "HighContrastRect"
	high_contrast_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	high_contrast_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	high_contrast_rect.visible = false

	var hc_mat: ShaderMaterial = ShaderMaterial.new()
	hc_mat.shader = preload("res://vfx/high_contrast.gdshader")
	high_contrast_rect.material = hc_mat
	add_child(high_contrast_rect)

	screen_filter_rect = ColorRect.new()
	screen_filter_rect.name = "ScreenFilterRect"
	screen_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_filter_rect.visible = false
	add_child(screen_filter_rect)


## Subscribes to post-processing events on the global bus.
func _connect_signals() -> void:
	print("PostProcessLayer: Connecting event bus signals.")
	if not has_node("/root/Events"):
		return
	var events: Node = get_node("/root/Events")
	if events.has_signal("colorblind_mode_changed"):
		events.colorblind_mode_changed.connect(set_colorblind_mode)
	if events.has_signal("high_contrast_toggled"):
		events.high_contrast_toggled.connect(set_high_contrast)
	if events.has_signal("screen_filter_changed"):
		events.screen_filter_changed.connect(set_screen_filter)
	if events.has_signal("film_grain_changed"):
		events.film_grain_changed.connect(set_film_grain)


## Updates the mode uniform on the colorblind [ShaderMaterial].
func set_colorblind_mode(mode: int) -> void:
	print("PostProcessLayer: Applying colorblind mode index: ", mode)
	if not is_instance_valid(colorblind_rect):
		return
	var mat: ShaderMaterial = colorblind_rect.material as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("mode", mode)


## Toggles visibility on the high contrast screen overlay.
func set_high_contrast(is_active: bool) -> void:
	print("PostProcessLayer: Setting high contrast active: ", is_active)
	if is_instance_valid(high_contrast_rect):
		high_contrast_rect.visible = is_active


## Applies a named screen filter shader loaded via [GlobalSettings].
func set_screen_filter(filter_name: String) -> void:
	print("PostProcessLayer: Setting screen filter: ", filter_name)
	if not is_instance_valid(screen_filter_rect):
		return

	var clean_filter: String = filter_name.to_lower()
	if clean_filter == "off":
		screen_filter_rect.material = null
		screen_filter_rect.visible = false
		return

	if not is_instance_valid(GlobalSettings):
		return

	var shader_path: String = GlobalSettings.get_screen_filter_path(clean_filter)
	if shader_path.is_empty():
		push_warning("PostProcessLayer: No shader path mapped for: " + clean_filter)
		return

	if not cached_shaders.has(clean_filter):
		if ResourceLoader.exists(shader_path):
			cached_shaders[clean_filter] = load(shader_path)
		else:
			push_warning("PostProcessLayer: Shader not found at: " + shader_path)
			return

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = cached_shaders[clean_filter] as Shader
	screen_filter_rect.material = mat
	screen_filter_rect.visible = true


## Updates the grain intensity uniform on the active screen filter.
func set_film_grain(intensity: float) -> void:
	print("PostProcessLayer: Setting film grain intensity: ", intensity)
	if not is_instance_valid(screen_filter_rect) or not screen_filter_rect.visible:
		return
	var mat: ShaderMaterial = screen_filter_rect.material as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("grain_amount", intensity)
