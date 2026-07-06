extends Panel

const DEFAULT_FPS: int = 60
const DEFAULT_FSR_MODE: String = "Disabled (Native)"
const DEFAULT_AA_MODE: String = "Disabled"
const DEFAULT_VSYNC: DisplayServer.VSyncMode = DisplayServer.VSYNC_ENABLED

const RESOLUTIONS: Dictionary = {
	"1920 x 1080": Vector2i(1920, 1080),
	"1600 x 900": Vector2i(1600, 900),
	"1280 x 720": Vector2i(1280, 720)
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

# --- UNIFIED ANTI-ALIASING SYSTEM ---
const AA_MODES: Dictionary = {
	"Disabled": {
		"msaa": Viewport.MSAA_DISABLED, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"FXAA (Fast)": {
		"msaa": Viewport.MSAA_DISABLED, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_FXAA
	},
	"TAA (Smooth)": {
		"msaa": Viewport.MSAA_DISABLED, 
		"taa": true, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 2x": {
		"msaa": Viewport.MSAA_2X, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 4x": {
		"msaa": Viewport.MSAA_4X, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 8x (Heavy)": {
		"msaa": Viewport.MSAA_8X, 
		"taa": false, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 2x + TAA (High)": {
		"msaa": Viewport.MSAA_2X, 
		"taa": true, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	},
	"MSAA 4x + TAA (Ultra)": {
		"msaa": Viewport.MSAA_4X, 
		"taa": true, 
		"fxaa": Viewport.SCREEN_SPACE_AA_DISABLED
	}
}

@onready var resolution_options: OptionButton = %ResolutionOptionButton
@onready var fps_options: OptionButton = %FPSOptionButton
@onready var vsync_options: OptionButton = %VSyncOptionButton
@onready var fsr_options: OptionButton = %FSROptionButton
@onready var aa_options: OptionButton = %AAOptionButton

func _ready() -> void:
	print("UI: Video Panel initialized.")
	_populate_dropdowns()
	
	resolution_options.item_selected.connect(_on_resolution_selected)
	fps_options.item_selected.connect(_on_fps_selected)
	vsync_options.item_selected.connect(_on_vsync_selected)
	fsr_options.item_selected.connect(_on_fsr_selected)
	aa_options.item_selected.connect(_on_aa_selected)
	
	_load_video_settings()

func _populate_dropdowns() -> void:
	print("UI: Populating Video Dropdowns.")
	for res: String in RESOLUTIONS.keys(): 
		resolution_options.add_item(res)
	for fps: String in FPS_LIMITS.keys(): 
		fps_options.add_item(fps)
	for vsync: String in VSYNC_MODES.keys(): 
		vsync_options.add_item(vsync)
	for fsr: String in FSR_MODES.keys(): 
		fsr_options.add_item(fsr)
	for aa: String in AA_MODES.keys(): 
		aa_options.add_item(aa)

func _load_video_settings() -> void:
	print("UI: Loading video data from GlobalSettings.")
	var saved_fps: int = GlobalSettings.get_setting("Settings", "fps_limit", DEFAULT_FPS)
	for i: int in range(fps_options.get_item_count()):
		if FPS_LIMITS[fps_options.get_item_text(i)] == saved_fps:
			fps_options.select(i)
			break
			
	var saved_vsync: int = GlobalSettings.get_setting("Settings", "vsync_mode", DEFAULT_VSYNC)
	for i: int in range(vsync_options.get_item_count()):
		if VSYNC_MODES[vsync_options.get_item_text(i)] == saved_vsync:
			vsync_options.select(i)
			break

	var saved_fsr: String = GlobalSettings.get_setting("Settings", "fsr_mode", DEFAULT_FSR_MODE)
	for i: int in range(fsr_options.get_item_count()):
		if fsr_options.get_item_text(i) == saved_fsr:
			fsr_options.select(i)
			break
			
	var saved_aa: String = GlobalSettings.get_setting("Settings", "aa_mode", DEFAULT_AA_MODE)
	for i: int in range(aa_options.get_item_count()):
		if aa_options.get_item_text(i) == saved_aa:
			aa_options.select(i)
			break

	_apply_video_settings(saved_fps, saved_vsync as DisplayServer.VSyncMode, saved_fsr, saved_aa)

func _apply_video_settings(fps: int, vsync: DisplayServer.VSyncMode, fsr: String, aa: String) -> void:
	print("Engine: Applying video and rendering settings.")
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(vsync)
	
	var current_viewport: Viewport = get_viewport()
	var fsr_scale: float = FSR_MODES[fsr]
	
	if fsr_scale >= 1.0:
		current_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	else:
		current_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		current_viewport.use_taa = false
	current_viewport.scaling_3d_scale = fsr_scale

	var aa_settings: Dictionary = AA_MODES[aa]
	current_viewport.msaa_3d = aa_settings["msaa"] as Viewport.MSAA
	current_viewport.screen_space_aa = aa_settings["fxaa"] as Viewport.ScreenSpaceAA
	if current_viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
		current_viewport.use_taa = aa_settings["taa"] as bool

func _on_resolution_selected(index: int) -> void:
	var key: String = resolution_options.get_item_text(index)
	var new_size: Vector2i = RESOLUTIONS[key]
	print("Player selected resolution: ", key)
	get_window().content_scale_size = new_size
	if not get_window().is_embedded() and get_window().mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
		get_window().size = new_size
	GlobalSettings.save_setting("Settings", "resolution_x", new_size.x)
	GlobalSettings.save_setting("Settings", "resolution_y", new_size.y)

func _on_fps_selected(index: int) -> void:
	var limit: int = FPS_LIMITS[fps_options.get_item_text(index)]
	print("Player changed FPS limit to: ", limit)
	Engine.max_fps = limit
	GlobalSettings.save_setting("Settings", "fps_limit", limit)

func _on_vsync_selected(index: int) -> void:
	var mode: DisplayServer.VSyncMode = VSYNC_MODES[vsync_options.get_item_text(index)]
	print("Player changed VSync to: ", mode)
	DisplayServer.window_set_vsync_mode(mode)
	GlobalSettings.save_setting("Settings", "vsync_mode", mode)

func _on_fsr_selected(index: int) -> void:
	var key: String = fsr_options.get_item_text(index)
	print("Player changed FSR to: ", key)
	GlobalSettings.save_setting("Settings", "fsr_mode", key)
	_load_video_settings()

func _on_aa_selected(index: int) -> void:
	var key: String = aa_options.get_item_text(index)
	print("Player changed Anti-Aliasing to: ", key)
	GlobalSettings.save_setting("Settings", "aa_mode", key)
	_load_video_settings()
