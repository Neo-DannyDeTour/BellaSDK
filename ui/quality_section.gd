## Controls graphics presets, shadow maps, scaling filters, and mesh LOD.
class_name QualitySection
extends VBoxContainer

## Emitted when the master preset dropdown selection changes.
signal preset_changed(preset_name: String)

## Emitted when individual graphics quality options change.
signal quality_settings_changed

## Reference to the graphics preset [OptionButton].
@onready var preset_options: OptionButton = %PresetOptionButton
## Reference to the shadow map quality [OptionButton].
@onready var shadow_options: OptionButton = %ShadowOptionButton
## Reference to dynamic light shadow toggle [CheckBox].
@onready var dynamic_shadows_checkbox: CheckBox = %DynamicShadowsCheckBox
## Reference to shadow filter softness [OptionButton].
@onready var shadow_filter_options: OptionButton = %ShadowFilterOptionButton
## Reference to positional shadow distance input [LineEdit].
@onready var pos_dist_line: LineEdit = %PositionalShadowDistanceLine
## Reference to positional shadow distance slider [HSlider].
@onready var pos_dist_slider: HSlider = %PositionalShadowDistanceSlider
## Reference to directional shadow distance input [LineEdit].
@onready var dir_dist_line: LineEdit = %DirectionalShadowDistanceLine
## Reference to directional shadow distance slider [HSlider].
@onready var dir_dist_slider: HSlider = %DirectionalShadowDistanceSlider
## Reference to occlusion culling toggle [CheckBox].
@onready var occlusion_checkbox: CheckBox = %OcclusionCullingCheckBox
## Reference to the VRS mode [OptionButton].
@onready var vrs_options: OptionButton = %VRSOptionButton
## Reference to the texture filter [OptionButton].
@onready var texture_filter_options: OptionButton = %TextureFilterOptionButton
## Reference to resolution scale input [LineEdit].
@onready var res_scale_line: LineEdit = %ResolutionScaleLine
## Reference to resolution scale slider [HSlider].
@onready var res_scale_slider: HSlider = %ResolutionScaleSlider
## Reference to anti-aliasing configuration [OptionButton].
@onready var aa_options: OptionButton = %AAOptionButton
## Reference to FSR scaling [OptionButton].
@onready var fsr_options: OptionButton = %FSROptionButton
## Reference to anisotropic filtering level [OptionButton].
@onready var anisotropy_options: OptionButton = %AnisotropyOptionButton
## Reference to the Mesh LOD slider [HSlider].
@onready var mesh_lod_slider: HSlider = %MeshLODSlider
## Reference to the Mesh LOD input [LineEdit].
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
	_fill_dropdown(shadow_filter_options, VideoConfig.SHADOW_FILTER_MODES)
	_fill_dropdown(vrs_options, VideoConfig.VRS_MODES)
	_fill_dropdown(texture_filter_options, VideoConfig.TEXTURE_FILTER_MODES)
	_fill_dropdown(aa_options, VideoConfig.AA_MODES)
	_fill_dropdown(fsr_options, VideoConfig.FSR_MODES)
	_fill_dropdown(anisotropy_options, VideoConfig.ANISOTROPY_LEVELS)


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("QualitySection: Connecting quality section signals.")
	preset_options.item_selected.connect(_on_preset_selected)
	shadow_options.item_selected.connect(_on_shadow_selected)
	dynamic_shadows_checkbox.toggled.connect(_on_dynamic_shadows_toggled)
	shadow_filter_options.item_selected.connect(_on_shadow_filter_selected)
	_connect_slider(
		pos_dist_slider, pos_dist_line, "positional_shadow_distance", 8.0, 64.0, 1.0, true
	)
	_connect_slider(
		dir_dist_slider, dir_dist_line, "directional_shadow_distance", 16.0, 150.0, 1.0, true
	)
	occlusion_checkbox.toggled.connect(_on_occlusion_toggled)
	vrs_options.item_selected.connect(_on_vrs_selected)
	texture_filter_options.item_selected.connect(_on_texture_filter_selected)
	_connect_slider(res_scale_slider, res_scale_line, "resolution_scale", 0.1, 1.0, 0.1, false)
	aa_options.item_selected.connect(_on_aa_selected)
	fsr_options.item_selected.connect(_on_fsr_selected)
	anisotropy_options.item_selected.connect(_on_anisotropy_selected)
	_connect_slider(mesh_lod_slider, mesh_lod_line, "mesh_lod_threshold", 0.0, 4.0, 0.01, false)


