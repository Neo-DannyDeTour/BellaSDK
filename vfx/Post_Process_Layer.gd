## Manages fullscreen post-processing shaders, colorblind filters, and overlays.
#class_name PostProcessLayer
extends CanvasLayer

## Pre-allocated shader uniform key for colorblind mode index.
const UNIFORM_MODE: StringName = &"mode"

## Pre-allocated shader uniform key for film grain intensity.
const UNIFORM_GRAIN_AMOUNT: StringName = &"grain_amount"

## Preloaded colorblind compensation shader resource.
const SHADER_COLORBLIND: Shader = preload("res://vfx/colorblind.gdshader")

## Preloaded high-contrast edge overlay shader resource.
const SHADER_HIGH_CONTRAST: Shader = preload("res://vfx/high_contrast.gdshader")

## Preloaded map of screen filter IDs to [Shader] resources.
const SCREEN_FILTER_SHADERS: Dictionary[String, Shader] = {
	"crt": preload("res://vfx/crt.gdshader"),
	"vhs": preload("res://vfx/vhs.gdshader"),
	"pixelate": preload("res://vfx/pixelate.gdshader"),
	"toon": preload("res://vfx/toon.gdshader"),
	"gameboy": preload("res://vfx/gameboy.gdshader"),
	"glitch": preload("res://vfx/glitch.gdshader"),
	"grain": preload("res://environment/grain.gdshader"),
	"halftone": preload("res://vfx/halftone.gdshader"),
	"nightvision": preload("res://vfx/nightvision.gdshader"),
	"kuwahara": preload("res://vfx/kuwahara.gdshader"),
	"ascii": preload("res://vfx/ascii.gdshader"),
	"90anime": preload("res://vfx/90anime.gdshader"),
	"manga": preload("res://vfx/manga.gdshader"),
	"handdrawn": preload("res://vfx/handdrawn.gdshader"),
	"moebius": preload("res://vfx/moebius.gdshader"),
	"obra": preload("res://vfx/obra.gdshader"),
	"psychedelic": preload("res://vfx/psychedelic.gdshader"),
	"botw": preload("res://vfx/botw.gdshader"),
	"ghibli": preload("res://vfx/ghibli.gdshader"),
	"software": preload("res://vfx/software.gdshader"),
	"swirl": preload("res://vfx/swirl.gdshader"),
	"mandelbrot": preload("res://vfx/mandelbrot.gdshader"),
	"80sfantasy": preload("res://vfx/80sfantasy.gdshader"),
	"oldphoto": preload("res://vfx/old_photo.gdshader"),
}

## Fullscreen color rectangle hosting the colorblind compensation shader.
var colorblind_rect: ColorRect
## Fullscreen color rectangle hosting high-contrast edge overlays.
var high_contrast_rect: ColorRect
## Fullscreen color rectangle hosting general screen filter shaders.
var screen_filter_rect: ColorRect

## Internal cache mapping filter keys to preloaded [Shader] resources.
var cached_shaders: Dictionary[String, Shader] = {}


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
	cb_mat.shader = SHADER_COLORBLIND
	colorblind_rect.material = cb_mat
	add_child(colorblind_rect)

	high_contrast_rect = ColorRect.new()
	high_contrast_rect.name = "HighContrastRect"
	high_contrast_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	high_contrast_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	high_contrast_rect.visible = false

	var hc_mat: ShaderMaterial = ShaderMaterial.new()
	hc_mat.shader = SHADER_HIGH_CONTRAST
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
	if is_instance_valid(Events):
		Events.colorblind_mode_changed.connect(set_colorblind_mode)
		Events.high_contrast_toggled.connect(set_high_contrast)
		Events.screen_filter_changed.connect(set_screen_filter)
		Events.film_grain_changed.connect(set_film_grain)


## Updates the mode uniform on the colorblind [ShaderMaterial].
func set_colorblind_mode(mode: int) -> void:
	print("PostProcessLayer: Applying colorblind mode index: ", mode)
	if not is_instance_valid(colorblind_rect):
		return
	var raw_mat: Material = colorblind_rect.material
	var mat: ShaderMaterial = raw_mat if raw_mat is ShaderMaterial else null
	if is_instance_valid(mat):
		mat.set_shader_parameter(UNIFORM_MODE, mode)


## Toggles visibility on the high contrast screen overlay.
func set_high_contrast(is_active: bool) -> void:
	print("PostProcessLayer: Setting high contrast active: ", is_active)
	if is_instance_valid(high_contrast_rect):
		high_contrast_rect.visible = is_active


## Applies a named preloaded screen filter shader.
func set_screen_filter(filter_name: String) -> void:
	print("PostProcessLayer: Setting screen filter: ", filter_name)
	if not is_instance_valid(screen_filter_rect):
		return

	var clean_filter: String = filter_name.to_lower()
	if clean_filter == "off":
		screen_filter_rect.material = null
		screen_filter_rect.visible = false
		return

	if not SCREEN_FILTER_SHADERS.has(clean_filter):
		push_warning("PostProcessLayer: No shader mapped for: " + clean_filter)
		return

	var shader_res: Shader = SCREEN_FILTER_SHADERS[clean_filter]
	cached_shaders[clean_filter] = shader_res
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader_res
	screen_filter_rect.material = mat
	screen_filter_rect.visible = true


## Updates the grain intensity uniform on the active screen filter.
func set_film_grain(intensity: float) -> void:
	print("PostProcessLayer: Setting film grain intensity: ", intensity)
	if not is_instance_valid(screen_filter_rect) or not screen_filter_rect.visible:
		return
	var raw_mat: Material = screen_filter_rect.material
	var mat: ShaderMaterial = raw_mat if raw_mat is ShaderMaterial else null
	if is_instance_valid(mat):
		mat.set_shader_parameter(UNIFORM_GRAIN_AMOUNT, intensity)
