## Controls graphics presets, shadow quality, distances, scaling, anti-aliasing, and LOD.
class_name QualitySection
extends VBoxContainer

## Emitted when the player selects a master quality preset ("Low", "Medium", "High", "Ultra").
@warning_ignore("unused_signal")
signal preset_changed(preset_name: String)

## Emitted when any individual quality setting is adjusted.
@warning_ignore("unused_signal")
signal quality_settings_changed

## Map associating master preset names with their toggle buttons.
var _preset_btn_map: Dictionary[String, Button] = {}

## Map associating shadow quality tier names with their toggle buttons.
var _shadow_btn_map: Dictionary[String, Button] = {}

## Map associating shadow filter tier names with their toggle buttons.
var _shadow_filter_btn_map: Dictionary[String, Button] = {}

## Map associating texture filter mode names with their toggle buttons.
var _texture_filter_btn_map: Dictionary[String, Button] = {}

## Map associating FSR 2 mode names with their toggle buttons.
var _fsr_btn_map: Dictionary[String, Button] = {}

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

## Dynamic light shadow casting toggle [CheckBox].
@onready var dynamic_shadows_checkbox: CheckBox = %DynamicShadowsCheckBox

## Shadow filter "Hard" toggle [Button].
@onready var shadow_filter_hard_button: Button = %ShadowFilterHardButton

## Shadow filter "Soft Low" toggle [Button].
@onready var shadow_filter_low_button: Button = %ShadowFilterLowButton

## Shadow filter "Soft Medium" toggle [Button].
@onready var shadow_filter_medium_button: Button = %ShadowFilterMediumButton

## Shadow filter "Soft High" toggle [Button].
@onready var shadow_filter_high_button: Button = %ShadowFilterHighButton

## Positional shadow distance numerical input [LineEdit].
@onready var pos_dist_line: LineEdit = %PositionalShadowDistanceLine

## Positional shadow distance [HSlider].
@onready var pos_dist_slider: HSlider = %PositionalShadowDistanceSlider

## Directional shadow distance numerical input [LineEdit].
@onready var dir_dist_line: LineEdit = %DirectionalShadowDistanceLine

## Directional shadow distance [HSlider].
@onready var dir_dist_slider: HSlider = %DirectionalShadowDistanceSlider

## Occlusion culling toggle [CheckBox].
@onready var occlusion_checkbox: CheckBox = %OcclusionCullingCheckBox

## Variable Rate Shading mode [OptionButton].
@onready var vrs_options: OptionButton = %VRSOptionButton

## Texture filter "Nearest" toggle [Button].
@onready var tex_filter_nearest_button: Button = %TexFilterNearestButton

## Texture filter "Linear" toggle [Button].
@onready var tex_filter_linear_button: Button = %TexFilterLinearButton

## Texture filter "Linear Mipmap" toggle [Button].
@onready var tex_filter_lin_mip_button: Button = %TexFilterLinMipButton

## Texture filter "Nearest Mipmap" toggle [Button].
@onready var tex_filter_near_mip_button: Button = %TexFilterNearMipButton

## 3D resolution scale numerical input [LineEdit].
@onready var res_scale_line: LineEdit = %ResolutionScaleLine

## 3D resolution scale [HSlider].
@onready var res_scale_slider: HSlider = %ResolutionScaleSlider

## Anti-aliasing mode [OptionButton].
@onready var aa_options: OptionButton = %AAOptionButton

## FSR "Native" toggle [Button].
@onready var fsr_native_button: Button = %FSRNativeButton

## FSR "Quality" toggle [Button].
@onready var fsr_quality_button: Button = %FSRQualityButton

## FSR "Balanced" toggle [Button].
@onready var fsr_balanced_button: Button = %FSRBalancedButton

## FSR "Performance" toggle [Button].
@onready var fsr_perf_button: Button = %FSRPerfButton

## Anisotropic filtering level [OptionButton].
@onready var anisotropy_options: OptionButton = %AnisotropyOptionButton

## Mesh LOD threshold [HSlider].
@onready var mesh_lod_slider: HSlider = %MeshLODSlider

## Mesh LOD threshold numerical input [LineEdit].
@onready var mesh_lod_line: LineEdit = %MeshLODLine


## Initializes quality button groups, dropdowns, and live signal bindings.
func _ready() -> void:
	print("QualitySection: Initializing quality settings UI.")
	set_process(false)
	set_physics_process(false)
	_setup_button_mappings()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Synchronizes all quality widgets with saved settings without emitting signals.
