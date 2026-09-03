## Manages user-configurable video settings, renderer switching, tonemapping,
## and synchronizes rendering features across viewports and preview environments.
class_name VideoOptions
extends Panel

## The default application display mode.
const DEFAULT_DISPLAY: int = DisplayServer.WINDOW_MODE_FULLSCREEN
## The default framerate target.
const DEFAULT_FPS: int = 60
## The default FSR configuration string.
const DEFAULT_FSR_MODE: String = "Disabled (Native)"
## The default Anti-Aliasing configuration string.
const DEFAULT_AA_MODE: String = "Disabled"
## The default VSync state.
const DEFAULT_VSYNC: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED
## The default preset configuration string.
const DEFAULT_PRESET: String = "High"
## The default Tonemapping algorithm mode.
const DEFAULT_TONEMAP: String = "Filmic"
## The default Anisotropic filtering setting string.
const DEFAULT_ANISOTROPY: String = "4x"

## Map of window mode titles to their respective [enum DisplayServer.WindowMode] values.
const DISPLAY_MODES: Dictionary = {
	"Fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	"Borderless Windowed": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"Windowed": DisplayServer.WINDOW_MODE_WINDOWED
}

## Map of rendering driver labels to their Godot project setting identifiers.
const RENDERER_MODES: Dictionary = {
	"Forward+ (Vulkan High-End)": "forward_plus",
	"Mobile (Vulkan Mobile)": "mobile",
	"Compatibility (OpenGL Low-End)": "gl_compatibility"
}

## Map of screen resolution labels to their respective pixel dimensions.
const RESOLUTIONS: Dictionary = {
	"1920 x 1080": Vector2i(1920, 1080),
	"1600 x 900": Vector2i(1600, 900),
	"1366 x 768": Vector2i(1366, 768),
	"1280 x 720": Vector2i(1280, 720),
	"1024 x 768": Vector2i(1024, 768),
	"800 x 600": Vector2i(800, 600),
	"640 x 480": Vector2i(640, 480)
}

## Map of selectable FPS limit labels to integer caps.
const FPS_LIMITS: Dictionary = {
	"30 FPS": 30, "60 FPS": 60, "120 FPS": 120, "144 FPS": 144, "Unlimited": 0
}

## Map of VSync option labels to [enum DisplayServer.VSyncMode] values.
const VSYNC_MODES: Dictionary = {
	"Enabled": DisplayServer.VSYNC_ENABLED,
	"Disabled": DisplayServer.VSYNC_DISABLED,
	"Adaptive": DisplayServer.VSYNC_ADAPTIVE
}

## Map of FSR 2 quality modes to their viewport 3D render scales.
const FSR_MODES: Dictionary = {
	"Disabled (Native)": 1.0, "Quality": 0.77, "Balanced": 0.59, "Performance": 0.50
}

