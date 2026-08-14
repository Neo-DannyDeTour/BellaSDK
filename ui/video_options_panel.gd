extends Panel

## Manages the video settings UI and synchronizes visual state with the backend.

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

const DISPLAY_MODES: Dictionary = {
	"Fullscreen": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	"Borderless Windowed": DisplayServer.WINDOW_MODE_FULLSCREEN,
	"Windowed": DisplayServer.WINDOW_MODE_WINDOWED
}

const RESOLUTIONS: Dictionary = {
	"1920 x 1080": Vector2i(1920, 1080),
	"1600 x 900": Vector2i(1600, 900),
	"1366 x 768": Vector2i(1366, 768),
	"1280 x 720": Vector2i(1280, 720),
	"1024 x 768": Vector2i(1024, 768),
	"800 x 600": Vector2i(800, 600),
	"640 x 480": Vector2i(640, 480)
}

const FPS_LIMITS: Dictionary = {
	"30 FPS": 30, "60 FPS": 60, "120 FPS": 120, "144 FPS": 144, "Unlimited": 0
}

const VSYNC_MODES: Dictionary = {
	"Enabled": DisplayServer.VSYNC_ENABLED,
	"Disabled": DisplayServer.VSYNC_DISABLED,
	"Adaptive": DisplayServer.VSYNC_ADAPTIVE
}

const FSR_MODES: Dictionary = {
	"Disabled (Native)": 1.0, "Quality": 0.77, "Balanced": 0.59, "Performance": 0.50
}

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

const SHADOW_QUALITIES: Dictionary = {
	"Off": {"atlas_size": 0, "filter": 0},
	"Low (Fast)": {"atlas_size": 1024, "filter": 0},
	"Medium": {"atlas_size": 2048, "filter": 1},
	"High (Smooth)": {"atlas_size": 4096, "filter": 2}
}

## UI Node References
@onready var user_mode_btn: Button = %UserModeButton
@onready var optimize_mode_btn: Button = %OptimizeModeButton

@onready var display_options: OptionButton = %DisplayOptionButton
@onready var resolution_options: OptionButton = %ResolutionOptionButton
@onready var fps_options: OptionButton = %FPSOptionButton
@onready var vsync_options: OptionButton = %VSyncOptionButton
@onready var fsr_options: OptionButton = %FSROptionButton
@onready var aa_options: OptionButton = %AAOptionButton
@onready var preset_options: OptionButton = %PresetOptionButton
@onready var shadow_options: OptionButton = %ShadowOptionButton
@onready var ssao_checkbox: CheckBox = %SSAOCheckBox
@onready var ssr_checkbox: CheckBox = %SSRCheckBox
@onready var sdfgi_checkbox: CheckBox = %SDFGICheckBox


func _ready() -> void:
	print("UI: Video Panel initialized.")
	_populate_all_dropdowns()
	_connect_signals()
	_load_video_settings()

	if GraphicsManager.has_signal("profile_mode_changed"):
		GraphicsManager.profile_mode_changed.connect(_on_profile_mode_changed)

	if GraphicsManager.has_signal("performance_profile_adjusted"):
		GraphicsManager.performance_profile_adjusted.connect(_on_performance_adjusted)

	_on_profile_mode_changed(GraphicsManager.is_auto_optimizing)


func _connect_signals() -> void:
	print("UI: Connecting video option signals.")
	user_mode_btn.pressed.connect(_on_user_mode_pressed)
	optimize_mode_btn.pressed.connect(_on_optimize_mode_pressed)

	display_options.item_selected.connect(_on_display_selected)
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)
	vsync_options.item_selected.connect(_on_vsync_selected)
	fsr_options.item_selected.connect(_on_fsr_selected)
	aa_options.item_selected.connect(_on_aa_selected)
	shadow_options.item_selected.connect(_on_shadow_selected)
	preset_options.item_selected.connect(_on_preset_selected)

	ssao_checkbox.toggled.connect(_on_ssao_toggled)
	ssr_checkbox.toggled.connect(_on_ssr_toggled)
	sdfgi_checkbox.toggled.connect(_on_sdfgi_toggled)