func load_settings() -> void:
	print("QualitySection: Synchronizing quality UI with active configuration.")
	_sync_button_row(_preset_btn_map, "preset", VideoConfig.DEFAULT_PRESET)
	_sync_button_row(_shadow_btn_map, "shadow_quality", VideoConfig.DEFAULT_SHADOW_QUALITY)
	_sync_button_row(_shadow_filter_btn_map, "shadow_filter", VideoConfig.DEFAULT_SHADOW_FILTER)
	_sync_button_row(_texture_filter_btn_map, "texture_filter", VideoConfig.DEFAULT_TEXTURE_FILTER)
	_sync_button_row(_fsr_btn_map, "fsr_mode", VideoConfig.DEFAULT_FSR_MODE)

	var dyn_shadows: bool = GlobalSettings.get_setting_bool(
		"Settings", "dynamic_light_shadows", VideoConfig.DEFAULT_DYNAMIC_LIGHT_SHADOWS
	)
	dynamic_shadows_checkbox.set_pressed_no_signal(dyn_shadows)

	var p_dist: float = GlobalSettings.get_setting_float(
		"Settings", "positional_shadow_distance", VideoConfig.DEFAULT_POSITIONAL_SHADOW_DISTANCE
	)
	pos_dist_slider.set_value_no_signal(p_dist)
	pos_dist_line.text = str(int(p_dist))

	var d_dist: float = GlobalSettings.get_setting_float(
		"Settings", "directional_shadow_distance", VideoConfig.DEFAULT_DIRECTIONAL_SHADOW_DISTANCE
	)
	dir_dist_slider.set_value_no_signal(d_dist)
	dir_dist_line.text = str(int(d_dist))

	var occ_cull: bool = GlobalSettings.get_setting_bool(
		"Settings", "occlusion_culling", VideoConfig.DEFAULT_OCCLUSION_CULLING
	)
	occlusion_checkbox.set_pressed_no_signal(occ_cull)

	var vrs_str: String = str(
		GlobalSettings.get_setting("Settings", "vrs_mode", VideoConfig.DEFAULT_VRS_MODE)
	)
	_select_dropdown_text(vrs_options, vrs_str)

	var r_scale: float = GlobalSettings.get_setting_float(
		"Settings", "resolution_scale", VideoConfig.DEFAULT_RESOLUTION_SCALE
	)
	res_scale_slider.set_value_no_signal(r_scale)
	res_scale_line.text = "%.1f" % r_scale

	var aa_str: String = str(
		GlobalSettings.get_setting("Settings", "aa_mode", VideoConfig.DEFAULT_AA_MODE)
	)
	_select_dropdown_text(aa_options, aa_str)

	var aniso_str: String = str(
		GlobalSettings.get_setting("Settings", "anisotropy", VideoConfig.DEFAULT_ANISOTROPY)
	)
	_select_dropdown_text(anisotropy_options, aniso_str)

	var lod: float = GlobalSettings.get_setting_float(
		"Settings", "mesh_lod_threshold", VideoConfig.DEFAULT_MESH_LOD
	)
	mesh_lod_slider.set_value_no_signal(lod)
	mesh_lod_line.text = "%.2f" % lod


## Updates local quality widgets from a preset dictionary without emitting signals.
func apply_preset_dict(data: Dictionary) -> void:
	if data.has("preset"):
		_set_group_button_silent(_preset_btn_map, str(data["preset"]))
	if data.has("shadow_quality"):
		_set_group_button_silent(_shadow_btn_map, str(data["shadow_quality"]))
	if data.has("dynamic_light_shadows"):
		dynamic_shadows_checkbox.set_pressed_no_signal(
			VideoApplier._get_bool(data, "dynamic_light_shadows", true)
		)
	if data.has("shadow_filter"):
		_set_group_button_silent(_shadow_filter_btn_map, str(data["shadow_filter"]))
	if data.has("positional_shadow_distance"):
		var p_d: float = VideoApplier._get_float(data, "positional_shadow_distance", 32.0)
		pos_dist_slider.set_value_no_signal(p_d)
		pos_dist_line.text = str(int(p_d))
	if data.has("directional_shadow_distance"):
		var d_d: float = VideoApplier._get_float(data, "directional_shadow_distance", 64.0)
		dir_dist_slider.set_value_no_signal(d_d)
		dir_dist_line.text = str(int(d_d))
	if data.has("occlusion_culling"):
		occlusion_checkbox.set_pressed_no_signal(
			VideoApplier._get_bool(data, "occlusion_culling", true)
		)
	if data.has("vrs_mode"):
		_select_dropdown_text(vrs_options, str(data["vrs_mode"]))
	if data.has("texture_filter"):
		_set_group_button_silent(_texture_filter_btn_map, str(data["texture_filter"]))
	if data.has("fsr_mode"):
		_set_group_button_silent(_fsr_btn_map, str(data["fsr_mode"]))
	if data.has("resolution_scale"):
		var r_s: float = VideoApplier._get_float(data, "resolution_scale", 1.0)
		res_scale_slider.set_value_no_signal(r_s)
		res_scale_line.text = "%.1f" % r_s
	if data.has("mesh_lod_threshold"):
		var lod_v: float = VideoApplier._get_float(data, "mesh_lod_threshold", 4.0)
		mesh_lod_slider.set_value_no_signal(lod_v)
		mesh_lod_line.text = "%.2f" % lod_v


