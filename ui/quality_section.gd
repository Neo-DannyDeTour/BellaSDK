## Controls graphics presets, shadow maps, scaling filters, and mesh LOD.
class_name QualitySection
extends VBoxContainer

## Emitted when graphics quality options change to trigger renderer updates.
signal quality_settings_changed

## Reference to the graphics preset [OptionButton].
@onready var preset_options: OptionButton = %PresetOptionButton
## Reference to the shadow map quality [OptionButton].
@onready var shadow_options: OptionButton = %ShadowOptionButton
## Reference to the anti-aliasing configuration [OptionButton].
@onready var aa_options: OptionButton = %AAOptionButton
## Reference to the FSR scaling [OptionButton].
@onready var fsr_options: OptionButton = %FSROptionButton
## Reference to the anisotropic filtering level [OptionButton].
@onready var anisotropy_options: OptionButton = %AnisotropyOptionButton
## Reference to the Mesh LOD slider [HSlider].
@onready var mesh_lod_slider: HSlider = %MeshLODSlider
## Reference to the Mesh LOD direct numerical input [LineEdit].
@onready var mesh_lod_line: LineEdit = %MeshLODLine


## Populates dropdown entries and connects widgets to listeners.
func _ready() -> void:
	print("QualitySection: Initializing quality section UI.")
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Populates dropdown buttons with keys defined in [VideoConfig].
func _populate_dropdowns() -> void:
	print("QualitySection: Populating quality dropdown items.")
	preset_options.clear()
	for preset: String in VideoConfig.PRESETS.keys():
		preset_options.add_item(preset)

	_fill_dropdown(shadow_options, VideoConfig.SHADOW_QUALITIES)
	_fill_dropdown(aa_options, VideoConfig.AA_MODES)
	_fill_dropdown(fsr_options, VideoConfig.FSR_MODES)
	_fill_dropdown(anisotropy_options, VideoConfig.ANISOTROPY_LEVELS)


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("QualitySection: Connecting quality section signals.")
	preset_options.item_selected.connect(_on_preset_selected)
	shadow_options.item_selected.connect(_on_shadow_selected)
	aa_options.item_selected.connect(_on_aa_selected)
	fsr_options.item_selected.connect(_on_fsr_selected)
	anisotropy_options.item_selected.connect(_on_anisotropy_selected)
	mesh_lod_slider.value_changed.connect(_on_mesh_lod_slider_changed)
	mesh_lod_line.text_submitted.connect(_on_mesh_lod_text_submitted)
	mesh_lod_line.focus_exited.connect(_on_mesh_lod_focus_exited)


## Synchronizes UI widgets with saved configuration values.
func load_settings() -> void:
	print("QualitySection: Loading quality parameters from config.")
	var preset: String = (
		GlobalSettings.get_setting("Settings", "preset", VideoConfig.DEFAULT_PRESET) as String
	)
	_select_dropdown_text(preset_options, preset)

	_sync_dropdown(shadow_options, VideoConfig.SHADOW_QUALITIES, "shadow_quality", "High (Smooth)")
	_sync_dropdown(aa_options, VideoConfig.AA_MODES, "aa_mode", VideoConfig.DEFAULT_AA_MODE)
	_sync_dropdown(fsr_options, VideoConfig.FSR_MODES, "fsr_mode", VideoConfig.DEFAULT_FSR_MODE)
	_sync_dropdown(
		anisotropy_options,
		VideoConfig.ANISOTROPY_LEVELS,
		"anisotropy",
		VideoConfig.DEFAULT_ANISOTROPY
	)

	var lod: float = GlobalSettings.get_setting("Settings", "mesh_lod_threshold", 1.0) as float
	mesh_lod_slider.value = lod
	mesh_lod_line.text = str(snappedf(lod, 0.01))


## Updates local quality controls without modifying other subsystem states.
## [param shadow_quality] Shadow atlas preset string.
## [param mesh_lod] Mesh Level of Detail threshold float.
func apply_preset_values(shadow_quality: String, mesh_lod: float) -> void:
	print("QualitySection: Applying preset values: ", shadow_quality)
	_select_dropdown_text(shadow_options, shadow_quality)
	mesh_lod_slider.value = mesh_lod
	mesh_lod_line.text = str(snappedf(mesh_lod, 0.01))


