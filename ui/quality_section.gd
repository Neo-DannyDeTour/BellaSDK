## Controls graphics presets, shadow maps, scaling filters, and mesh LOD.
class_name QualitySection
extends VBoxContainer

## Emitted when the master preset selection changes.
signal preset_changed(preset_name: String)

## Emitted when individual graphics quality options change.
signal quality_settings_changed

## Preset "Low" toggle [Button].
@onready var preset_low_button: Button = %PresetLowButton
## Preset "Medium" toggle [Button].
@onready var preset_medium_button: Button = %PresetMediumButton
## Preset "High" toggle [Button].
@onready var preset_high_button: Button = %PresetHighButton
## Preset "Ultra" toggle [Button].
@onready var preset_ultra_button: Button = %PresetUltraButton

## Shadow quality "Off" toggle [Button].
@onready var shadow_off_button: Button = %ShadowOffButton
## Shadow quality "Low" toggle [Button].
@onready var shadow_low_button: Button = %ShadowLowButton
## Shadow quality "Medium" toggle [Button].
@onready var shadow_medium_button: Button = %ShadowMediumButton
## Shadow quality "High" toggle [Button].
@onready var shadow_high_button: Button = %ShadowHighButton

## Reference to dynamic light shadow toggle [CheckBox].
@onready var dynamic_shadows_checkbox: CheckBox = %DynamicShadowsCheckBox

## Shadow filter "Hard" toggle [Button].
@onready var shadow_filter_hard_button: Button = %ShadowFilterHardButton
## Shadow filter "Soft Low" toggle [Button].
@onready var shadow_filter_low_button: Button = %ShadowFilterLowButton
## Shadow filter "Soft Medium" toggle [Button].
@onready var shadow_filter_medium_button: Button = %ShadowFilterMediumButton
## Shadow filter "Soft High" toggle [Button].
@onready var shadow_filter_high_button: Button = %ShadowFilterHighButton

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

## Texture filter "Nearest" toggle [Button].
@onready var tex_filter_nearest_button: Button = %TexFilterNearestButton
## Texture filter "Linear" toggle [Button].
@onready var tex_filter_linear_button: Button = %TexFilterLinearButton
## Texture filter "Linear Mipmap" toggle [Button].
@onready var tex_filter_lin_mip_button: Button = %TexFilterLinMipButton
## Texture filter "Nearest Mipmap" toggle [Button].
@onready var tex_filter_near_mip_button: Button = %TexFilterNearMipButton

## Reference to resolution scale input [LineEdit].
@onready var res_scale_line: LineEdit = %ResolutionScaleLine
## Reference to resolution scale slider [HSlider].
@onready var res_scale_slider: HSlider = %ResolutionScaleSlider
## Reference to anti-aliasing configuration [OptionButton].
@onready var aa_options: OptionButton = %AAOptionButton

## FSR "Native" toggle [Button].
@onready var fsr_native_button: Button = %FSRNativeButton
## FSR "Quality" toggle [Button].
@onready var fsr_quality_button: Button = %FSRQualityButton
## FSR "Balanced" toggle [Button].
@onready var fsr_balanced_button: Button = %FSRBalancedButton
## FSR "Performance" toggle [Button].
@onready var fsr_perf_button: Button = %FSRPerfButton

## Reference to anisotropic filtering level [OptionButton].
@onready var anisotropy_options: OptionButton = %AnisotropyOptionButton
## Reference to the Mesh LOD slider [HSlider].
@onready var mesh_lod_slider: HSlider = %MeshLODSlider
## Reference to the Mesh LOD input [LineEdit].
@onready var mesh_lod_line: LineEdit = %MeshLODLine

## Lookup map associating preset names with toggle buttons.
var _preset_btn_map: Dictionary[String, Button] = {}
## Lookup map associating shadow quality names with toggle buttons.
var _shadow_btn_map: Dictionary[String, Button] = {}
## Lookup map associating shadow filter names with toggle buttons.
var _shadow_filter_btn_map: Dictionary[String, Button] = {}
## Lookup map associating texture filter names with toggle buttons.
var _texture_filter_btn_map: Dictionary[String, Button] = {}
## Lookup map associating FSR mode names with toggle buttons.
var _fsr_btn_map: Dictionary[String, Button] = {}


## Populates dropdown entries and connects widgets to listeners.
func _ready() -> void:
	print("QualitySection: Initializing quality section UI.")
	_setup_button_mappings()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Configures ButtonGroups and dictionary mappings for quality button rows.