## Map of anti-aliasing modes to MSAA, TAA, and FXAA configurations.
const AA_MODES: Dictionary = {
	"Disabled":
	{"msaa": Viewport.MSAA_DISABLED, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"FXAA (Fast)":
	{"msaa": Viewport.MSAA_DISABLED, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_FXAA},
	"TAA (Smooth)":
	{"msaa": Viewport.MSAA_DISABLED, "taa": true, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 2x": {"msaa": Viewport.MSAA_2X, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 4x": {"msaa": Viewport.MSAA_4X, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 8x (Heavy)":
	{"msaa": Viewport.MSAA_8X, "taa": false, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED},
	"MSAA 2x + TAA (High)":
	{"msaa": Viewport.MSAA_2X, "taa": true, "fxaa": Viewport.SCREEN_SPACE_AA_DISABLED}
}

## Map of shadow quality options to atlas sizes and filter settings.
const SHADOW_QUALITIES: Dictionary = {
	"Off": {"atlas_size": 0, "filter": 0},
	"Low (Fast)": {"atlas_size": 1024, "filter": 0},
	"Medium": {"atlas_size": 2048, "filter": 1},
	"High (Smooth)": {"atlas_size": 4096, "filter": 2}
}

## Map of Tonemapper option labels to configuration identifiers.
const TONEMAP_MODES: Dictionary = {
	"Linear": "linear",
	"Reinhard": "reinhard",
	"Filmic": "filmic",
	"ACES": "aces",
	"AgX": "agx",
	"AgX (Punchy)": "agx_punchy"
}

## Map of texture Anisotropic filtering levels to integer settings.
const ANISOTROPY_LEVELS: Dictionary = {"Disabled": 0, "2x": 1, "4x": 2, "8x": 3, "16x": 4}

## Reference to the video card selection [OptionButton].
@onready var gpu_options: OptionButton = %GPUAdapterOptionButton
## Reference to the renderer selection [OptionButton].
@onready var renderer_options: OptionButton = %RendererOptionButton
## Reference to the display mode [OptionButton].
@onready var display_options: OptionButton = %DisplayOptionButton
## Reference to the active monitor [OptionButton].
@onready var monitor_options: OptionButton = %MonitorOptionButton
## Reference to the resolution [OptionButton].
@onready var resolution_options: OptionButton = %ResolutionOptionButton
## Reference to the framerate limit [OptionButton].
@onready var fps_options: OptionButton = %FPSOptionButton
## Reference to the VSync mode [OptionButton].
@onready var vsync_options: OptionButton = %VSyncOptionButton
## Reference to the FSR scaling [OptionButton].
@onready var fsr_options: OptionButton = %FSROptionButton
## Reference to the anti-aliasing [OptionButton].
@onready var aa_options: OptionButton = %AAOptionButton
## Reference to the overall preset [OptionButton].
@onready var preset_options: OptionButton = %PresetOptionButton
## Reference to the shadow quality [OptionButton].
@onready var shadow_options: OptionButton = %ShadowOptionButton
## Reference to the tonemapper algorithm [OptionButton].
@onready var tonemap_options: OptionButton = %TonemapOptionButton
## Reference to the anisotropic filtering level [OptionButton].
@onready var anisotropy_options: OptionButton = %AnisotropyOptionButton
## Reference to the Mesh LOD direct numerical input [LineEdit].
@onready var mesh_lod_line: LineEdit = %MeshLODLine
## Reference to the Mesh LOD threshold [HSlider].
@onready var mesh_lod_slider: HSlider = %MeshLODSlider
## Reference to the color debanding toggle [CheckBox].
@onready var debanding_checkbox: CheckBox = %DebandingCheckBox
## Reference to the Screen Space Indirect Lighting toggle [CheckBox].
@onready var ssi_checkbox: CheckBox = %SSICheckBox
## Reference to the SSAO toggle [CheckBox].
@onready var ssao_checkbox: CheckBox = %SSAOCheckBox
## Reference to the SSR toggle [CheckBox].
@onready var ssr_checkbox: CheckBox = %SSRCheckBox
## Reference to the SDFGI toggle [CheckBox].
@onready var sdfgi_checkbox: CheckBox = %SDFGICheckBox
## Reference to the volumetric fog toggle [CheckBox].
@onready var fog_checkbox: CheckBox = %FogCheckBox
## Reference to the glow toggle [CheckBox].
@onready var glow_checkbox: CheckBox = %GlowCheckBox
## Reference to the auto-optimization benchmark [Button].
@onready var auto_tune_button: Button = %AutoTuneButton
## Reference to the restart confirmation [ConfirmationDialog].
@onready var restart_dialog: ConfirmationDialog = %RestartDialog

## Cached pending rendering method chosen before restarting.
var _pending_renderer: String = ""
## Cached pending GPU adapter index chosen before restarting.
var _pending_gpu_index: int = -1
## Map storing GPU adapter names mapped to their physical hardware index.
var _available_gpus: Dictionary = {}


## Initializes dropdown options, hooks UI signals, and loads settings from disk.
func _ready() -> void:
	print("UI: Video Panel initialized.")
	_populate_all_dropdowns()
	_connect_signals()
	_load_video_settings()

	if has_node("/root/GraphicsManager"):
		var manager: Node = get_node("/root/GraphicsManager")
		if manager.has_signal("benchmark_completed"):
			manager.connect("benchmark_completed", _on_benchmark_completed)


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("UI: Connecting video option signals.")
	preset_options.item_selected.connect(_on_preset_selected)
	renderer_options.item_selected.connect(_on_renderer_selected)
	gpu_options.item_selected.connect(_on_gpu_selected)
	display_options.item_selected.connect(_on_display_selected)
	monitor_options.item_selected.connect(_on_monitor_selected)
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)
	vsync_options.item_selected.connect(_on_vsync_selected)
	fsr_options.item_selected.connect(_on_fsr_selected)
	aa_options.item_selected.connect(_on_aa_selected)
	shadow_options.item_selected.connect(_on_shadow_selected)
	tonemap_options.item_selected.connect(_on_tonemap_selected)
	anisotropy_options.item_selected.connect(_on_anisotropy_selected)

	mesh_lod_slider.value_changed.connect(_on_mesh_lod_changed)
	mesh_lod_line.text_submitted.connect(_on_mesh_lod_text_submitted)
	mesh_lod_line.focus_exited.connect(_on_mesh_lod_focus_exited)

	debanding_checkbox.toggled.connect(_on_debanding_toggled)
	ssi_checkbox.toggled.connect(_on_ssi_toggled)
	ssao_checkbox.toggled.connect(_on_ssao_toggled)
	ssr_checkbox.toggled.connect(_on_ssr_toggled)
	sdfgi_checkbox.toggled.connect(_on_sdfgi_toggled)
	fog_checkbox.toggled.connect(_on_fog_toggled)
	glow_checkbox.toggled.connect(_on_glow_toggled)

	auto_tune_button.pressed.connect(_on_auto_tune_pressed)
	restart_dialog.confirmed.connect(_on_restart_dialog_confirmed)


## Populates all dropdown menus with predefined settings tables.
func _populate_all_dropdowns() -> void:
	print("UI: Populating Video Dropdowns dynamically.")
	preset_options.clear()
	preset_options.add_item("Low")
	preset_options.add_item("Medium")
	preset_options.add_item("High")
	preset_options.add_item("Ultra")

	_populate_gpu_adapters()
	_fill_dropdown(renderer_options, RENDERER_MODES)
	_fill_dropdown(display_options, DISPLAY_MODES)
	_populate_monitors()
	_fill_dropdown(resolution_options, RESOLUTIONS)
	_fill_dropdown(fps_options, FPS_LIMITS)
	_fill_dropdown(vsync_options, VSYNC_MODES)
	_fill_dropdown(fsr_options, FSR_MODES)
	_fill_dropdown(aa_options, AA_MODES)
	_fill_dropdown(shadow_options, SHADOW_QUALITIES)
	_fill_dropdown(tonemap_options, TONEMAP_MODES)
	_fill_dropdown(anisotropy_options, ANISOTROPY_LEVELS)


## Discovers available system GPU adapters and populates [member gpu_options].
func _populate_gpu_adapters() -> void:
	print("UI: Querying video adapters.")
	gpu_options.clear()
	_available_gpus.clear()

	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var adapter_name: String = ""

	if is_instance_valid(rd):
		adapter_name = rd.get_device_name()
	else:
		adapter_name = RenderingServer.get_video_adapter_name()

	if adapter_name.is_empty():
		adapter_name = "Default Graphics Adapter"

	var display_text: String = adapter_name + " (Active Device)"
	_available_gpus[display_text] = 0
	gpu_options.add_item(display_text)
	gpu_options.select(0)


## Populates connected physical monitors into [member monitor_options].
func _populate_monitors() -> void:
	print("UI: Detecting connected displays.")
	monitor_options.clear()
	var screen_count: int = DisplayServer.get_screen_count()
	for i: int in range(screen_count):
		monitor_options.add_item("Monitor " + str(i + 1))


## Populates a single [OptionButton] with keys from a [Dictionary].
## [param dropdown] The target button to fill.
## [param data_dict] The dictionary containing option names as keys.
func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("UI: Clearing and refilling individual dropdown.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


## Selects an item in [param dropdown] matching [param target_text].
## [param dropdown] The target button.
## [param target_text] The text label to select.
func _select_dropdown_by_text(dropdown: OptionButton, target_text: String) -> void:
	print("UI: Selecting dropdown text dynamically: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Reads saved video configuration from [GlobalSettings] and synchronizes the UI.
func _load_video_settings() -> void:
	print("UI: Loading video data from GlobalSettings.")
	var current_renderer: String = (
		GlobalSettings.get_setting("Settings", "renderer", "forward_plus") as String
	)
	for i: int in range(renderer_options.get_item_count()):
		var key_text: String = renderer_options.get_item_text(i)
		if RENDERER_MODES[key_text] == current_renderer:
			renderer_options.select(i)
			break

	var saved_gpu: int = GlobalSettings.get_setting("Settings", "gpu_adapter_index", 0) as int
	if saved_gpu < gpu_options.get_item_count():
		gpu_options.select(saved_gpu)

	_sync_dropdown_to_setting(display_options, DISPLAY_MODES, "display_mode", DEFAULT_DISPLAY)
	_sync_dropdown_to_setting(fps_options, FPS_LIMITS, "fps_limit", DEFAULT_FPS)
	_sync_dropdown_to_setting(vsync_options, VSYNC_MODES, "vsync_mode", DEFAULT_VSYNC)
	_sync_dropdown_to_setting(fsr_options, FSR_MODES, "fsr_mode", DEFAULT_FSR_MODE)
	_sync_dropdown_to_setting(aa_options, AA_MODES, "aa_mode", DEFAULT_AA_MODE)
	_sync_dropdown_to_setting(shadow_options, SHADOW_QUALITIES, "shadow_quality", "High (Smooth)")
	_sync_dropdown_to_setting(tonemap_options, TONEMAP_MODES, "tonemap_mode", DEFAULT_TONEMAP)
	_sync_dropdown_to_setting(
		anisotropy_options, ANISOTROPY_LEVELS, "anisotropy", DEFAULT_ANISOTROPY
	)

	var saved_preset: String = (
		GlobalSettings.get_setting("Settings", "preset", DEFAULT_PRESET) as String
	)
	_select_dropdown_by_text(preset_options, saved_preset)

	var saved_screen: int = GlobalSettings.get_setting("Settings", "screen_index", 0) as int
	if saved_screen < monitor_options.get_item_count():
		monitor_options.select(saved_screen)

	var res_x: int = GlobalSettings.get_setting("Settings", "resolution_x", 1920) as int
	var res_y: int = GlobalSettings.get_setting("Settings", "resolution_y", 1080) as int
	var res_string: String = str(res_x) + " x " + str(res_y)
	_select_dropdown_by_text(resolution_options, res_string)

	var saved_lod: float = (
		GlobalSettings.get_setting("Settings", "mesh_lod_threshold", 1.0) as float
	)
	mesh_lod_slider.value = saved_lod
	mesh_lod_line.text = str(snappedf(saved_lod, 0.01))

	debanding_checkbox.button_pressed = (
		GlobalSettings.get_setting("Settings", "debanding", true) as bool
	)
	ssi_checkbox.button_pressed = (GlobalSettings.get_setting("Settings", "ssi", false) as bool)
	ssao_checkbox.button_pressed = (GlobalSettings.get_setting("Settings", "ssao", true) as bool)
	ssr_checkbox.button_pressed = (GlobalSettings.get_setting("Settings", "ssr", false) as bool)
	sdfgi_checkbox.button_pressed = (GlobalSettings.get_setting("Settings", "sdfgi", true) as bool)
	fog_checkbox.button_pressed = (
		GlobalSettings.get_setting("Settings", "volumetric_fog", false) as bool
	)
	glow_checkbox.button_pressed = (GlobalSettings.get_setting("Settings", "glow", true) as bool)

	_apply_all_current_settings()


## Matches a saved value to an item in [param dropdown] using [param dict].
## Safely compares numeric and string types to prevent type mismatch crashes.
## [param dropdown] The option button to update.
## [param dict] Key-value dictionary associated with the option button.
## [param setting_key] The config setting key identifier.
## [param default_val] Default fallback value if setting does not exist.
func _sync_dropdown_to_setting(
	dropdown: OptionButton, dict: Dictionary, setting_key: String, default_val: Variant
) -> void:
	print("UI: Syncing dropdown dictionary index to saved file selection.")
	var saved_val: Variant = GlobalSettings.get_setting("Settings", setting_key, default_val)
	var saved_str: String = str(saved_val)

	for i: int in range(dropdown.get_item_count()):
		var item_text: String = dropdown.get_item_text(i)

		if item_text == saved_str:
			dropdown.select(i)
			return

		if dict.has(item_text):
			var dict_val: Variant = dict[item_text]
			if str(dict_val) == saved_str:
				dropdown.select(i)
				return


## Applies active UI settings to the engine, root window, and preview [SubViewport].
func _apply_all_current_settings() -> void:
	print("Engine: Applying all saved video and rendering settings.")
	var target_screen: int = monitor_options.selected
	get_window().current_screen = target_screen

	var mode_text: String = display_options.get_item_text(display_options.selected)
	var mode: DisplayServer.WindowMode = DISPLAY_MODES[mode_text] as DisplayServer.WindowMode
	DisplayServer.window_set_mode(mode)

	var res_key: String = resolution_options.get_item_text(resolution_options.selected)
	var new_size: Vector2i = RESOLUTIONS.get(res_key, Vector2i(1920, 1080)) as Vector2i
	get_window().content_scale_size = new_size
	if not get_window().is_embedded() and get_window().mode == Window.MODE_WINDOWED:
		get_window().size = new_size

	Engine.max_fps = (FPS_LIMITS[fps_options.get_item_text(fps_options.selected)] as int)

	var vsync_text: String = vsync_options.get_item_text(vsync_options.selected)
	var vsync_val: DisplayServer.VSyncMode = VSYNC_MODES[vsync_text] as DisplayServer.VSyncMode
	DisplayServer.window_set_vsync_mode(vsync_val)

	var fsr_scale: float = FSR_MODES[fsr_options.get_item_text(fsr_options.selected)] as float
	var aa_settings: Dictionary = AA_MODES[aa_options.get_item_text(aa_options.selected)]
	var shadow_key: String = shadow_options.get_item_text(shadow_options.selected)
	var shadow_data: Dictionary = SHADOW_QUALITIES[shadow_key]
	var shadow_atlas: int = shadow_data["atlas_size"] as int
	var mesh_lod_val: float = mesh_lod_slider.value as float
	var debanding_val: bool = debanding_checkbox.button_pressed

	var aniso_key: String = anisotropy_options.get_item_text(anisotropy_options.selected)
	var aniso_val: int = ANISOTROPY_LEVELS.get(aniso_key, 2) as int
	ProjectSettings.set_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", aniso_val
	)

	var target_viewports: Array[Viewport] = [get_viewport()]
	var diorama_vp: SubViewport = (
		get_tree().root.find_child("DioramaViewport", true, false) as SubViewport
	)
	if is_instance_valid(diorama_vp) and diorama_vp not in target_viewports:
		target_viewports.append(diorama_vp)

	var primary_msaa: Viewport.MSAA = aa_settings["msaa"] as Viewport.MSAA

	for vp: Viewport in target_viewports:
		if fsr_scale >= 1.0:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.use_taa = false

		vp.scaling_3d_scale = fsr_scale

		if vp is SubViewport:
			vp.msaa_3d = _clamp_preview_msaa(primary_msaa)
		else:
			vp.msaa_3d = primary_msaa

		vp.screen_space_aa = aa_settings["fxaa"] as Viewport.ScreenSpaceAA
		vp.use_debanding = debanding_val
		vp.mesh_lod_threshold = mesh_lod_val

		if vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
			vp.use_taa = aa_settings["taa"] as bool

		vp.positional_shadow_atlas_size = shadow_atlas
		_apply_environment_settings(vp)


## Clamps high MSAA modes for preview and secondary [SubViewport] instances to
## protect render throughput and maintain the 60 FPS target.
## [param requested_msaa] The target [enum Viewport.MSAA] configured by the player.
## Returns a bounded [enum Viewport.MSAA] value no higher than [constant Viewport.MSAA_2X].
func _clamp_preview_msaa(requested_msaa: Viewport.MSAA) -> Viewport.MSAA:
	print("Engine: Clamping preview viewport MSAA to ensure 60 FPS headroom.")
	if requested_msaa > Viewport.MSAA_2X:
		return Viewport.MSAA_2X
	return requested_msaa


## Fetches and modifies the active [Environment] and synchronizes AgX shader state.
## [param vp] The target viewport to extract and modify the environment from.
func _apply_environment_settings(vp: Viewport) -> void:
	print("Engine: Updating environment settings for viewport.")
	var env: Environment = null
	if vp.find_world_3d():
		var world: World3D = vp.find_world_3d()
		if world.environment:
			env = world.environment
		elif world.fallback_environment:
			env = world.fallback_environment

	var tonemap_key: String = tonemap_options.get_item_text(tonemap_options.selected)
	var is_agx: bool = tonemap_key == "AgX"
	var is_agx_punchy: bool = tonemap_key == "AgX (Punchy)"

	if env:
		if is_agx or is_agx_punchy:
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		else:
			match tonemap_key:
				"Linear":
					env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
				"Reinhard":
					env.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
				"Filmic":
					env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
				"ACES":
					env.tonemap_mode = Environment.TONE_MAPPER_ACES

		env.ssao_enabled = ssao_checkbox.button_pressed
		env.ssil_enabled = ssi_checkbox.button_pressed
		env.ssr_enabled = ssr_checkbox.button_pressed
		env.sdfgi_enabled = sdfgi_checkbox.button_pressed
		env.volumetric_fog_enabled = fog_checkbox.button_pressed
		env.glow_enabled = glow_checkbox.button_pressed

	var vision_mesh: MeshInstance3D = (
		vp.find_child("VisionAssistMesh", true, false) as MeshInstance3D
	)
	if is_instance_valid(vision_mesh):
		var mat: ShaderMaterial = vision_mesh.get_surface_override_material(0) as ShaderMaterial
		if not is_instance_valid(mat):
			mat = vision_mesh.material_override as ShaderMaterial

		if is_instance_valid(mat):
			var is_va_enabled: bool = (
				GlobalSettings.get_setting("VisionAssist", "enabled", false) as bool
			)
			if is_va_enabled:
				var va_mode: int = GlobalSettings.get_setting("VisionAssist", "mode", 1) as int
				mat.set_shader_parameter("mode", va_mode)
				vision_mesh.visible = true
			elif is_agx:
				mat.set_shader_parameter("mode", 5)
				vision_mesh.visible = true
			elif is_agx_punchy:
				mat.set_shader_parameter("mode", 6)
				vision_mesh.visible = true
			else:
				mat.set_shader_parameter("mode", 7)
				vision_mesh.visible = false


## Prompts the user to restart the game when switching GPU adapters.
## [param index] Index of the selected GPU option.
func _on_gpu_selected(index: int) -> void:
	var label_text: String = gpu_options.get_item_text(index)
	_pending_gpu_index = _available_gpus.get(label_text, 0) as int
	print("UI: User selected GPU adapter index: ", _pending_gpu_index)
	restart_dialog.dialog_text = (
		"Switching GPU adapter to '"
		+ label_text
		+ "' requires restarting the application.\n\nRestart now?"
	)
	restart_dialog.popup_centered()


## Prompts the user to restart the game when changing rendering drivers.
## [param index] Index of the selected renderer.
func _on_renderer_selected(index: int) -> void:
	var label_text: String = renderer_options.get_item_text(index)
	_pending_renderer = RENDERER_MODES[label_text] as String
	print("UI: Requesting backend driver swap to: ", _pending_renderer)
	restart_dialog.dialog_text = (
		"Changing the rendering engine to '"
		+ label_text
		+ "' requires restarting the game.\n\nRestart now?"
	)
	restart_dialog.popup_centered()


## Confirms the restart request, persists options, and restarts the engine.
func _on_restart_dialog_confirmed() -> void:
	print("Engine: Persisting restart parameters and restarting.")
	var restart_args: Array[String] = []

	if not _pending_renderer.is_empty():
		GlobalSettings.save_setting("Settings", "renderer", _pending_renderer)
		var driver_val: String = "opengl3" if _pending_renderer == "gl_compatibility" else "vulkan"
		restart_args.append("--rendering-driver")
		restart_args.append(driver_val)

	if _pending_gpu_index >= 0:
		GlobalSettings.save_setting("Settings", "gpu_adapter_index", _pending_gpu_index)
		ProjectSettings.set_setting("rendering/vulkan/rendering_device/device", _pending_gpu_index)
		restart_args.append("--gpu-index")
		restart_args.append(str(_pending_gpu_index))

	OS.set_restart_on_exit(true, PackedStringArray(restart_args))
	get_tree().quit()


## Triggers the [GraphicsManager] automated 60 FPS benchmark run.
func _on_auto_tune_pressed() -> void:
	print("UI: Starting automated 60 FPS benchmark pass.")
	auto_tune_button.disabled = true
	auto_tune_button.text = "Benchmarking..."
	if has_node("/root/GraphicsManager"):
		var manager: Node = get_node("/root/GraphicsManager")
		manager.call("run_benchmark_for_60fps")


## Refreshes the options interface once the benchmark completes.
## [param _optimal_level] The finalized optimization tier index.
func _on_benchmark_completed(_optimal_level: int) -> void:
	print("UI: Benchmark complete. Synchronizing UI to calculated settings.")
	auto_tune_button.disabled = false
	auto_tune_button.text = "Auto-Tune for 60 FPS"
	_load_video_settings()


## Applies preset graphics levels across all individual toggle settings.
## [param index] Index of the selected preset.
func _on_preset_selected(index: int) -> void:
	var preset: String = preset_options.get_item_text(index)
	print("UI: Player selected Graphics Preset: ", preset)
	GlobalSettings.save_setting("Settings", "preset", preset)

	match preset:
		"Low":
			_update_ui_and_save(shadow_options, "Low (Fast)", "shadow_quality")
			ssao_checkbox.button_pressed = false
			ssi_checkbox.button_pressed = false
			ssr_checkbox.button_pressed = false
			sdfgi_checkbox.button_pressed = false
			fog_checkbox.button_pressed = false
			glow_checkbox.button_pressed = false
			mesh_lod_slider.value = 2.0
			GlobalSettings.save_setting("Settings", "ssao", false)
			GlobalSettings.save_setting("Settings", "ssi", false)
			GlobalSettings.save_setting("Settings", "ssr", false)
			GlobalSettings.save_setting("Settings", "sdfgi", false)
			GlobalSettings.save_setting("Settings", "volumetric_fog", false)
			GlobalSettings.save_setting("Settings", "glow", false)
			GlobalSettings.save_setting("Settings", "mesh_lod_threshold", 2.0)
		"Medium":
			_update_ui_and_save(shadow_options, "Medium", "shadow_quality")
			ssao_checkbox.button_pressed = true
			ssi_checkbox.button_pressed = false
			ssr_checkbox.button_pressed = false
			sdfgi_checkbox.button_pressed = false
			fog_checkbox.button_pressed = false
			glow_checkbox.button_pressed = true
			mesh_lod_slider.value = 1.5
			GlobalSettings.save_setting("Settings", "ssao", true)
			GlobalSettings.save_setting("Settings", "ssi", false)
			GlobalSettings.save_setting("Settings", "ssr", false)
			GlobalSettings.save_setting("Settings", "sdfgi", false)
			GlobalSettings.save_setting("Settings", "volumetric_fog", false)
			GlobalSettings.save_setting("Settings", "glow", true)
			GlobalSettings.save_setting("Settings", "mesh_lod_threshold", 1.5)
		"High":
			_update_ui_and_save(shadow_options, "High (Smooth)", "shadow_quality")
			ssao_checkbox.button_pressed = true
			ssi_checkbox.button_pressed = true
			ssr_checkbox.button_pressed = true
			sdfgi_checkbox.button_pressed = true
			fog_checkbox.button_pressed = false
			glow_checkbox.button_pressed = true
			mesh_lod_slider.value = 1.0
			GlobalSettings.save_setting("Settings", "ssao", true)
			GlobalSettings.save_setting("Settings", "ssi", true)
			GlobalSettings.save_setting("Settings", "ssr", true)
			GlobalSettings.save_setting("Settings", "sdfgi", true)
			GlobalSettings.save_setting("Settings", "volumetric_fog", false)
			GlobalSettings.save_setting("Settings", "glow", true)
			GlobalSettings.save_setting("Settings", "mesh_lod_threshold", 1.0)
		"Ultra":
			_update_ui_and_save(shadow_options, "High (Smooth)", "shadow_quality")
			ssao_checkbox.button_pressed = true
			ssi_checkbox.button_pressed = true
			ssr_checkbox.button_pressed = true
			sdfgi_checkbox.button_pressed = true
			fog_checkbox.button_pressed = true
			glow_checkbox.button_pressed = true
			mesh_lod_slider.value = 0.5
			GlobalSettings.save_setting("Settings", "ssao", true)
			GlobalSettings.save_setting("Settings", "ssi", true)
			GlobalSettings.save_setting("Settings", "ssr", true)
			GlobalSettings.save_setting("Settings", "sdfgi", true)
			GlobalSettings.save_setting("Settings", "volumetric_fog", true)
			GlobalSettings.save_setting("Settings", "glow", true)
			GlobalSettings.save_setting("Settings", "mesh_lod_threshold", 0.5)

	_apply_all_current_settings()


## Helper to select an option and save it directly to settings.
## [param dropdown] The option button to select within.
## [param target_key] The item string to find and select.
## [param setting_name] Key name in the settings backend.
func _update_ui_and_save(dropdown: OptionButton, target_key: String, setting_name: String) -> void:
	print("UI: Automatically updating settings array map and disk.")
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_key:
			dropdown.select(i)
			GlobalSettings.save_setting("Settings", setting_name, target_key)
			break


## Handles tonemap algorithm selection.
## [param index] Item index selected.
func _on_tonemap_selected(index: int) -> void:
	var key: String = tonemap_options.get_item_text(index)
	print("UI: Tonemapping algorithm selected: ", key)
	GlobalSettings.save_setting("Settings", "tonemap_mode", key)
	_apply_all_current_settings()


## Handles anisotropic filtering level changes.
## [param index] Item index selected.
func _on_anisotropy_selected(index: int) -> void:
	var key: String = anisotropy_options.get_item_text(index)
	var level: int = ANISOTROPY_LEVELS[key] as int
	print("UI: Anisotropic filtering level set to: ", key)
	ProjectSettings.set_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", level
	)
	GlobalSettings.save_setting("Settings", "anisotropy", key)
	_apply_all_current_settings()


## Handles mesh Level of Detail (LOD) threshold changes from [member mesh_lod_slider].
## [param value] The new LOD threshold floating-point scale.
func _on_mesh_lod_changed(value: float) -> void:
	print("UI: Mesh LOD slider value changed: ", value)
	var rounded_val: float = snappedf(value, 0.01)
	if mesh_lod_line.text != str(rounded_val):
		mesh_lod_line.text = str(rounded_val)
	GlobalSettings.save_setting("Settings", "mesh_lod_threshold", rounded_val)
	_apply_all_current_settings()


## Handles direct numerical input committed in [member mesh_lod_line].
## [param new_text] The text submitted in the input field.
func _on_mesh_lod_text_submitted(new_text: String) -> void:
	print("UI: Mesh LOD text input submitted: ", new_text)
	_parse_and_apply_lod_text(new_text)


## Sanitizes and synchronizes [member mesh_lod_line] input when user leaves the field.
func _on_mesh_lod_focus_exited() -> void:
	print("UI: Mesh LOD line edit focus exited.")
	_parse_and_apply_lod_text(mesh_lod_line.text)


## Validates, clamps, and synchronizes numerical LOD input with [member mesh_lod_slider].
## [param input_text] The raw string value to validate and apply.
func _parse_and_apply_lod_text(input_text: String) -> void:
	print("UI: Parsing Mesh LOD input: ", input_text)
	var val: float = input_text.to_float()
	val = clampf(val, mesh_lod_slider.min_value, mesh_lod_slider.max_value)
	mesh_lod_slider.value = val
	mesh_lod_line.text = str(snappedf(val, 0.01))


## Handles debanding toggle changes.
## [param toggled_on] Whether debanding is enabled.
func _on_debanding_toggled(toggled_on: bool) -> void:
	print("UI: Color debanding toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "debanding", toggled_on)
	_apply_all_current_settings()


## Handles Screen Space Indirect Lighting (SSIL) toggle changes.
## [param toggled_on] Whether SSIL is enabled.
func _on_ssi_toggled(toggled_on: bool) -> void:
	print("UI: Screen Space Indirect Lighting toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "ssi", toggled_on)
	_apply_all_current_settings()


## Handles display mode changes.
## [param index] Item index selected.
func _on_display_selected(index: int) -> void:
	print("UI: Display mode selection made.")
	var key: String = display_options.get_item_text(index)
	var mode: DisplayServer.WindowMode = DISPLAY_MODES[key] as DisplayServer.WindowMode
	DisplayServer.window_set_mode(mode)
	GlobalSettings.save_setting("Settings", "display_mode", mode as int)


## Handles monitor display switching.
## [param index] Item index selected.
func _on_monitor_selected(index: int) -> void:
	print("UI: Monitor selection changed: ", index)
	get_window().current_screen = index
	GlobalSettings.save_setting("Settings", "screen_index", index)


## Handles resolution changes.
## [param index] Item index selected.
func _on_resolution_selected(index: int) -> void:
	print("UI: Resolution target altered.")
	var key: String = resolution_options.get_item_text(index)
	var new_size: Vector2i = RESOLUTIONS[key] as Vector2i
	get_window().content_scale_size = new_size
	if not get_window().is_embedded() and get_window().mode == Window.MODE_WINDOWED:
		get_window().size = new_size
	GlobalSettings.save_setting("Settings", "resolution_x", new_size.x)
	GlobalSettings.save_setting("Settings", "resolution_y", new_size.y)


## Handles maximum FPS limit changes.
## [param index] Item index selected.
func _on_fps_selected(index: int) -> void:
	print("UI: Framerate limit cap selection made.")
	var limit: int = FPS_LIMITS[fps_options.get_item_text(index)] as int
	Engine.max_fps = limit
	GlobalSettings.save_setting("Settings", "fps_limit", limit)


## Handles VSync mode changes.
## [param index] Item index selected.
func _on_vsync_selected(index: int) -> void:
	print("UI: Player toggled V-Sync mode options.")
	var key: String = vsync_options.get_item_text(index)
	var vsync_val: DisplayServer.VSyncMode = VSYNC_MODES[key] as DisplayServer.VSyncMode
	DisplayServer.window_set_vsync_mode(vsync_val)
	GlobalSettings.save_setting("Settings", "vsync_mode", vsync_val as int)


## Handles FSR scaling changes.
## [param index] Item index selected.
func _on_fsr_selected(index: int) -> void:
	print("UI: FidelityFX scaling options changed.")
	var key: String = fsr_options.get_item_text(index)
	GlobalSettings.save_setting("Settings", "fsr_mode", key)
	_apply_all_current_settings()


## Handles anti-aliasing configuration changes.
## [param index] Item index selected.
func _on_aa_selected(index: int) -> void:
	print("UI: Anti-Aliasing options altered.")
	var key: String = aa_options.get_item_text(index)
	GlobalSettings.save_setting("Settings", "aa_mode", key)
	_apply_all_current_settings()


## Handles shadow quality changes.
## [param index] Item index selected.
func _on_shadow_selected(index: int) -> void:
	print("UI: Positional shadows atlas size map adjusted.")
	var key: String = shadow_options.get_item_text(index)
	GlobalSettings.save_setting("Settings", "shadow_quality", key)
	_apply_all_current_settings()


## Handles SSAO toggle changes.
## [param toggled_on] Whether SSAO is enabled.
func _on_ssao_toggled(toggled_on: bool) -> void:
	print("UI: Screen Space Ambient Occlusion toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "ssao", toggled_on)
	_apply_all_current_settings()


## Handles SSR toggle changes.
## [param toggled_on] Whether SSR is enabled.
func _on_ssr_toggled(toggled_on: bool) -> void:
	print("UI: Screen Space Reflections toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "ssr", toggled_on)
	_apply_all_current_settings()


## Handles SDFGI toggle changes.
## [param toggled_on] Whether SDFGI is enabled.
func _on_sdfgi_toggled(toggled_on: bool) -> void:
	print("UI: Signed Distance Field Global Illumination toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "sdfgi", toggled_on)
	_apply_all_current_settings()


## Handles Volumetric Fog toggle changes.
## [param toggled_on] Whether Volumetric Fog is enabled.
func _on_fog_toggled(toggled_on: bool) -> void:
	print("UI: Volumetric Fog toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "volumetric_fog", toggled_on)
	_apply_all_current_settings()


## Handles Glow / Bloom toggle changes.
## [param toggled_on] Whether Glow is enabled.
func _on_glow_toggled(toggled_on: bool) -> void:
	print("UI: Glow effect toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "glow", toggled_on)
	_apply_all_current_settings()