## Connects slider and LineEdit pairs with auto-clear and fallback handling.
## [param slider] The [HSlider] node.
## [param line] The [LineEdit] node.
## [param key] Setting key identifier.
## [param min_v] Minimum clamp limit.
## [param max_v] Maximum clamp limit.
## [param step_val] Step interval for the slider.
## [param is_int] True if formatted as integer.
func _connect_slider(
	slider: HSlider,
	line: LineEdit,
	key: String,
	min_v: float,
	max_v: float,
	step_val: float,
	is_int: bool
) -> void:
	if not is_instance_valid(slider) or not is_instance_valid(line):
		return
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_val

	slider.value_changed.connect(
		func(val: float) -> void:
			if not line.has_focus():
				line.text = (
					str(int(val)) if is_int else ("%.1f" % val if step_val == 0.1 else "%.2f" % val)
				)
			GlobalSettings.save_setting("Settings", key, val)
			quality_settings_changed.emit()
	)

	line.focus_entered.connect(
		func() -> void:
			line.set_meta("pre_focus_text", line.text)
			line.text = ""
	)

	line.text_submitted.connect(
		func(text: String) -> void:
			var trimmed: String = text.strip_edges()
			var fallback: String = str(line.get_meta("pre_focus_text", ""))
			if trimmed.is_empty() or not trimmed.is_valid_float():
				line.text = fallback
			else:
				var c_val: float = clampf(trimmed.to_float(), min_v, max_v)
				var s_val: float = snappedf(c_val, step_val)
				line.text = (
					str(int(s_val))
					if is_int
					else ("%.1f" % s_val if step_val == 0.1 else "%.2f" % s_val)
				)
				slider.value = s_val
				print("QualitySection: Committed ", key, " input: ", s_val)
			line.release_focus()
	)

	line.focus_exited.connect(
		func() -> void:
			var trimmed: String = line.text.strip_edges()
			var fallback: String = str(line.get_meta("pre_focus_text", ""))
			if trimmed.is_empty() or not trimmed.is_valid_float():
				line.text = fallback
			else:
				var c_val: float = clampf(trimmed.to_float(), min_v, max_v)
				var s_val: float = snappedf(c_val, step_val)
				line.text = (
					str(int(s_val))
					if is_int
					else ("%.1f" % s_val if step_val == 0.1 else "%.2f" % s_val)
				)
				slider.value = s_val
				print("QualitySection: Saved ", key, " on defocus: ", s_val)
	)


## Synchronizes UI widgets with saved configuration values.
func load_settings() -> void:
	print("QualitySection: Loading quality parameters from config.")
	var preset: String = (
		GlobalSettings.get_setting("Settings", "preset", VideoConfig.DEFAULT_PRESET) as String
	)
	_select_dropdown_text(preset_options, preset)

	_sync_dropdown(shadow_options, VideoConfig.SHADOW_QUALITIES, "shadow_quality", "High (Smooth)")

	var dyn_val: bool = bool(
		GlobalSettings.get_setting(
			"Settings", "dynamic_light_shadows", VideoConfig.DEFAULT_DYNAMIC_LIGHT_SHADOWS
		)
	)
	dynamic_shadows_checkbox.set_pressed_no_signal(dyn_val)

	_sync_dropdown(
		shadow_filter_options,
		VideoConfig.SHADOW_FILTER_MODES,
		"shadow_filter",
		VideoConfig.DEFAULT_SHADOW_FILTER
	)

	var p_dist: float = float(
		GlobalSettings.get_setting(
			"Settings", "positional_shadow_distance", VideoConfig.DEFAULT_POSITIONAL_SHADOW_DISTANCE
		)
	)
	pos_dist_slider.set_value_no_signal(p_dist)
	pos_dist_line.text = str(int(p_dist))

	var d_dist: float = float(
		GlobalSettings.get_setting(
			"Settings",
			"directional_shadow_distance",
			VideoConfig.DEFAULT_DIRECTIONAL_SHADOW_DISTANCE
		)
	)
	dir_dist_slider.set_value_no_signal(d_dist)
	dir_dist_line.text = str(int(d_dist))

	var occ_val: bool = bool(
		GlobalSettings.get_setting(
			"Settings", "occlusion_culling", VideoConfig.DEFAULT_OCCLUSION_CULLING
		)
	)
	occlusion_checkbox.set_pressed_no_signal(occ_val)

	_sync_dropdown(vrs_options, VideoConfig.VRS_MODES, "vrs_mode", VideoConfig.DEFAULT_VRS_MODE)
	_sync_dropdown(
		texture_filter_options,
		VideoConfig.TEXTURE_FILTER_MODES,
		"texture_filter",
		VideoConfig.DEFAULT_TEXTURE_FILTER
	)

	var r_scale: float = float(
		GlobalSettings.get_setting(
			"Settings", "resolution_scale", VideoConfig.DEFAULT_RESOLUTION_SCALE
		)
	)
	res_scale_slider.set_value_no_signal(r_scale)
	res_scale_line.text = "%.1f" % r_scale

	_sync_dropdown(aa_options, VideoConfig.AA_MODES, "aa_mode", VideoConfig.DEFAULT_AA_MODE)
	_sync_dropdown(fsr_options, VideoConfig.FSR_MODES, "fsr_mode", VideoConfig.DEFAULT_FSR_MODE)
	_sync_dropdown(
		anisotropy_options,
		VideoConfig.ANISOTROPY_LEVELS,
		"anisotropy",
		VideoConfig.DEFAULT_ANISOTROPY
	)

	var lod: float = GlobalSettings.get_setting("Settings", "mesh_lod_threshold", 1.0) as float
	mesh_lod_slider.set_value_no_signal(lod)
	mesh_lod_line.text = "%.2f" % lod