func _setup_button_mappings() -> void:
	print("QualitySection: Configuring button groups and mapping lookups.")
	_preset_btn_map = {
		"Low": preset_low_button,
		"Medium": preset_medium_button,
		"High": preset_high_button,
		"Ultra": preset_ultra_button,
	}
	_setup_group(_preset_btn_map)

	_shadow_btn_map = {
		"Off": shadow_off_button,
		"Low (Fast)": shadow_low_button,
		"Medium": shadow_medium_button,
		"High (Smooth)": shadow_high_button,
	}
	_setup_group(_shadow_btn_map)

	_shadow_filter_btn_map = {
		"Hard (Fast)": shadow_filter_hard_button,
		"Soft Low": shadow_filter_low_button,
		"Soft Medium": shadow_filter_medium_button,
		"Soft High": shadow_filter_high_button,
	}
	_setup_group(_shadow_filter_btn_map)

	_texture_filter_btn_map = {
		"Nearest": tex_filter_nearest_button,
		"Linear": tex_filter_linear_button,
		"Linear Mipmap": tex_filter_lin_mip_button,
		"Nearest Mipmap": tex_filter_near_mip_button,
	}
	_setup_group(_texture_filter_btn_map)

	_fsr_btn_map = {
		"Disabled (Native)": fsr_native_button,
		"Quality": fsr_quality_button,
		"Balanced": fsr_balanced_button,
		"Performance": fsr_perf_button,
	}
	_setup_group(_fsr_btn_map)


## Assigns a unified [ButtonGroup] and pressed visual styles to buttons.
func _setup_group(mapping: Dictionary[String, Button]) -> void:
	var group: ButtonGroup = ButtonGroup.new()

	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	pressed_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(3)

	for btn: Button in mapping.values():
		btn.toggle_mode = true
		btn.button_group = group
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("hover_pressed", pressed_style)
		btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7, 1.0))


## Populates dropdown buttons with keys defined in [VideoConfig].
func _populate_dropdowns() -> void:
	print("QualitySection: Populating remaining dropdown items.")
	_fill_dropdown(vrs_options, VideoConfig.VRS_MODES)
	_fill_dropdown(aa_options, VideoConfig.AA_MODES)
	_fill_dropdown(anisotropy_options, VideoConfig.ANISOTROPY_LEVELS)


## Connects all widget selection signals to their corresponding handlers.
func _connect_signals() -> void:
	print("QualitySection: Connecting quality section signals.")
	for preset_name: String in _preset_btn_map.keys():
		var btn: Button = _preset_btn_map[preset_name]
		btn.pressed.connect(_on_preset_pressed.bind(preset_name))

	_connect_button_row(_shadow_btn_map, "shadow_quality")
	_connect_button_row(_shadow_filter_btn_map, "shadow_filter")
	_connect_button_row(_texture_filter_btn_map, "texture_filter")
	_connect_button_row(_fsr_btn_map, "fsr_mode")

	dynamic_shadows_checkbox.toggled.connect(_on_dynamic_shadows_toggled)
	_connect_slider(
		pos_dist_slider, pos_dist_line, "positional_shadow_distance", 8.0, 64.0, 1.0, true
	)
	_connect_slider(
		dir_dist_slider, dir_dist_line, "directional_shadow_distance", 16.0, 150.0, 1.0, true
	)
	occlusion_checkbox.toggled.connect(_on_occlusion_toggled)
	vrs_options.item_selected.connect(_on_vrs_selected)
	_connect_slider(res_scale_slider, res_scale_line, "resolution_scale", 0.1, 1.0, 0.1, false)
	aa_options.item_selected.connect(_on_aa_selected)
	anisotropy_options.item_selected.connect(_on_anisotropy_selected)
	_connect_slider(mesh_lod_slider, mesh_lod_line, "mesh_lod_threshold", 0.0, 64.0, 0.5, false)


## Connects pressed events for each button in a dictionary to settings.
func _connect_button_row(mapping: Dictionary[String, Button], config_key: String) -> void:
	for mode_key: String in mapping.keys():
		var btn: Button = mapping[mode_key]
		btn.pressed.connect(_on_quality_button_pressed.bind(config_key, mode_key))


## Connects slider and LineEdit pairs with immediate save and live dispatch.
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
				GlobalSettings.save_setting("Settings", key, s_val)
				quality_settings_changed.emit()
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
				GlobalSettings.save_setting("Settings", key, s_val)
				quality_settings_changed.emit()
	)


## Synchronizes UI widgets with saved configuration values.
func load_settings() -> void:
	print("QualitySection: Loading quality parameters from config.")
	_sync_button_row(_preset_btn_map, "preset", VideoConfig.DEFAULT_PRESET)
	_sync_button_row(_shadow_btn_map, "shadow_quality", "High (Smooth)")

	var dyn_val: bool = bool(
		GlobalSettings.get_setting(
			"Settings", "dynamic_light_shadows", VideoConfig.DEFAULT_DYNAMIC_LIGHT_SHADOWS
		)
	)
	dynamic_shadows_checkbox.set_pressed_no_signal(dyn_val)

	_sync_button_row(_shadow_filter_btn_map, "shadow_filter", VideoConfig.DEFAULT_SHADOW_FILTER)

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
	_sync_button_row(_texture_filter_btn_map, "texture_filter", VideoConfig.DEFAULT_TEXTURE_FILTER)

	var r_scale: float = float(
		GlobalSettings.get_setting(
			"Settings", "resolution_scale", VideoConfig.DEFAULT_RESOLUTION_SCALE
		)
	)
	res_scale_slider.set_value_no_signal(r_scale)
	res_scale_line.text = "%.1f" % r_scale

	_sync_dropdown(aa_options, VideoConfig.AA_MODES, "aa_mode", VideoConfig.DEFAULT_AA_MODE)
	_sync_button_row(_fsr_btn_map, "fsr_mode", VideoConfig.DEFAULT_FSR_MODE)
	_sync_dropdown(
		anisotropy_options,
		VideoConfig.ANISOTROPY_LEVELS,
		"anisotropy",
		VideoConfig.DEFAULT_ANISOTROPY
	)

	var lod: float = GlobalSettings.get_setting("Settings", "mesh_lod_threshold", 1.0) as float
	mesh_lod_slider.set_value_no_signal(lod)
	mesh_lod_line.text = "%.2f" % lod


