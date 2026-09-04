## Coordinates sub-panel sections and delegates engine rendering settings execution.
class_name VideoOptions
extends Panel

## Reference to the display sub-section controller [DisplaySection].
@onready var display_section: DisplaySection = %DisplaySection
## Reference to the quality sub-section controller [QualitySection].
@onready var quality_section: QualitySection = %QualitySection
## Reference to the effects sub-section controller [EffectsSection].
@onready var effects_section: EffectsSection = %EffectsSection
## Reference to the hardware sub-section controller [HardwareSection].
@onready var hardware_section: HardwareSection = %HardwareSection
## Reference to the restart confirmation [ConfirmationDialog].
@onready var restart_dialog: ConfirmationDialog = %RestartDialog

## Cached pending rendering method chosen before restarting.
var _pending_renderer: String = ""
## Cached pending GPU adapter index chosen before restarting.
var _pending_gpu_index: int = -1


## Connects section events and triggers initial engine settings dispatch.
func _ready() -> void:
	print("VideoOptions: Main panel coordinator initialized.")
	display_section.display_settings_changed.connect(_apply_all_settings)
	quality_section.quality_settings_changed.connect(_on_quality_settings_changed)
	effects_section.effects_settings_changed.connect(_apply_all_settings)
	hardware_section.restart_required.connect(_on_restart_required)
	hardware_section.auto_tune_requested.connect(_on_auto_tune_requested)
	restart_dialog.confirmed.connect(_on_restart_dialog_confirmed)

	if has_node("/root/GraphicsManager"):
		var manager: Node = get_node("/root/GraphicsManager")
		if manager.has_signal("benchmark_completed"):
			manager.connect("benchmark_completed", _on_benchmark_completed)

	_apply_all_settings()


## Synchronizes preset effects settings when the quality section modifies presets.
func _on_quality_settings_changed() -> void:
	print("VideoOptions: Quality preset changed, synchronizing effects flags.")
	var preset: String = (
		GlobalSettings.get_setting("Settings", "preset", VideoConfig.DEFAULT_PRESET) as String
	)
	if VideoConfig.PRESETS.has(preset):
		var p_data: Dictionary = VideoConfig.PRESETS[preset] as Dictionary
		effects_section.apply_preset_dict(p_data)
		for key: String in p_data.keys():
			if key != "shadow_quality" and key != "mesh_lod_threshold":
				GlobalSettings.save_setting("Settings", key, p_data[key])

	_apply_all_settings()


