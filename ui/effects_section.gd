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

## SSAO toggle buttons.
@onready var ssao_off_button: Button = %SSAOOffButton
@onready var ssao_low_button: Button = %SSAOLowButton
@onready var ssao_medium_button: Button = %SSAOMediumButton
@onready var ssao_high_button: Button = %SSAOHighButton

## SSIL toggle buttons.
@onready var ssi_off_button: Button = %SSIOffButton
@onready var ssi_low_button: Button = %SSILowButton
@onready var ssi_medium_button: Button = %SSIMediumButton
@onready var ssi_high_button: Button = %SSIHighButton

## SSR toggle buttons.
@onready var ssr_off_button: Button = %SSROffButton
@onready var ssr_low_button: Button = %SSRLowButton
@onready var ssr_medium_button: Button = %SSRMediumButton
@onready var ssr_high_button: Button = %SSRHighButton

## SDFGI toggle buttons.
@onready var sdfgi_off_button: Button = %SDFGIOffButton
@onready var sdfgi_low_button: Button = %SDFGILowButton
@onready var sdfgi_medium_button: Button = %SDFGIMediumButton
@onready var sdfgi_high_button: Button = %SDFGIHighButton

## Volumetric fog toggle buttons.
@onready var fog_off_button: Button = %FogOffButton
@onready var fog_low_button: Button = %FogLowButton
@onready var fog_medium_button: Button = %FogMediumButton
@onready var fog_high_button: Button = %FogHighButton

## Glow toggle buttons.
@onready var glow_off_button: Button = %GlowOffButton
@onready var glow_low_button: Button = %GlowLowButton
@onready var glow_medium_button: Button = %GlowMediumButton
@onready var glow_high_button: Button = %GlowHighButton

## Internal lookup maps associating mode keys with their respective toggle buttons.
var _ssao_btn_map: Dictionary[String, Button] = {}
var _ssi_btn_map: Dictionary[String, Button] = {}
var _ssr_btn_map: Dictionary[String, Button] = {}
var _sdfgi_btn_map: Dictionary[String, Button] = {}
var _fog_btn_map: Dictionary[String, Button] = {}
var _glow_btn_map: Dictionary[String, Button] = {}


## Populates tonemapper algorithms and hooks widget state listeners.
func _ready() -> void:
	print("EffectsSection: Initializing effects UI.")
	_setup_button_mappings()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Configures ButtonGroups and dictionary mappings for all multi-button effect rows.
func _setup_button_mappings() -> void:
	print("EffectsSection: Configuring button groups and mapping lookups.")
	_ssao_btn_map = {
		"Off": ssao_off_button,
		"Low": ssao_low_button,
		"Medium": ssao_medium_button,
		"High": ssao_high_button,
	}
	_setup_group(_ssao_btn_map)

	_ssi_btn_map = {
		"Off": ssi_off_button,
		"Low": ssi_low_button,
		"Medium": ssi_medium_button,
		"High": ssi_high_button,
	}
	_setup_group(_ssi_btn_map)

	_ssr_btn_map = {
		"Off": ssr_off_button,
		"Low": ssr_low_button,
		"Medium": ssr_medium_button,
		"High": ssr_high_button,
	}
	_setup_group(_ssr_btn_map)

	_sdfgi_btn_map = {
		"Off": sdfgi_off_button,
		"Low": sdfgi_low_button,
		"Medium": sdfgi_medium_button,
		"High": sdfgi_high_button,
	}
	_setup_group(_sdfgi_btn_map)

	_fog_btn_map = {
		"Off": fog_off_button,
		"Low": fog_low_button,
		"Medium": fog_medium_button,
		"High": fog_high_button,
	}
	_setup_group(_fog_btn_map)

	_glow_btn_map = {
		"Off": glow_off_button,
		"Low": glow_low_button,
		"Medium": glow_medium_button,
		"High": glow_high_button,
	}
	_setup_group(_glow_btn_map)


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


## Populates standalone dropdown widgets with options declared in [VideoConfig].
func _populate_dropdowns() -> void:
	print("EffectsSection: Populating tonemap options.")
	tonemap_options.clear()
	for key: Variant in VideoConfig.TONEMAP_MODES.keys():
		tonemap_options.add_item(str(key))


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("EffectsSection: Connecting effect UI signals.")
	tonemap_options.item_selected.connect(_on_tonemap_selected)

	_connect_slider(exposure_slider, exposure_line, "exposure", 0.5, 2.0, 0.05)
	_connect_dof_slider()
	_connect_slider(motion_blur_slider, motion_blur_line, "motion_blur", 0.0, 1.5, 0.05)

	debanding_checkbox.toggled.connect(_on_debanding_toggled)

	_connect_button_row(_ssao_btn_map, "ssao")
	_connect_button_row(_ssi_btn_map, "ssi")
	_connect_button_row(_ssr_btn_map, "ssr")
	_connect_button_row(_sdfgi_btn_map, "sdfgi")
	_connect_button_row(_fog_btn_map, "volumetric_fog")
	_connect_button_row(_glow_btn_map, "glow")


## Connects pressed events for each button in a dictionary to save and emit settings.
func _connect_button_row(mapping: Dictionary[String, Button], config_key: String) -> void:
	for mode_key: String in mapping.keys():
		var btn: Button = mapping[mode_key]
		btn.pressed.connect(_on_effect_button_pressed.bind(config_key, mode_key))