## Configures button group mappings for preset, shadow, texture filter, and FSR rows.
func _setup_button_mappings() -> void:
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


## Assigns a unified [ButtonGroup] and pressed visual styles to a button dictionary.
func _setup_group(mapping: Dictionary[String, Button]) -> void:
	var group: ButtonGroup = ButtonGroup.new()
	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	pressed_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(3)

	for btn: Button in mapping.values():
		if not is_instance_valid(btn):
			continue
		btn.toggle_mode = true
		btn.button_group = group
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("hover_pressed", pressed_style)
		btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7, 1.0))


## Populates VRS, AA, and Anisotropy dropdown menus from [VideoConfig].
func _populate_dropdowns() -> void:
	vrs_options.clear()
	for key: String in VideoConfig.VRS_MODES.keys():
		vrs_options.add_item(key)

	aa_options.clear()
	for key: String in VideoConfig.AA_MODES.keys():
		aa_options.add_item(key)

	anisotropy_options.clear()
	for key: String in VideoConfig.ANISOTROPY_LEVELS.keys():
		anisotropy_options.add_item(key)


## Connects all quality buttons, checkboxes, dropdowns, and sliders.
func _connect_signals() -> void:
	for preset_name: String in _preset_btn_map.keys():
		var btn: Button = _preset_btn_map[preset_name]
		if is_instance_valid(btn):
			btn.pressed.connect(_on_preset_pressed.bind(preset_name))

	_connect_button_row(_shadow_btn_map, "shadow_quality")
	_connect_button_row(_shadow_filter_btn_map, "shadow_filter")
	_connect_button_row(_texture_filter_btn_map, "texture_filter")
	_connect_button_row(_fsr_btn_map, "fsr_mode")

	dynamic_shadows_checkbox.toggled.connect(_on_dynamic_shadows_toggled)
	occlusion_checkbox.toggled.connect(_on_occlusion_toggled)
	vrs_options.item_selected.connect(_on_vrs_selected)
	aa_options.item_selected.connect(_on_aa_selected)
	anisotropy_options.item_selected.connect(_on_anisotropy_selected)

	_connect_slider(
		pos_dist_slider, pos_dist_line, "positional_shadow_distance", 16.0, 40.0, 1.0, true
	)
	_connect_slider(
		dir_dist_slider, dir_dist_line, "directional_shadow_distance", 32.0, 80.0, 1.0, true
	)
	_connect_slider(res_scale_slider, res_scale_line, "resolution_scale", 0.5, 1.0, 0.1, false)
	_connect_slider(mesh_lod_slider, mesh_lod_line, "mesh_lod_threshold", 1.0, 32.0, 0.5, false)


## Connects button presses in [param mapping] to [param config_key].
func _connect_button_row(mapping: Dictionary[String, Button], config_key: String) -> void:
	for mode_key: String in mapping.keys():
		var btn: Button = mapping[mode_key]
		if is_instance_valid(btn):
			btn.pressed.connect(_on_quality_button_pressed.bind(config_key, mode_key))


## Connects an [HSlider] and [LineEdit] pair for instant real-time diorama updates.
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
					str(int(val))
					if is_int
					else ("%.1f" % val if is_equal_approx(step_val, 0.1) else "%.2f" % val)
				)
			_commit_slider_value(key, val)
	)

	line.focus_entered.connect(
		func() -> void:
			line.set_meta("pre_focus_text", line.text)
			line.text = ""
	)

	line.text_submitted.connect(
		func(_text: String) -> void:
			_commit_slider_line(slider, line, key, min_v, max_v, step_val, is_int)
			line.release_focus()
	)

	line.focus_exited.connect(
		func() -> void: _commit_slider_line(slider, line, key, min_v, max_v, step_val, is_int)
	)