## Collects active configurations across sections and dispatches to [VideoApplier].
func _apply_all_settings() -> void:
	print("VideoOptions: Dispatching full state payload to VideoApplier.")
	var mode: DisplayServer.WindowMode = (
		GlobalSettings.get_setting("Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY)
		as DisplayServer.WindowMode
	)
	var screen_idx: int = GlobalSettings.get_setting("Settings", "screen_index", 0) as int
	var res: Vector2i = Vector2i(
		GlobalSettings.get_setting("Settings", "resolution_x", 1920) as int,
		GlobalSettings.get_setting("Settings", "resolution_y", 1080) as int
	)
	VideoApplier.apply_window_settings(get_window(), mode, screen_idx, res)

	var vsync: DisplayServer.VSyncMode = (
		GlobalSettings.get_setting("Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC)
		as DisplayServer.VSyncMode
	)
	var fps_cap: int = (
		GlobalSettings.get_setting("Settings", "fps_limit", VideoConfig.DEFAULT_FPS) as int
	)
	VideoApplier.apply_engine_limits(vsync, fps_cap)

	var aniso_key: String = (
		GlobalSettings.get_setting("Settings", "anisotropy", VideoConfig.DEFAULT_ANISOTROPY)
		as String
	)
	var aniso_val: int = VideoConfig.ANISOTROPY_LEVELS.get(aniso_key, 2) as int
	VideoApplier.apply_anisotropy(aniso_val)

	var shadow_key: String = (
		GlobalSettings.get_setting("Settings", "shadow_quality", "High (Smooth)") as String
	)
	var shadow_data: Dictionary = VideoConfig.SHADOW_QUALITIES.get(shadow_key, {}) as Dictionary
	var fsr_key: String = (
		GlobalSettings.get_setting("Settings", "fsr_mode", VideoConfig.DEFAULT_FSR_MODE) as String
	)
	var aa_key: String = (
		GlobalSettings.get_setting("Settings", "aa_mode", VideoConfig.DEFAULT_AA_MODE) as String
	)

	var ssao_key: String = (
		GlobalSettings.get_setting("Settings", "ssao", VideoConfig.DEFAULT_SSAO) as String
	)
	var ssi_key: String = (
		GlobalSettings.get_setting("Settings", "ssi", VideoConfig.DEFAULT_SSI) as String
	)
	var ssr_key: String = (
		GlobalSettings.get_setting("Settings", "ssr", VideoConfig.DEFAULT_SSR) as String
	)
	var sdfgi_key: String = (
		GlobalSettings.get_setting("Settings", "sdfgi", VideoConfig.DEFAULT_SDFGI) as String
	)
	var fog_key: String = (
		GlobalSettings.get_setting("Settings", "volumetric_fog", VideoConfig.DEFAULT_FOG) as String
	)
	var glow_key: String = (
		GlobalSettings.get_setting("Settings", "glow", VideoConfig.DEFAULT_GLOW) as String
	)

	var config: Dictionary = {
		"fsr_scale": VideoConfig.FSR_MODES.get(fsr_key, 1.0) as float,
		"aa_settings": VideoConfig.AA_MODES.get(aa_key, {}) as Dictionary,
		"shadow_atlas": shadow_data.get("atlas_size", 2048) as int,
		"mesh_lod": GlobalSettings.get_setting("Settings", "mesh_lod_threshold", 1.0) as float,
		"debanding": GlobalSettings.get_setting("Settings", "debanding", true) as bool,
		"tonemap_key": GlobalSettings.get_setting("Settings", "tonemap_mode", "Filmic") as String,
		"ssao": VideoConfig.SSAO_MODES.get(ssao_key, {}) as Dictionary,
		"ssi": VideoConfig.SSI_MODES.get(ssi_key, {}) as Dictionary,
		"ssr": VideoConfig.SSR_MODES.get(ssr_key, {}) as Dictionary,
		"sdfgi": VideoConfig.SDFGI_MODES.get(sdfgi_key, {}) as Dictionary,
		"fog": VideoConfig.FOG_MODES.get(fog_key, {}) as Dictionary,
		"glow": VideoConfig.GLOW_MODES.get(glow_key, {}) as Dictionary,
		"ssao_key": ssao_key,
		"ssi_key": ssi_key,
		"ssr_key": ssr_key,
		"sdfgi_key": sdfgi_key,
		"fog_key": fog_key,
		"glow_key": glow_key
	}
	VideoApplier.apply_viewport_pipeline(get_tree(), get_viewport(), config)


## Opens the restart confirmation popup when changing GPU or graphics backend.
## [param msg] Confirmation description text.
## [param rend_key] Selected renderer identifier.
## [param gpu_idx] Selected physical GPU index.
func _on_restart_required(msg: String, rend_key: String, gpu_idx: int) -> void:
	print("VideoOptions: Restart confirmation requested.")
	_pending_renderer = rend_key
	_pending_gpu_index = gpu_idx
	restart_dialog.dialog_text = msg
	restart_dialog.popup_centered()


## Confirms restart, persists pending flags, and relaunches the application.
func _on_restart_dialog_confirmed() -> void:
	print("VideoOptions: Restart confirmed. Persisting launch parameters.")
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


## Dispatches auto-tuning request to the [GraphicsManager] singleton.
func _on_auto_tune_requested() -> void:
	print("VideoOptions: Dispatching 60 FPS benchmark pass.")
	hardware_section.set_benchmark_state(true)
	if has_node("/root/GraphicsManager"):
		var manager: Node = get_node("/root/GraphicsManager")
		manager.call("run_benchmark_for_60fps")


## Restores section widgets once benchmark completes.
## [param _optimal_level] Output benchmark tier index.
func _on_benchmark_completed(_optimal_level: int) -> void:
	print("VideoOptions: Benchmark completed. Refreshing all panels.")
	hardware_section.set_benchmark_state(false)
	display_section.load_settings()
	quality_section.load_settings()
	effects_section.load_settings()
	hardware_section.load_settings()
	_apply_all_settings()