## Connects DoF slider and line edit, setting dof_enabled based on magnitude.
func _connect_dof_slider() -> void:
	print("EffectsSection: Connecting specialized DoF slider.")
	dof_slider.min_value = 0.0
	dof_slider.max_value = 0.5
	dof_slider.step = 0.01

	dof_slider.value_changed.connect(
		func(val: float) -> void:
			if not dof_line.has_focus():
				dof_line.text = "%.2f" % val
	)

	dof_slider.drag_ended.connect(
		func(value_changed: bool) -> void:
			if value_changed:
				var amt: float = dof_slider.value
				var is_active: bool = amt > 0.005
				print("EffectsSection: Committed DoF amount: ", amt, " Active: ", is_active)
				GlobalSettings.save_setting("Settings", "dof_amount", amt)
				GlobalSettings.save_setting("Settings", "dof_enabled", is_active)
				effects_settings_changed.emit()
	)

	dof_line.text_submitted.connect(
		func(text: String) -> void:
			var trimmed: String = text.strip_edges()
			if trimmed.is_valid_float():
				var amt: float = clampf(trimmed.to_float(), 0.0, 0.5)
				var is_active: bool = amt > 0.005
				dof_line.text = "%.2f" % amt
				dof_slider.value = amt
				GlobalSettings.save_setting("Settings", "dof_amount", amt)
				GlobalSettings.save_setting("Settings", "dof_enabled", is_active)
				effects_settings_changed.emit()
			dof_line.release_focus()
	)


## Connects slider and LineEdit pairs with deferred save and signal dispatch.
func _connect_slider(
	slider: HSlider, line: LineEdit, key: String, min_v: float, max_v: float, step_val: float
) -> void:
	if not is_instance_valid(slider) or not is_instance_valid(line):
		return
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_val

	slider.value_changed.connect(
		func(val: float) -> void:
			if not line.has_focus():
				line.text = "%.2f" % val
	)

	slider.drag_ended.connect(
		func(value_changed: bool) -> void:
			if value_changed:
				print("EffectsSection: Drag ended for ", key, " -> ", slider.value)
				GlobalSettings.save_setting("Settings", key, slider.value)
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

	_sync_button_row(_ssao_btn_map, "ssao", VideoConfig.DEFAULT_SSAO)
	_sync_button_row(_ssi_btn_map, "ssi", VideoConfig.DEFAULT_SSI)
	_sync_button_row(_ssr_btn_map, "ssr", VideoConfig.DEFAULT_SSR)
	_sync_button_row(_sdfgi_btn_map, "sdfgi", VideoConfig.DEFAULT_SDFGI)
	_sync_button_row(_fog_btn_map, "volumetric_fog", VideoConfig.DEFAULT_FOG)
	_sync_button_row(_glow_btn_map, "glow", VideoConfig.DEFAULT_GLOW)


## Reads a persisted setting and activates the corresponding toggle button in the row.
func _sync_button_row(
	mapping: Dictionary[String, Button], config_key: String, default_val: String
) -> void:
	var mode: String = _load_effect_setting(config_key, default_val)
	for key: String in mapping.keys():
		mapping[key].button_pressed = (key == mode)


## Safely reads an effect mode string, converting legacy booleans.
func _load_effect_setting(key: String, default_val: String) -> String:
	var raw: Variant = GlobalSettings.get_setting("Settings", key, default_val)
	if raw is bool:
		var migrated: String = default_val if raw else "Off"
		GlobalSettings.save_setting("Settings", key, migrated)
		return migrated
	return str(raw)


## Updates widgets matching active preset data dictionary.
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

	if data.has("ssao") and _ssao_btn_map.has(str(data["ssao"])):
		_ssao_btn_map[str(data["ssao"])].button_pressed = true
	if data.has("ssi") and _ssi_btn_map.has(str(data["ssi"])):
		_ssi_btn_map[str(data["ssi"])].button_pressed = true
	if data.has("ssr") and _ssr_btn_map.has(str(data["ssr"])):
		_ssr_btn_map[str(data["ssr"])].button_pressed = true
	if data.has("sdfgi") and _sdfgi_btn_map.has(str(data["sdfgi"])):
		_sdfgi_btn_map[str(data["sdfgi"])].button_pressed = true
	if data.has("volumetric_fog") and _fog_btn_map.has(str(data["volumetric_fog"])):
		_fog_btn_map[str(data["volumetric_fog"])].button_pressed = true
	if data.has("glow") and _glow_btn_map.has(str(data["glow"])):
		_glow_btn_map[str(data["glow"])].button_pressed = true


## Selects a dropdown item matching target label text.
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	for i: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(i) == target_text:
			dropdown.select(i)
			return


## Handles tonemap algorithm selection.
func _on_tonemap_selected(index: int) -> void:
	var text: String = tonemap_options.get_item_text(index)
	print("EffectsSection: Tonemap algorithm selected: ", text)
	GlobalSettings.save_setting("Settings", "tonemap_mode", text)
	effects_settings_changed.emit()


## Handles color debanding toggles.
func _on_debanding_toggled(toggled_on: bool) -> void:
	print("EffectsSection: Debanding toggled: ", toggled_on)
	GlobalSettings.save_setting("Settings", "debanding", toggled_on)
	effects_settings_changed.emit()


## Handles any effect button press, saving setting and notifying pipeline.
func _on_effect_button_pressed(config_key: String, mode_key: String) -> void:
	print("EffectsSection: Pressed ", config_key, " -> ", mode_key)
	var current_val: String = _load_effect_setting(config_key, "")
	if current_val != mode_key:
		GlobalSettings.save_setting("Settings", config_key, mode_key)
		effects_settings_changed.emit()
