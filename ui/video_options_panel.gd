## Coordinates video sub-panels and delegates rendering settings in the scene tree.
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


## Connects section events and applies initial video settings on load.
func _ready() -> void:
	print("VideoOptions: Main panel coordinator initialized.")
	if is_instance_valid(restart_dialog):
		restart_dialog.hide()

	visibility_changed.connect(_on_visibility_changed)
	display_section.display_settings_changed.connect(_apply_all_settings)
	quality_section.preset_changed.connect(_on_preset_changed)
	quality_section.quality_settings_changed.connect(_apply_all_settings)
	effects_section.effects_settings_changed.connect(_apply_all_settings)
	hardware_section.restart_required.connect(_on_restart_required)
	hardware_section.auto_tune_requested.connect(_on_auto_tune_requested)
	restart_dialog.confirmed.connect(_on_restart_dialog_confirmed)

	var manager: Node = SystemLocator.get_graphics_manager()
	if is_instance_valid(manager) and manager.has_signal(&"benchmark_completed"):
		var bench_sig: Signal = Signal(manager, &"benchmark_completed")
		if not bench_sig.is_connected(_on_benchmark_completed):
			bench_sig.connect(_on_benchmark_completed)

	if is_visible_in_tree():
		VideoApplier.set_diorama_active(get_tree(), true)
		_apply_all_settings()


## Cleans up diorama rendering when panel exits scene tree.
func _exit_tree() -> void:
	print("VideoOptions: Exiting tree; putting diorama rendering to sleep.")
	VideoApplier.set_diorama_active(get_tree(), false)


## Synchronizes diorama state when panel visibility toggles.
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		print("VideoOptions: Panel became visible. Pushing full state to diorama.")
		VideoApplier.set_diorama_active(get_tree(), true)
		_apply_all_settings()
	else:
		print("VideoOptions: Panel hidden. Putting diorama to sleep.")
		VideoApplier.set_diorama_active(get_tree(), false)


## Updates section settings when master preset selection changes.
## [param preset] The target quality preset key name to load.
func _on_preset_changed(preset: String) -> void:
	print("VideoOptions: Quality preset changed to: ", preset)
	if VideoConfig.PRESETS.has(preset):
		var raw_p_data: Variant = VideoConfig.PRESETS[preset]
		var p_data: Dictionary = raw_p_data if raw_p_data is Dictionary else {}
		effects_section.apply_preset_dict(p_data)
		quality_section.apply_preset_dict(p_data)
		GlobalSettings.save_settings_bulk("Settings", p_data)

	_apply_all_settings()


