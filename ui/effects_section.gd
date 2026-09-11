## Controls post-processing, tonemapping, and environment visual effects.
class_name EffectsSection
extends VBoxContainer

## Emitted when effect options change to trigger viewport environment updates.
signal effects_settings_changed

## Reference to the tonemapper algorithm [OptionButton].
@onready var tonemap_options: OptionButton = %TonemapOptionButton
## Reference to the exposure direct numerical input [LineEdit].
@onready var exposure_line: LineEdit = %ExposureLine
## Reference to the exposure slider [HSlider].
@onready var exposure_slider: HSlider = %ExposureSlider
## Reference to the color debanding toggle [CheckBox].
@onready var debanding_checkbox: CheckBox = %DebandingCheckBox
## Reference to the depth of field amount input [LineEdit].
@onready var dof_line: LineEdit = %DoFLine
## Reference to the depth of field amount slider [HSlider].
@onready var dof_slider: HSlider = %DoFSlider
## Reference to the motion blur slider [HSlider].
@onready var motion_blur_slider: HSlider = %MotionBlurSlider
## Reference to the motion blur input [LineEdit].
@onready var motion_blur_line: LineEdit = %MotionBlurLine
## Reference to the SSAO quality [OptionButton].
@onready var ssao_options: OptionButton = %SSAOOptionButton
## Reference to SSIL quality [OptionButton].
@onready var ssi_options: OptionButton = %SSIOptionButton
## Reference to Screen Space Reflections quality [OptionButton].
@onready var ssr_options: OptionButton = %SSROptionButton
## Reference to the SDFGI quality [OptionButton].
@onready var sdfgi_options: OptionButton = %SDFGIOptionButton
## Reference to the volumetric fog quality [OptionButton].
@onready var fog_options: OptionButton = %FogOptionButton
## Reference to the glow quality [OptionButton].
@onready var glow_options: OptionButton = %GlowOptionButton


## Populates tonemapper algorithms and hooks widget state listeners.
func _ready() -> void:
	print("EffectsSection: Initializing effects UI.")
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Populates all dropdown widgets with options declared in [VideoConfig].
func _populate_dropdowns() -> void:
	print("EffectsSection: Populating all effects dropdown options.")
	_populate_button(tonemap_options, VideoConfig.TONEMAP_MODES)
	_populate_button(ssao_options, VideoConfig.SSAO_MODES)
	_populate_button(ssi_options, VideoConfig.SSI_MODES)
	_populate_button(ssr_options, VideoConfig.SSR_MODES)
	_populate_button(sdfgi_options, VideoConfig.SDFGI_MODES)
	_populate_button(fog_options, VideoConfig.FOG_MODES)
	_populate_button(glow_options, VideoConfig.GLOW_MODES)


## Fills target [OptionButton] with keys from a source [Dictionary].
## [param button] Target dropdown widget.
## [param source] Source dictionary containing option labels.
func _populate_button(button: OptionButton, source: Dictionary) -> void:
	print("EffectsSection: Populating options for: ", button.name)
	button.clear()
	for key: Variant in source.keys():
		button.add_item(str(key))


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("EffectsSection: Connecting effect UI signals.")
	tonemap_options.item_selected.connect(_on_tonemap_selected)

	_connect_slider(exposure_slider, exposure_line, "exposure", 0.5, 2.0, 0.05)
	_connect_slider(dof_slider, dof_line, "dof_amount", 0.0, 0.5, 0.01)
	_connect_slider(motion_blur_slider, motion_blur_line, "motion_blur", 0.0, 1.5, 0.05)

	debanding_checkbox.toggled.connect(_on_debanding_toggled)
	ssao_options.item_selected.connect(_on_ssao_selected)
	ssi_options.item_selected.connect(_on_ssi_selected)
	ssr_options.item_selected.connect(_on_ssr_selected)
	sdfgi_options.item_selected.connect(_on_sdfgi_selected)
	fog_options.item_selected.connect(_on_fog_selected)
	glow_options.item_selected.connect(_on_glow_selected)