func _on_user_mode_pressed() -> void:
	print("UI: Player requested User Settings mode. Restoring saved user config.")
	GraphicsManager.enable_user_mode()
	_load_video_settings()


func _on_optimize_mode_pressed() -> void:
	print("UI: Player requested Auto 60 FPS mode.")
	GraphicsManager.enable_auto_mode()
	_sync_ui_to_live_engine_state()


func _on_profile_mode_changed(is_optimized: bool) -> void:
	print("UI: Toggling UI lock state. Auto-optimized: ", is_optimized)

	user_mode_btn.disabled = not is_optimized
	optimize_mode_btn.disabled = is_optimized

	var controls: Array[BaseButton] = [
		display_options,
		resolution_options,
		fps_options,
		vsync_options,
		fsr_options,
		aa_options,
		preset_options,
		shadow_options,
		ssao_checkbox,
		ssr_checkbox,
		sdfgi_checkbox
	]

	for control: BaseButton in controls:
		control.disabled = is_optimized

	if is_optimized:
		_sync_ui_to_live_engine_state()


func _on_performance_adjusted(_level: int) -> void:
	print("UI: Performance adjusted signal received. Updating interface elements.")
	if GraphicsManager.is_auto_optimizing:
		_sync_ui_to_live_engine_state()


func _sync_ui_to_live_engine_state() -> void:
	print("UI: Syncing visual widgets to reflect current engine downgrades.")
	var vp: Viewport = get_viewport()

	if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2:
		if vp.scaling_3d_scale <= 0.51:
			_select_dropdown_by_text(fsr_options, "Performance")
	else:
		_select_dropdown_by_text(fsr_options, "Disabled (Native)")

	if vp.msaa_3d == Viewport.MSAA_DISABLED:
		if vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA:
			_select_dropdown_by_text(aa_options, "FXAA (Fast)")
		elif vp.use_taa:
			_select_dropdown_by_text(aa_options, "TAA (Smooth)")
		else:
			_select_dropdown_by_text(aa_options, "Disabled")

	if vp.positional_shadow_atlas_size == 0:
		_select_dropdown_by_text(shadow_options, "Off")
	elif vp.positional_shadow_atlas_size <= 1024:
		_select_dropdown_by_text(shadow_options, "Low (Fast)")

	var win: Window = vp as Window
	if win and not win.is_embedded():
		var res_str: String = str(win.size.x) + " x " + str(win.size.y)
		_select_dropdown_by_text(resolution_options, res_str)

	var env: Environment = null
	if vp.find_world_3d():
		var world: World3D = vp.find_world_3d()
		if world.environment:
			env = world.environment
		elif world.fallback_environment:
			env = world.fallback_environment

	if env:
		ssao_checkbox.set_pressed_no_signal(env.ssao_enabled)
		ssr_checkbox.set_pressed_no_signal(env.ssr_enabled)
		sdfgi_checkbox.set_pressed_no_signal(env.sdfgi_enabled)