## Gathers all configuration values and applies them to viewport.
func _apply_all_settings() -> void:
	print("VideoOptions: Dispatching full state payload to VideoApplier.")
	var mode_val: int = GlobalSettings.get_setting_int(
		"Settings", "display_mode", VideoConfig.DEFAULT_DISPLAY
	)
	var mode: DisplayServer.WindowMode = mode_val as DisplayServer.WindowMode
	var screen_idx: int = GlobalSettings.get_setting_int("Settings", "screen_index", 0)
	var res_x: int = GlobalSettings.get_setting_int("Settings", "resolution_x", 1920)
	var res_y: int = GlobalSettings.get_setting_int("Settings", "resolution_y", 1080)
	var res: Vector2i = Vector2i(res_x, res_y)
	VideoApplier.apply_window_settings(get_window(), mode, screen_idx, res)

	var vsync_val: int = GlobalSettings.get_setting_int(
		"Settings", "vsync_mode", VideoConfig.DEFAULT_VSYNC
	)
	var vsync: DisplayServer.VSyncMode = vsync_val as DisplayServer.VSyncMode
	var fps_cap: int = GlobalSettings.get_setting_int(
		"Settings", "fps_limit", VideoConfig.DEFAULT_FPS
	)
	VideoApplier.apply_engine_limits(vsync, fps_cap)

	var raw_aniso: Variant = GlobalSettings.get_setting(
		"Settings", "anisotropy", VideoConfig.DEFAULT_ANISOTROPY
	)
	var aniso_key: String = raw_aniso if raw_aniso is String else VideoConfig.DEFAULT_ANISOTROPY
	var raw_aniso_val: Variant = VideoConfig.ANISOTROPY_LEVELS.get(aniso_key, 2)
	var aniso_val: int = raw_aniso_val if raw_aniso_val is int else 2
	VideoApplier.apply_anisotropy(aniso_val)

	var raw_shadow: Variant = GlobalSettings.get_setting(
		"Settings", "shadow_quality", "High (Smooth)"
	)
	var shadow_key: String = raw_shadow if raw_shadow is String else "High (Smooth)"
	var raw_shadow_data: Variant = VideoConfig.SHADOW_QUALITIES.get(shadow_key, {})
	var shadow_data: Dictionary = raw_shadow_data if raw_shadow_data is Dictionary else {}

	var raw_fsr: Variant = GlobalSettings.get_setting(
		"Settings", "fsr_mode", VideoConfig.DEFAULT_FSR_MODE
	)
	var fsr_key: String = raw_fsr if raw_fsr is String else VideoConfig.DEFAULT_FSR_MODE
	var raw_aa: Variant = GlobalSettings.get_setting(
		"Settings", "aa_mode", VideoConfig.DEFAULT_AA_MODE
	)
	var aa_key: String = raw_aa if raw_aa is String else VideoConfig.DEFAULT_AA_MODE

	var dyn_shadows: bool = GlobalSettings.get_setting_bool(
		"Settings", "dynamic_light_shadows", VideoConfig.DEFAULT_DYNAMIC_LIGHT_SHADOWS
	)
	var raw_filter: Variant = GlobalSettings.get_setting(
		"Settings", "shadow_filter", VideoConfig.DEFAULT_SHADOW_FILTER
	)
	var shadow_filter: String = (
		raw_filter if raw_filter is String else VideoConfig.DEFAULT_SHADOW_FILTER
	)
	var p_shadow_dist: float = GlobalSettings.get_setting_float(
		"Settings", "positional_shadow_distance", VideoConfig.DEFAULT_POSITIONAL_SHADOW_DISTANCE
	)
	var d_shadow_dist: float = GlobalSettings.get_setting_float(
		"Settings", "directional_shadow_distance", VideoConfig.DEFAULT_DIRECTIONAL_SHADOW_DISTANCE
	)
	var occ_cull: bool = GlobalSettings.get_setting_bool(
		"Settings", "occlusion_culling", VideoConfig.DEFAULT_OCCLUSION_CULLING
	)
	var raw_vrs: Variant = GlobalSettings.get_setting(
		"Settings", "vrs_mode", VideoConfig.DEFAULT_VRS_MODE
	)
	var vrs_key: String = raw_vrs if raw_vrs is String else VideoConfig.DEFAULT_VRS_MODE
	var raw_tex_filter: Variant = GlobalSettings.get_setting(
		"Settings", "texture_filter", VideoConfig.DEFAULT_TEXTURE_FILTER
	)
	var tex_filter: String = (
		raw_tex_filter if raw_tex_filter is String else VideoConfig.DEFAULT_TEXTURE_FILTER
	)
	var res_scale: float = GlobalSettings.get_setting_float(
		"Settings", "resolution_scale", VideoConfig.DEFAULT_RESOLUTION_SCALE
	)
	var exp_val: float = GlobalSettings.get_setting_float(
		"Settings", "exposure", VideoConfig.DEFAULT_EXPOSURE
	)
	var raw_dof_amount: float = GlobalSettings.get_setting_float("Settings", "dof_amount", 0.15)
	var dof_val: bool = GlobalSettings.get_setting_bool(
		"Settings", "dof_enabled", raw_dof_amount > 0.005
	)
	var mb_strength: float = GlobalSettings.get_setting_float(
		"Settings", "motion_blur", VideoConfig.DEFAULT_MOTION_BLUR
	)

	var raw_ssao: Variant = GlobalSettings.get_setting("Settings", "ssao", VideoConfig.DEFAULT_SSAO)
	var ssao_key: String = raw_ssao if raw_ssao is String else VideoConfig.DEFAULT_SSAO
	var raw_ssi: Variant = GlobalSettings.get_setting("Settings", "ssi", VideoConfig.DEFAULT_SSI)
	var ssi_key: String = raw_ssi if raw_ssi is String else VideoConfig.DEFAULT_SSI
	var raw_ssr: Variant = GlobalSettings.get_setting("Settings", "ssr", VideoConfig.DEFAULT_SSR)
	var ssr_key: String = raw_ssr if raw_ssr is String else VideoConfig.DEFAULT_SSR
	var raw_sdfgi: Variant = GlobalSettings.get_setting(
		"Settings", "sdfgi", VideoConfig.DEFAULT_SDFGI
	)
	var sdfgi_key: String = raw_sdfgi if raw_sdfgi is String else VideoConfig.DEFAULT_SDFGI
	var raw_fog: Variant = GlobalSettings.get_setting(
		"Settings", "volumetric_fog", VideoConfig.DEFAULT_FOG
	)
	var fog_key: String = raw_fog if raw_fog is String else VideoConfig.DEFAULT_FOG
	var raw_glow: Variant = GlobalSettings.get_setting("Settings", "glow", VideoConfig.DEFAULT_GLOW)
	var glow_key: String = raw_glow if raw_glow is String else VideoConfig.DEFAULT_GLOW

	var raw_fsr_val: Variant = VideoConfig.FSR_MODES.get(fsr_key, 1.0)
	var fsr_scale: float = raw_fsr_val if raw_fsr_val is float else 1.0

	var raw_aa_val: Variant = VideoConfig.AA_MODES.get(aa_key, {})
	var aa_settings: Dictionary = raw_aa_val if raw_aa_val is Dictionary else {}

	var raw_atlas: Variant = shadow_data.get("atlas_size", 4096)
	var shadow_atlas: int = raw_atlas if raw_atlas is int else 4096

	var raw_vrs_val: Variant = VideoConfig.VRS_MODES.get(vrs_key, Viewport.VRS_DISABLED)
	var vrs_mode: int = raw_vrs_val if raw_vrs_val is int else Viewport.VRS_DISABLED

	var raw_tex_val: Variant = VideoConfig.TEXTURE_FILTER_MODES.get(tex_filter, 2)
	var tex_filter_val: int = raw_tex_val if raw_tex_val is int else 2

	var mesh_lod: float = GlobalSettings.get_setting_float("Settings", "mesh_lod_threshold", 1.0)
	var debanding: bool = GlobalSettings.get_setting_bool("Settings", "debanding", true)
	var raw_tonemap: Variant = GlobalSettings.get_setting("Settings", "tonemap_mode", "Filmic")
	var tonemap_key: String = raw_tonemap if raw_tonemap is String else "Filmic"

	var raw_ssao_data: Variant = VideoConfig.SSAO_MODES.get(ssao_key, {})
	var ssao_dict: Dictionary = raw_ssao_data if raw_ssao_data is Dictionary else {}

	var raw_ssi_data: Variant = VideoConfig.SSI_MODES.get(ssi_key, {})
	var ssi_dict: Dictionary = raw_ssi_data if raw_ssi_data is Dictionary else {}

	var raw_ssr_data: Variant = VideoConfig.SSR_MODES.get(ssr_key, {})
	var ssr_dict: Dictionary = raw_ssr_data if raw_ssr_data is Dictionary else {}

	var raw_sdfgi_data: Variant = VideoConfig.SDFGI_MODES.get(sdfgi_key, {})
	var sdfgi_dict: Dictionary = raw_sdfgi_data if raw_sdfgi_data is Dictionary else {}

	var raw_fog_data: Variant = VideoConfig.FOG_MODES.get(fog_key, {})
	var fog_dict: Dictionary = raw_fog_data if raw_fog_data is Dictionary else {}

	var raw_glow_data: Variant = VideoConfig.GLOW_MODES.get(glow_key, {})
	var glow_dict: Dictionary = raw_glow_data if raw_glow_data is Dictionary else {}

	var config: Dictionary = {
		"fsr_scale": fsr_scale,
		"aa_settings": aa_settings,
		"shadow_atlas": shadow_atlas,
		"dynamic_light_shadows": dyn_shadows,
		"shadow_filter": shadow_filter,
		"positional_shadow_distance": p_shadow_dist,
		"directional_shadow_distance": d_shadow_dist,
		"occlusion_culling": occ_cull,
		"vrs_mode": vrs_mode,
		"texture_filter": tex_filter_val,
		"resolution_scale": res_scale,
		"exposure": exp_val,
		"motion_blur": mb_strength,
		"mesh_lod": mesh_lod,
		"debanding": debanding,
		"tonemap_key": tonemap_key,
		"dof_amount": raw_dof_amount if dof_val else 0.0,
		"dof_enabled": dof_val,
		"ssao": ssao_dict,
		"ssi": ssi_dict,
		"ssr": ssr_dict,
		"sdfgi": sdfgi_dict,
		"fog": fog_dict,
		"glow": glow_dict,
	}
	VideoApplier.apply_viewport_pipeline(get_tree(), get_viewport(), config)