## Connects slider and LineEdit pairs with auto-clear and fallback handling.
## [param slider] Target [HSlider] node.
## [param line] Target [LineEdit] node.
## [param key] Setting key identifier.
## [param min_v] Minimum clamp limit.
## [param max_v] Maximum clamp limit.
## [param step_val] Step interval for the slider.
func _connect_slider(
	slider: HSlider, line: LineEdit, key: String, min_v: float, max_v: float, step_val: float
) -> void:
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_val

	slider.value_changed.connect(
		func(val: float) -> void:
			if not line.has_focus():
				line.text = "%.2f" % val
			GlobalSettings.save_setting("Settings", key, val)
			effects_settings_changed.emit()
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
				line.text = "%.2f" % s_val
				slider.value = s_val
				print("EffectsSection: Committed ", key, " input: ", s_val)
				GlobalSettings.save_setting("Settings", key, s_val)
				effects_settings_changed.emit()
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
				line.text = "%.2f" % s_val
				slider.value = s_val
				print("EffectsSection: Saved ", key, " on defocus: ", s_val)
				GlobalSettings.save_setting("Settings", key, s_val)
				effects_settings_changed.emit()
	)


## Synchronizes widgets with values persisted in [GlobalSettings].
func load_settings() -> void:
	print("EffectsSection: Loading effects settings from disk.")
	var saved_tonemap: String = _load_effect_setting("tonemap_mode", VideoConfig.DEFAULT_TONEMAP)
	_select_dropdown_text(tonemap_options, saved_tonemap)

	var exp_val: float = float(
		GlobalSettings.get_setting("Settings", "exposure", VideoConfig.DEFAULT_EXPOSURE)
	)
	exposure_slider.set_value_no_signal(exp_val)
	exposure_line.text = "%.2f" % exp_val

	var deband_val: bool = bool(GlobalSettings.get_setting("Settings", "debanding", true))
	debanding_checkbox.set_pressed_no_signal(deband_val)

	var dof_amt: float = float(GlobalSettings.get_setting("Settings", "dof_amount", 0.15))
	dof_slider.set_value_no_signal(dof_amt)
	dof_line.text = "%.2f" % dof_amt

	var mb_val: float = float(
		GlobalSettings.get_setting("Settings", "motion_blur", VideoConfig.DEFAULT_MOTION_BLUR)
	)
	motion_blur_slider.set_value_no_signal(mb_val)
	motion_blur_line.text = "%.2f" % mb_val

	var saved_ssao: String = _load_effect_setting("ssao", VideoConfig.DEFAULT_SSAO)
	_select_dropdown_text(ssao_options, saved_ssao)

	var saved_ssi: String = _load_effect_setting("ssi", VideoConfig.DEFAULT_SSI)
	_select_dropdown_text(ssi_options, saved_ssi)

	var saved_ssr: String = _load_effect_setting("ssr", VideoConfig.DEFAULT_SSR)
	_select_dropdown_text(ssr_options, saved_ssr)

	var saved_sdfgi: String = _load_effect_setting("sdfgi", VideoConfig.DEFAULT_SDFGI)
	_select_dropdown_text(sdfgi_options, saved_sdfgi)

	var saved_fog: String = _load_effect_setting("volumetric_fog", VideoConfig.DEFAULT_FOG)
	_select_dropdown_text(fog_options, saved_fog)

	var saved_glow: String = _load_effect_setting("glow", VideoConfig.DEFAULT_GLOW)
	_select_dropdown_text(glow_options, saved_glow)


## Safely reads an effect mode string, converting legacy booleans.
## [param key] Setting dictionary key.
## [param default_val] Fallback string mode.
func _load_effect_setting(key: String, default_val: String) -> String:
	print("EffectsSection: Resolving effect setting: ", key)
	var raw: Variant = GlobalSettings.get_setting("Settings", key, default_val)
	if raw is bool:
		var migrated: String = default_val if raw else "Off"
		GlobalSettings.save_setting("Settings", key, migrated)
		return migrated
	return str(raw)