func _select_dropdown_by_text(dropdown: OptionButton, target_text: String) -> void:
	print("UI: Selecting dropdown text dynamically: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


func _populate_all_dropdowns() -> void:
	print("UI: Populating Video Dropdowns dynamically.")
	_fill_dropdown(display_options, DISPLAY_MODES)
	_fill_dropdown(resolution_options, RESOLUTIONS)
	_fill_dropdown(fps_options, FPS_LIMITS)
	_fill_dropdown(vsync_options, VSYNC_MODES)
	_fill_dropdown(fsr_options, FSR_MODES)
	_fill_dropdown(aa_options, AA_MODES)
	_fill_dropdown(shadow_options, SHADOW_QUALITIES)

	preset_options.add_item("Low")
	preset_options.add_item("Medium")
	preset_options.add_item("High")
	preset_options.add_item("Ultra")


func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("UI: Clearing and refilling individual dropdown.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


func _load_video_settings() -> void:
	print("UI: Loading video data from GlobalSettings.")
	_sync_dropdown_to_setting(display_options, DISPLAY_MODES, "display_mode", DEFAULT_DISPLAY)
	_sync_dropdown_to_setting(fps_options, FPS_LIMITS, "fps_limit", DEFAULT_FPS)
	_sync_dropdown_to_setting(vsync_options, VSYNC_MODES, "vsync_mode", DEFAULT_VSYNC)
	_sync_dropdown_to_setting(fsr_options, FSR_MODES, "fsr_mode", DEFAULT_FSR_MODE)
	_sync_dropdown_to_setting(aa_options, AA_MODES, "aa_mode", DEFAULT_AA_MODE)
	_sync_dropdown_to_setting(shadow_options, SHADOW_QUALITIES, "shadow_quality", "High (Smooth)")

	var res_x: int = GlobalSettings.get_setting("Settings", "resolution_x", 1920) as int
	var res_y: int = GlobalSettings.get_setting("Settings", "resolution_y", 1080) as int
	var res_string: String = str(res_x) + " x " + str(res_y)
	_select_dropdown_by_text(resolution_options, res_string)

	ssao_checkbox.button_pressed = GlobalSettings.get_setting("Settings", "ssao", true) as bool
	ssr_checkbox.button_pressed = GlobalSettings.get_setting("Settings", "ssr", false) as bool
	sdfgi_checkbox.button_pressed = GlobalSettings.get_setting("Settings", "sdfgi", true) as bool

	_apply_all_current_settings()


func _sync_dropdown_to_setting(
	dropdown: OptionButton, dict: Dictionary, setting_key: String, default_val: Variant
) -> void:
	print("UI: Syncing dropdown dictionary index to saved file selection.")
	var saved_val: Variant = GlobalSettings.get_setting("Settings", setting_key, default_val)
	for i: int in range(dropdown.get_item_count()) -> void:
		var item_text: String = dropdown.get_item_text(i)
		if typeof(saved_val) == TYPE_STRING:
			if item_text == str(saved_val):
				dropdown.select(i)
				return
		else:
			if dict.has(item_text) and dict[item_text] == saved_val:
				dropdown.select(i)
				return


func _apply_all_current_settings() -> void:
	print("Engine: Applying all saved video and rendering settings.")
	var mode: DisplayServer.WindowMode = (
		DISPLAY_MODES[display_options.get_item_text(display_options.selected)]
		as DisplayServer.WindowMode
	)
	DisplayServer.window_set_mode(mode)

	var res_key: String = resolution_options.get_item_text(resolution_options.selected)
	var new_size: Vector2i = RESOLUTIONS.get(res_key, Vector2i(1920, 1080)) as Vector2i
	get_window().content_scale_size = new_size
	if not get_window().is_embedded() and get_window().mode == Window.MODE_WINDOWED:
		get_window().size = new_size

	Engine.max_fps = FPS_LIMITS[fps_options.get_item_text(fps_options.selected)] as int

	var vsync: DisplayServer.VSyncMode = (
		VSYNC_MODES[vsync_options.get_item_text(vsync_options.selected)] as DisplayServer.VSyncMode
	)
	DisplayServer.window_set_vsync_mode(vsync)

	var current_viewport: Viewport = get_viewport()
	var fsr_scale: float = FSR_MODES[fsr_options.get_item_text(fsr_options.selected)] as float
	var aa_settings: Dictionary = AA_MODES[aa_options.get_item_text(aa_options.selected)]

	if fsr_scale >= 1.0:
		current_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		current_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		current_viewport.use_taa = false

	current_viewport.scaling_3d_scale = fsr_scale
	current_viewport.msaa_3d = aa_settings["msaa"] as Viewport.MSAA
	current_viewport.screen_space_aa = aa_settings["fxaa"] as Viewport.ScreenSpaceAA

	if current_viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
		current_viewport.use_taa = aa_settings["taa"] as bool

	var shadow_key: String = shadow_options.get_item_text(shadow_options.selected)
	var shadow_data: Dictionary = SHADOW_QUALITIES[shadow_key]
	current_viewport.positional_shadow_atlas_size = shadow_data["atlas_size"] as int

	var env: Environment = null
	if current_viewport.find_world_3d():
		var world: World3D = current_viewport.find_world_3d()
		env = world.environment if world.environment else world.fallback_environment

	if env:
		env.ssao_enabled = ssao_checkbox.button_pressed
		env.ssr_enabled = ssr_checkbox.button_pressed
		env.sdfgi_enabled = sdfgi_checkbox.button_pressed


func _on_preset_selected(index: int) -> void:
	var preset: String = preset_options.get_item_text(index)
	print("UI: Player selected Graphics Preset: ", preset)
	match preset:
		"Low":
			_update_ui_and_save(shadow_options, "Low (Fast)", "shadow_quality")
			ssao_checkbox.button_pressed = false
			sdfgi_checkbox.button_pressed = false
			GlobalSettings.save_setting("Settings", "ssao", false)
			GlobalSettings.save_setting("Settings", "sdfgi", false)
		"High":
			_update_ui_and_save(shadow_options, "High (Smooth)", "shadow_quality")
			ssao_checkbox.button_pressed = true
			sdfgi_checkbox.button_pressed = true
			GlobalSettings.save_setting("Settings", "ssao", true)
			GlobalSettings.save_setting("Settings", "sdfgi", true)

	_apply_all_current_settings()


func _update_ui_and_save(dropdown: OptionButton, target_key: String, setting_name: String) -> void:
	print("UI: Automatically updating settings array map and disk.")
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_key:
			dropdown.select(i)
			GlobalSettings.save_setting("Settings", setting_name, target_key)
			break


func _on_display_selected(index: int) -> void:
	print("UI: Display mode selection made.")
	var key: String = display_options.get_item_text(index)
	var mode: DisplayServer.WindowMode = DISPLAY_MODES[key] as DisplayServer.WindowMode
	DisplayServer.window_set_mode(mode)
	GlobalSettings.save_setting("Settings", "display_mode", mode as int)


func _on_resolution_selected(index: int) -> void:
	print("UI: Resolution target altered.")
	var key: String = resolution_options.get_item_text(index)
	var new_size: Vector2i = RESOLUTIONS[key] as Vector2i
	get_window().content_scale_size = new_size
	if not get_window().is_embedded() and get_window().mode == Window.MODE_WINDOWED:
		get_window().size = new_size
	GlobalSettings.save_setting("Settings", "resolution_x", new_size.x)
	GlobalSettings.save_setting("Settings", "resolution_y", new_size.y)


func _on_fps_selected(index: int) -> void:
	print("UI: Framerate limit cap selection made.")
	var limit: int = FPS_LIMITS[fps_options.get_item_text(index)] as int
	Engine.max_fps = limit
	GlobalSettings.save_setting("Settings", "fps_limit", limit)


func _on_vsync_selected(index: int) -> void:
	print("UI: Player toggled V-Sync mode options.")
	var mode: DisplayServer.VSyncMode = (
		VSYNC_MODES[vsync_options.get_item_text(index)] as DisplayServer.VSyncMode
	)
	DisplayServer.window_set_vsync_mode(mode)
	GlobalSettings.save_setting("Settings", "vsync_mode", mode as int)


func _on_fsr_selected(index: int) -> void:
	print("UI: FidelityFX scaling options changed.")
	var key: String = fsr_options.get_item_text(index)
	GlobalSettings.save_setting("Settings", "fsr_mode", key)
	_apply_all_current_settings()


func _on_aa_selected(index: int) -> void:
	print("UI: Anti-Aliasing options altered.")
	var key: String = aa_options.get_item_text(index)
	GlobalSettings.save_setting("Settings", "aa_mode", key)
	_apply_all_current_settings()


func _on_shadow_selected(index: int) -> void:
	print("UI: Positional shadows atlas size map adjusted.")
	var key: String = shadow_options.get_item_text(index)
	GlobalSettings.save_setting("Settings", "shadow_quality", key)
	_apply_all_current_settings()


func _on_ssao_toggled(toggled_on: bool) -> void:
	print("UI: Screen Space Ambient Occlusion toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "ssao", toggled_on)
	_apply_all_current_settings()


func _on_ssr_toggled(toggled_on: bool) -> void:
	print("UI: Screen Space Reflections toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "ssr", toggled_on)
	_apply_all_current_settings()


func _on_sdfgi_toggled(toggled_on: bool) -> void:
	print("UI: Signed Distance Field Global Illumination toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "sdfgi", toggled_on)
	_apply_all_current_settings()