## Displays restart confirmation dialog for GPU or driver changes.
## [param msg] Confirmation message prompt to display.
## [param rend_key] Rendering driver identifier to apply on restart.
## [param gpu_idx] Dedicated GPU adapter hardware index to apply.
func _on_restart_required(msg: String, rend_key: String, gpu_idx: int) -> void:
	print("VideoOptions: Restart confirmation requested.")
	_pending_renderer = rend_key
	_pending_gpu_index = gpu_idx
	restart_dialog.dialog_text = msg
	restart_dialog.popup_centered()


## Persists launch arguments and restarts application.
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


## Dispatches auto-tune benchmark pass to [GraphicsManager].
func _on_auto_tune_requested() -> void:
	print("VideoOptions: Dispatching 60 FPS benchmark pass.")
	hardware_section.set_benchmark_state(true)
	var manager: Node = SystemLocator.get_graphics_manager()
	if is_instance_valid(manager) and manager.has_method(&"run_benchmark_for_60fps"):
		manager.call(&"run_benchmark_for_60fps")


## Refreshes UI sections after benchmark routine completes.
## [param _optimal_level] Recommended graphics tier determined by pass.
func _on_benchmark_completed(_optimal_level: int) -> void:
	print("VideoOptions: Benchmark completed. Refreshing all panels.")
	hardware_section.set_benchmark_state(false)
	display_section.load_settings()
	quality_section.load_settings()
	effects_section.load_settings()
	hardware_section.load_settings()
	_apply_all_settings()
