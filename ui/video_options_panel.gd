## Coordinates video sub-panels, preset synchronization, and restart dialogs.
class_name VideoOptions
extends Panel

## Cached pending rendering driver identifier chosen before application restart.
var _pending_renderer: String = ""

## Cached pending GPU adapter hardware index chosen before application restart.
var _pending_gpu_index: int = -1

## Guard flag preventing recursive signal loops during bulk preset or default resets.
var _is_applying_batch: bool = false

## Reference to the display settings sub-section [DisplaySection].
@onready var display_section: DisplaySection = %DisplaySection

## Reference to the quality settings sub-section [QualitySection].
@onready var quality_section: QualitySection = %QualitySection

## Reference to the effects settings sub-section [EffectsSection].
@onready var effects_section: EffectsSection = %EffectsSection

## Reference to the hardware settings sub-section [HardwareSection].
@onready var hardware_section: HardwareSection = %HardwareSection

## Reference to the application restart confirmation [ConfirmationDialog].
@onready var restart_dialog: ConfirmationDialog = %RestartDialog


## Connects sub-section events and synchronizes initial state with [GraphicsManager].
func _ready() -> void:
	print("VideoOptions: Initializing video options panel coordinator.")
	set_process(false)
	set_physics_process(false)

	if is_instance_valid(restart_dialog):
		restart_dialog.hide()

	visibility_changed.connect(_on_visibility_changed)
	display_section.display_settings_changed.connect(_on_display_settings_changed)
	quality_section.preset_changed.connect(_on_preset_changed)
	quality_section.quality_settings_changed.connect(_on_pipeline_settings_changed)
	effects_section.effects_settings_changed.connect(_on_pipeline_settings_changed)
	hardware_section.restart_required.connect(_on_restart_required)
	restart_dialog.confirmed.connect(_on_restart_dialog_confirmed)

	if not GraphicsManager.settings_changed.is_connected(_on_external_settings_changed):
		GraphicsManager.settings_changed.connect(_on_external_settings_changed)

	if is_visible_in_tree():
		GraphicsManager.set_diorama_mode(true)


## Disconnects global signals and ensures diorama sleeps when removed from scene tree.
func _exit_tree() -> void:
	print("VideoOptions: Exiting tree; disconnecting global signals.")
	if GraphicsManager.settings_changed.is_connected(_on_external_settings_changed):
		GraphicsManager.settings_changed.disconnect(_on_external_settings_changed)


## Resets all video settings to the default "High" preset and refreshes all sub-sections.
func reset_to_defaults() -> void:
	print("VideoOptions: Resetting video settings to 'High' defaults.")
	_is_applying_batch = true
	GraphicsManager.reset_to_defaults()
	display_section.load_settings()
	quality_section.load_settings()
	effects_section.load_settings()
	hardware_section.load_settings()
	_is_applying_batch = false


## Synchronizes diorama preview state when panel visibility changes.
func _on_visibility_changed() -> void:
	if not is_inside_tree():
		return

	if is_visible_in_tree():
		print("VideoOptions: Panel visible; activating isolated diorama preview.")
		GraphicsManager.set_diorama_mode(true)
	else:
		var parent_router: CanvasItem = get_parent() as CanvasItem
		var keep_diorama: bool = (
			is_instance_valid(parent_router) and parent_router.is_visible_in_tree()
		)
		if not keep_diorama:
			GraphicsManager.set_diorama_mode(false)


## Handles display setting updates from [DisplaySection].
func _on_display_settings_changed() -> void:
	if _is_applying_batch:
		return
	GraphicsManager.apply_display_settings()


## Handles quality or effect setting updates from [QualitySection] or [EffectsSection].
func _on_pipeline_settings_changed() -> void:
	if _is_applying_batch:
		return
	if GraphicsManager.is_diorama_active:
		GraphicsManager.update_diorama_preview()
	else:
		GraphicsManager.commit_gameplay_pipeline()


## Applies a master quality preset across [QualitySection], [EffectsSection], and [GraphicsManager].
func _on_preset_changed(preset: String) -> void:
	if _is_applying_batch:
		return

	print("VideoOptions: Master preset selected -> ", preset)
	if not VideoConfig.PRESETS.has(preset):
		return

	_is_applying_batch = true
	GraphicsManager.apply_preset(preset)
	var raw_preset: Variant = VideoConfig.PRESETS[preset]
	var preset_data: Dictionary = raw_preset if raw_preset is Dictionary else {}
	quality_section.apply_preset_dict(preset_data)
	effects_section.apply_preset_dict(preset_data)
	_is_applying_batch = false


## Synchronizes UI widgets if [GraphicsManager] state changes externally.
func _on_external_settings_changed(_config: Dictionary) -> void:
	if _is_applying_batch:
		return


## Displays the restart confirmation dialog when GPU or renderer backend changes.
func _on_restart_required(msg: String, rend_key: String, gpu_idx: int) -> void:
	print("VideoOptions: Prompting player for application restart.")
	_pending_renderer = rend_key
	_pending_gpu_index = gpu_idx
	restart_dialog.dialog_text = msg
	restart_dialog.popup_centered()


## Persists renderer or GPU launch flags and restarts the process.
func _on_restart_dialog_confirmed() -> void:
	print("VideoOptions: Restart confirmed; saving hardware flags and restarting.")
	var restart_args: Array[String] = []

	if not _pending_renderer.is_empty():
		GlobalSettings.save_setting("Settings", "renderer", _pending_renderer, true)
		var driver_val: String = "opengl3" if _pending_renderer == "gl_compatibility" else "vulkan"
		restart_args.append("--rendering-driver")
		restart_args.append(driver_val)

	if _pending_gpu_index >= 0:
		GlobalSettings.save_setting("Settings", "gpu_adapter_index", _pending_gpu_index, true)
		ProjectSettings.set_setting("rendering/vulkan/rendering_device/device", _pending_gpu_index)
		restart_args.append("--gpu-index")
		restart_args.append(str(_pending_gpu_index))

	GlobalSettings.flush_to_disk()
	OS.set_restart_on_exit(true, PackedStringArray(restart_args))
	get_tree().quit()