## Updates dropdowns matching active preset data dictionary.
## [param data] Dictionary of environment flag configurations.
func apply_preset_dict(data: Dictionary) -> void:
	print("EffectsSection: Applying environment preset flags.")
	if data.has("dof_amount"):
		var dof_a: float = float(data["dof_amount"])
		dof_slider.set_value_no_signal(dof_a)
		dof_line.text = "%.2f" % dof_a
	elif data.has("dof_enabled"):
		var fallback_amt: float = 0.15 if bool(data["dof_enabled"]) else 0.0
		dof_slider.set_value_no_signal(fallback_amt)
		dof_line.text = "%.2f" % fallback_amt

	if data.has("motion_blur"):
		var mb_v: float = float(data["motion_blur"])
		motion_blur_slider.set_value_no_signal(mb_v)
		motion_blur_line.text = "%.2f" % mb_v

	if data.has("ssao"):
		_select_dropdown_text(ssao_options, data["ssao"] as String)
	if data.has("ssi"):
		_select_dropdown_text(ssi_options, data["ssi"] as String)
	if data.has("ssr"):
		_select_dropdown_text(ssr_options, data["ssr"] as String)
	if data.has("sdfgi"):
		_select_dropdown_text(sdfgi_options, data["sdfgi"] as String)
	if data.has("volumetric_fog"):
		_select_dropdown_text(fog_options, data["volumetric_fog"] as String)
	if data.has("glow"):
		_select_dropdown_text(glow_options, data["glow"] as String)


## Selects a dropdown item matching target label text.
## [param dropdown] The target [OptionButton].
## [param target_text] String label to find and select.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	print("EffectsSection: Selecting option: ", target_text, " on ", dropdown.name)
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Handles tonemap algorithm selection.
## [param index] Item index selected.
func _on_tonemap_selected(index: int) -> void:
	var text: String = tonemap_options.get_item_text(index)
	print("EffectsSection: Tonemap algorithm selected: ", text)
	GlobalSettings.save_setting("Settings", "tonemap_mode", text)
	effects_settings_changed.emit()


## Handles color debanding toggles.
## [param toggled_on] Whether debanding is enabled.
func _on_debanding_toggled(toggled_on: bool) -> void:
	print("EffectsSection: Debanding toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "debanding", toggled_on)
	effects_settings_changed.emit()


## Handles Screen Space Ambient Occlusion quality selection.
## [param index] Item index selected.
func _on_ssao_selected(index: int) -> void:
	var text: String = ssao_options.get_item_text(index)
	print("EffectsSection: SSAO quality selected: ", text)
	GlobalSettings.save_setting("Settings", "ssao", text)
	effects_settings_changed.emit()


## Handles Screen Space Indirect Lighting quality selection.
## [param index] Item index selected.
func _on_ssi_selected(index: int) -> void:
	var text: String = ssi_options.get_item_text(index)
	print("EffectsSection: SSIL quality selected: ", text)
	GlobalSettings.save_setting("Settings", "ssi", text)
	effects_settings_changed.emit()


## Handles Screen Space Reflections quality selection.
## [param index] Item index selected.
func _on_ssr_selected(index: int) -> void:
	var text: String = ssr_options.get_item_text(index)
	print("EffectsSection: SSR quality selected: ", text)
	GlobalSettings.save_setting("Settings", "ssr", text)
	effects_settings_changed.emit()


## Handles SDFGI quality selection.
## [param index] Item index selected.
func _on_sdfgi_selected(index: int) -> void:
	var text: String = sdfgi_options.get_item_text(index)
	print("EffectsSection: SDFGI quality selected: ", text)
	GlobalSettings.save_setting("Settings", "sdfgi", text)
	effects_settings_changed.emit()


## Handles volumetric fog quality selection.
## [param index] Item index selected.
func _on_fog_selected(index: int) -> void:
	var text: String = fog_options.get_item_text(index)
	print("EffectsSection: Volumetric fog quality selected: ", text)
	GlobalSettings.save_setting("Settings", "volumetric_fog", text)
	effects_settings_changed.emit()


## Handles glow effect quality selection.
## [param index] Item index selected.
func _on_glow_selected(index: int) -> void:
	var text: String = glow_options.get_item_text(index)
	print("EffectsSection: Glow quality selected: ", text)
	GlobalSettings.save_setting("Settings", "glow", text)
	effects_settings_changed.emit()