## Commits a slider value directly to [GraphicsManager] for synchronous feedback.
func _commit_slider_value(key: String, val: float) -> void:
	GraphicsManager.set_setting(key, val)
	if key == "resolution_scale":
		var matched_fsr: String = ""
		for mode: String in VideoConfig.FSR_MODES.keys():
			if is_equal_approx(VideoConfig.FSR_MODES[mode], val):
				matched_fsr = mode
				break
		if not matched_fsr.is_empty():
			_set_group_button_silent(_fsr_btn_map, matched_fsr)
			GraphicsManager.set_setting("fsr_mode", matched_fsr, false)
	quality_settings_changed.emit()


## Validates and commits manual [LineEdit] numerical input.
func _commit_slider_line(
	slider: HSlider,
	line: LineEdit,
	key: String,
	min_v: float,
	max_v: float,
	step_val: float,
	is_int: bool
) -> void:
	var trimmed: String = line.text.strip_edges()
	var fallback: String = str(line.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		line.text = fallback
		return

	var clamped: float = snappedf(clampf(trimmed.to_float(), min_v, max_v), step_val)
	var formatted: String = (
		str(int(clamped))
		if is_int
		else ("%.1f" % clamped if is_equal_approx(step_val, 0.1) else "%.2f" % clamped)
	)
	line.text = formatted
	line.set_meta("pre_focus_text", formatted)
	slider.set_value_no_signal(clamped)
	_commit_slider_value(key, clamped)


## Syncs a button row with saved settings silently.
func _sync_button_row(
	mapping: Dictionary[String, Button], config_key: String, default_val: String
) -> void:
	var saved: String = str(GlobalSettings.get_setting("Settings", config_key, default_val))
	var resolved: String = saved if mapping.has(saved) else default_val
	_set_group_button_silent(mapping, resolved)


## Activates the button matching [param target_key] without firing signals.
func _set_group_button_silent(mapping: Dictionary[String, Button], target_key: String) -> void:
	for key: String in mapping.keys():
		var btn: Button = mapping[key]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(key == target_key)


## Selects the dropdown item matching [param target_text].
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	for idx: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(idx) == target_text:
			dropdown.select(idx)
			return


## Handles master quality preset button selection.
func _on_preset_pressed(preset_name: String) -> void:
	print("QualitySection: Player selected preset -> ", preset_name)
	_set_group_button_silent(_preset_btn_map, preset_name)
	preset_changed.emit(preset_name)


## Handles quality button row selection.
func _on_quality_button_pressed(config_key: String, mode_key: String) -> void:
	print("QualitySection: Player selected ", config_key, " -> ", mode_key)
	GraphicsManager.set_setting(config_key, mode_key)
	if config_key == "fsr_mode":
		var target_scale: float = VideoConfig.FSR_MODES.get(mode_key, 1.0)
		res_scale_slider.set_value_no_signal(target_scale)
		res_scale_line.text = "%.1f" % target_scale
		GraphicsManager.set_setting("resolution_scale", target_scale)
	quality_settings_changed.emit()


## Handles dynamic light shadows checkbox toggle.
func _on_dynamic_shadows_toggled(toggled_on: bool) -> void:
	print("QualitySection: Player toggled dynamic shadows -> ", toggled_on)
	GraphicsManager.set_setting("dynamic_light_shadows", toggled_on)
	quality_settings_changed.emit()


## Handles occlusion culling checkbox toggle.
func _on_occlusion_toggled(toggled_on: bool) -> void:
	print("QualitySection: Player toggled occlusion culling -> ", toggled_on)
	GraphicsManager.set_setting("occlusion_culling", toggled_on)
	quality_settings_changed.emit()


## Handles Variable Rate Shading dropdown selection.
func _on_vrs_selected(index: int) -> void:
	var label: String = vrs_options.get_item_text(index)
	print("QualitySection: Player selected VRS mode -> ", label)
	GraphicsManager.set_setting("vrs_mode", label)
	quality_settings_changed.emit()


## Handles Anti-Aliasing dropdown selection.
func _on_aa_selected(index: int) -> void:
	var label: String = aa_options.get_item_text(index)
	print("QualitySection: Player selected AA mode -> ", label)
	GraphicsManager.set_setting("aa_mode", label)
	quality_settings_changed.emit()


## Handles Anisotropic Filtering dropdown selection.
func _on_anisotropy_selected(index: int) -> void:
	var label: String = anisotropy_options.get_item_text(index)
	print("QualitySection: Player selected anisotropy -> ", label)
	GraphicsManager.set_setting("anisotropy", label)
	quality_settings_changed.emit()