## Populates a single dropdown menu with keys from a dictionary.
## [param dropdown] The target [OptionButton] to fill.
## [param data_dict] Source dictionary holding option keys.
func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("QualitySection: Populating dropdown entries.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


## Selects a dropdown item matching target label text.
## [param dropdown] The target [OptionButton].
## [param target_text] String label to find and select.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	print("QualitySection: Selecting dropdown entry: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Matches a saved value to an item in [param dropdown] using [param dict].
## [param dropdown] The option button to update.
## [param dict] Key-value dictionary associated with the option button.
## [param key] The config setting key identifier.
## [param default_val] Default fallback value if setting does not exist.
func _sync_dropdown(
	dropdown: OptionButton, dict: Dictionary, key: String, default_val: Variant
) -> void:
	print("QualitySection: Syncing dropdown option with config key: ", key)
	var saved_val: Variant = GlobalSettings.get_setting("Settings", key, default_val)
	var saved_str: String = str(saved_val)

	for i: int in range(dropdown.get_item_count()):
		var item_text: String = dropdown.get_item_text(i)
		if item_text == saved_str:
			dropdown.select(i)
			return
		if dict.has(item_text) and str(dict[item_text]) == saved_str:
			dropdown.select(i)
			return


## Handles preset selection and propagates configuration down to settings.
## [param index] Item index selected.
func _on_preset_selected(index: int) -> void:
	var preset: String = preset_options.get_item_text(index)
	print("QualitySection: Preset selected: ", preset)
	GlobalSettings.save_setting("Settings", "preset", preset)

	if VideoConfig.PRESETS.has(preset):
		var data: Dictionary = VideoConfig.PRESETS[preset] as Dictionary
		var shadow_key: String = data["shadow_quality"] as String
		var lod_val: float = data["mesh_lod_threshold"] as float
		apply_preset_values(shadow_key, lod_val)
		GlobalSettings.save_setting("Settings", "shadow_quality", shadow_key)
		GlobalSettings.save_setting("Settings", "mesh_lod_threshold", lod_val)

	quality_settings_changed.emit()


## Handles shadow atlas quality selection.
## [param index] Item index selected.
func _on_shadow_selected(index: int) -> void:
	var text: String = shadow_options.get_item_text(index)
	print("QualitySection: Shadow quality changed: ", text)
	GlobalSettings.save_setting("Settings", "shadow_quality", text)
	quality_settings_changed.emit()


## Handles Anti-Aliasing pipeline changes.
## [param index] Item index selected.
func _on_aa_selected(index: int) -> void:
	var text: String = aa_options.get_item_text(index)
	print("QualitySection: Anti-aliasing mode changed: ", text)
	GlobalSettings.save_setting("Settings", "aa_mode", text)
	quality_settings_changed.emit()


## Handles FSR upscaling mode selection.
## [param index] Item index selected.
func _on_fsr_selected(index: int) -> void:
	var text: String = fsr_options.get_item_text(index)
	print("QualitySection: FSR mode changed: ", text)
	GlobalSettings.save_setting("Settings", "fsr_mode", text)
	quality_settings_changed.emit()


## Handles texture anisotropic filtering level changes.
## [param index] Item index selected.
func _on_anisotropy_selected(index: int) -> void:
	var text: String = anisotropy_options.get_item_text(index)
	print("QualitySection: Anisotropic filtering changed: ", text)
	GlobalSettings.save_setting("Settings", "anisotropy", text)
	quality_settings_changed.emit()


## Handles mesh LOD slider drag events.
## [param value] Current floating-point slider position.
func _on_mesh_lod_slider_changed(value: float) -> void:
	print("QualitySection: Mesh LOD slider changed: ", value)
	var snapped_val: float = snappedf(value, 0.01)
	if mesh_lod_line.text != str(snapped_val):
		mesh_lod_line.text = str(snapped_val)
	GlobalSettings.save_setting("Settings", "mesh_lod_threshold", snapped_val)
	quality_settings_changed.emit()


## Handles manual mesh LOD text submissions.
## [param new_text] Raw string submitted in the line edit.
func _on_mesh_lod_text_submitted(new_text: String) -> void:
	print("QualitySection: Mesh LOD text submitted: ", new_text)
	_parse_and_apply_lod(new_text)


## Handles mesh LOD field focus exit events.
func _on_mesh_lod_focus_exited() -> void:
	print("QualitySection: Mesh LOD focus exited.")
	_parse_and_apply_lod(mesh_lod_line.text)


## Parses and clamps raw input string into mesh LOD slider value.
## [param input_text] Text value to sanitize.
func _parse_and_apply_lod(input_text: String) -> void:
	print("QualitySection: Parsing Mesh LOD input: ", input_text)
	var val: float = clampf(
		input_text.to_float(), mesh_lod_slider.min_value, mesh_lod_slider.max_value
	)
	mesh_lod_slider.value = val
	mesh_lod_line.text = str(snappedf(val, 0.01))