## Updates local quality controls without modifying other subsystem states.
## [param data] Dictionary holding quality preset values.
func apply_preset_dict(data: Dictionary) -> void:
	print("QualitySection: Applying preset quality dictionary.")
	if data.has("shadow_quality"):
		_select_dropdown_text(shadow_options, data["shadow_quality"] as String)
	if data.has("dynamic_light_shadows"):
		dynamic_shadows_checkbox.set_pressed_no_signal(data["dynamic_light_shadows"] as bool)
	if data.has("shadow_filter"):
		_select_dropdown_text(shadow_filter_options, data["shadow_filter"] as String)
	if data.has("positional_shadow_distance"):
		var p_d: float = data["positional_shadow_distance"] as float
		pos_dist_slider.set_value_no_signal(p_d)
		pos_dist_line.text = str(int(p_d))
	if data.has("directional_shadow_distance"):
		var d_d: float = data["directional_shadow_distance"] as float
		dir_dist_slider.set_value_no_signal(d_d)
		dir_dist_line.text = str(int(d_d))
	if data.has("occlusion_culling"):
		occlusion_checkbox.set_pressed_no_signal(data["occlusion_culling"] as bool)
	if data.has("vrs_mode"):
		_select_dropdown_text(vrs_options, data["vrs_mode"] as String)
	if data.has("texture_filter"):
		_select_dropdown_text(texture_filter_options, data["texture_filter"] as String)
	if data.has("resolution_scale"):
		var r_s: float = data["resolution_scale"] as float
		res_scale_slider.set_value_no_signal(r_s)
		res_scale_line.text = "%.1f" % r_s
	if data.has("mesh_lod_threshold"):
		var lod_val: float = data["mesh_lod_threshold"] as float
		mesh_lod_slider.set_value_no_signal(lod_val)
		mesh_lod_line.text = "%.2f" % lod_val


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
	if VideoConfig.PRESETS.has(preset):
		var data: Dictionary = VideoConfig.PRESETS[preset] as Dictionary
		apply_preset_dict(data)

		var bulk_data: Dictionary = {"preset": preset}
		for key: String in data.keys():
			bulk_data[key] = data[key]
		GlobalSettings.save_settings_bulk("Settings", bulk_data)
	else:
		GlobalSettings.save_setting("Settings", "preset", preset)

	preset_changed.emit(preset)


## Handles shadow atlas quality selection.
## [param index] Item index selected.
func _on_shadow_selected(index: int) -> void:
	var text: String = shadow_options.get_item_text(index)
	print("QualitySection: Shadow quality changed: ", text)
	GlobalSettings.save_setting("Settings", "shadow_quality", text)
	quality_settings_changed.emit()


## Handles dynamic light shadows toggle state changes.
## [param toggled_on] Boolean state indicating if local light shadows are active.
func _on_dynamic_shadows_toggled(toggled_on: bool) -> void:
	print("QualitySection: Dynamic shadows toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "dynamic_light_shadows", toggled_on)
	quality_settings_changed.emit()


## Handles positional shadow filter quality dropdown selection.
## [param index] Item index selected.
func _on_shadow_filter_selected(index: int) -> void:
	var text: String = shadow_filter_options.get_item_text(index)
	print("QualitySection: Shadow filter mode selected: ", text)
	GlobalSettings.save_setting("Settings", "shadow_filter", text)
	quality_settings_changed.emit()


## Handles occlusion culling toggle state changes.
## [param toggled_on] Boolean state for occlusion culling.
func _on_occlusion_toggled(toggled_on: bool) -> void:
	print("QualitySection: Occlusion culling toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "occlusion_culling", toggled_on)
	quality_settings_changed.emit()


## Handles VRS dropdown selection.
## [param index] Item index selected.
func _on_vrs_selected(index: int) -> void:
	var text: String = vrs_options.get_item_text(index)
	print("QualitySection: VRS mode selected: ", text)
	GlobalSettings.save_setting("Settings", "vrs_mode", text)
	quality_settings_changed.emit()


## Handles texture filter dropdown selection.
## [param index] Item index selected.
func _on_texture_filter_selected(index: int) -> void:
	var text: String = texture_filter_options.get_item_text(index)
	print("QualitySection: Texture filter selected: ", text)
	GlobalSettings.save_setting("Settings", "texture_filter", text)
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