## Reads a persisted setting and activates the corresponding toggle button.
func _sync_button_row(
	mapping: Dictionary[String, Button], config_key: String, default_val: String
) -> void:
	var saved: String = str(GlobalSettings.get_setting("Settings", config_key, default_val))
	for key: String in mapping.keys():
		mapping[key].button_pressed = (key == saved)


## Updates local quality controls without modifying other subsystem states.
func apply_preset_dict(data: Dictionary) -> void:
	print("QualitySection: Applying preset quality dictionary.")
	if data.has("shadow_quality") and _shadow_btn_map.has(str(data["shadow_quality"])):
		_shadow_btn_map[str(data["shadow_quality"])].button_pressed = true
	if data.has("dynamic_light_shadows"):
		dynamic_shadows_checkbox.set_pressed_no_signal(data["dynamic_light_shadows"] as bool)
	if data.has("shadow_filter") and _shadow_filter_btn_map.has(str(data["shadow_filter"])):
		_shadow_filter_btn_map[str(data["shadow_filter"])].button_pressed = true
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
	if data.has("texture_filter") and _texture_filter_btn_map.has(str(data["texture_filter"])):
		_texture_filter_btn_map[str(data["texture_filter"])].button_pressed = true
	if data.has("resolution_scale"):
		var r_s: float = data["resolution_scale"] as float
		res_scale_slider.set_value_no_signal(r_s)
		res_scale_line.text = "%.1f" % r_s
	if data.has("mesh_lod_threshold"):
		var lod_val: float = data["mesh_lod_threshold"] as float
		mesh_lod_slider.set_value_no_signal(lod_val)
		mesh_lod_line.text = "%.2f" % lod_val


## Populates a single dropdown menu with keys from a dictionary.
func _fill_dropdown(dropdown: OptionButton, data_dict: Dictionary) -> void:
	print("QualitySection: Populating dropdown entries.")
	dropdown.clear()
	for key: String in data_dict.keys():
		dropdown.add_item(key)


## Selects a dropdown item matching target label text.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	print("QualitySection: Selecting dropdown entry: ", target_text)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Matches a saved value to an item in [param dropdown] using [param dict].
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


## Handles master preset button press.
func _on_preset_pressed(preset: String) -> void:
	print("QualitySection: Preset button pressed: ", preset)
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


## Handles dynamic light shadows toggle state changes.
func _on_dynamic_shadows_toggled(toggled_on: bool) -> void:
	print("QualitySection: Dynamic shadows toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "dynamic_light_shadows", toggled_on)
	quality_settings_changed.emit()


## Handles occlusion culling toggle state changes.
func _on_occlusion_toggled(toggled_on: bool) -> void:
	print("QualitySection: Occlusion culling toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "occlusion_culling", toggled_on)
	quality_settings_changed.emit()


## Handles VRS dropdown selection.
func _on_vrs_selected(index: int) -> void:
	var text: String = vrs_options.get_item_text(index)
	print("QualitySection: VRS mode selected: ", text)
	GlobalSettings.save_setting("Settings", "vrs_mode", text)
	quality_settings_changed.emit()


## Handles Anti-Aliasing pipeline changes.
func _on_aa_selected(index: int) -> void:
	var text: String = aa_options.get_item_text(index)
	print("QualitySection: Anti-aliasing mode changed: ", text)
	GlobalSettings.save_setting("Settings", "aa_mode", text)
	quality_settings_changed.emit()


## Handles texture anisotropic filtering level changes.
func _on_anisotropy_selected(index: int) -> void:
	var text: String = anisotropy_options.get_item_text(index)
	print("QualitySection: Anisotropic filtering changed: ", text)
	GlobalSettings.save_setting("Settings", "anisotropy", text)
	quality_settings_changed.emit()


## Handles any quality button press, saving setting and notifying pipeline.
func _on_quality_button_pressed(config_key: String, mode_key: String) -> void:
	print("QualitySection: Pressed ", config_key, " -> ", mode_key)
	var current_val: String = str(GlobalSettings.get_setting("Settings", config_key, ""))
	if current_val != mode_key:
		GlobalSettings.save_setting("Settings", config_key, mode_key)
		quality_settings_changed.emit()
