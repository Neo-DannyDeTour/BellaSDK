## Controls tonemapping, exposure, debanding, DoF, motion blur, and environment effects.
class_name EffectsSection
extends VBoxContainer

## Emitted when any post-processing or environment effect setting changes.
@warning_ignore("unused_signal")
signal effects_settings_changed

## Valid tier labels for environment effect button rows.
const VALID_EFFECT_TIERS: Array[String] = ["Off", "Low", "Medium", "High"]

## Map associating SSAO tiers with their toggle buttons.
var _ssao_btn_map: Dictionary[String, Button] = {}

## Map associating SSIL tiers with their toggle buttons.
var _ssi_btn_map: Dictionary[String, Button] = {}

## Map associating SSR tiers with their toggle buttons.
var _ssr_btn_map: Dictionary[String, Button] = {}

## Map associating SDFGI tiers with their toggle buttons.
var _sdfgi_btn_map: Dictionary[String, Button] = {}

## Map associating volumetric fog tiers with their toggle buttons.
var _fog_btn_map: Dictionary[String, Button] = {}

## Map associating glow/bloom tiers with their toggle buttons.
var _glow_btn_map: Dictionary[String, Button] = {}

## Map associating volumetric clouds tiers with their toggle buttons.
var _clouds_btn_map: Dictionary[String, Button] = {}

## Tonemapper algorithm [OptionButton].
@onready var tonemap_options: OptionButton = %TonemapOptionButton

## Exposure direct numerical input [LineEdit].
@onready var exposure_line: LineEdit = %ExposureLine

## Exposure [HSlider].
@onready var exposure_slider: HSlider = %ExposureSlider

## Color debanding toggle [CheckBox].
@onready var debanding_checkbox: CheckBox = %DebandingCheckBox

## Depth of Field blur amount numerical input [LineEdit].
@onready var dof_line: LineEdit = %DoFLine

## Depth of Field blur amount [HSlider].
@onready var dof_slider: HSlider = %DoFSlider

## Camera motion blur strength [HSlider].
@onready var motion_blur_slider: HSlider = %MotionBlurSlider

## Camera motion blur strength numerical input [LineEdit].
@onready var motion_blur_line: LineEdit = %MotionBlurLine

## SSAO "Off" toggle [Button].
@onready var ssao_off_button: Button = %SSAOOffButton

## SSAO "Low" toggle [Button].
@onready var ssao_low_button: Button = %SSAOLowButton

## SSAO "Medium" toggle [Button].
@onready var ssao_medium_button: Button = %SSAOMediumButton

## SSAO "High" toggle [Button].
@onready var ssao_high_button: Button = %SSAOHighButton

## SSIL "Off" toggle [Button].
@onready var ssi_off_button: Button = %SSIOffButton

## SSIL "Low" toggle [Button].
@onready var ssi_low_button: Button = %SSILowButton

## SSIL "Medium" toggle [Button].
@onready var ssi_medium_button: Button = %SSIMediumButton

## SSIL "High" toggle [Button].
@onready var ssi_high_button: Button = %SSIHighButton

## SSR "Off" toggle [Button].
@onready var ssr_off_button: Button = %SSROffButton

## SSR "Low" toggle [Button].
@onready var ssr_low_button: Button = %SSRLowButton

## SSR "Medium" toggle [Button].
@onready var ssr_medium_button: Button = %SSRMediumButton

## SSR "High" toggle [Button].
@onready var ssr_high_button: Button = %SSRHighButton

## SDFGI "Off" toggle [Button].
@onready var sdfgi_off_button: Button = %SDFGIOffButton

## SDFGI "Low" toggle [Button].
@onready var sdfgi_low_button: Button = %SDFGILowButton

## SDFGI "Medium" toggle [Button].
@onready var sdfgi_medium_button: Button = %SDFGIMediumButton

## SDFGI "High" toggle [Button].
@onready var sdfgi_high_button: Button = %SDFGIHighButton

## Volumetric fog "Off" toggle [Button].
@onready var fog_off_button: Button = %FogOffButton

## Volumetric fog "Low" toggle [Button].
@onready var fog_low_button: Button = %FogLowButton

## Volumetric fog "Medium" toggle [Button].
@onready var fog_medium_button: Button = %FogMediumButton

## Volumetric fog "High" toggle [Button].
@onready var fog_high_button: Button = %FogHighButton

## Glow "Off" toggle [Button].
@onready var glow_off_button: Button = %GlowOffButton

## Glow "Low" toggle [Button].
@onready var glow_low_button: Button = %GlowLowButton

## Glow "Medium" toggle [Button].
@onready var glow_medium_button: Button = %GlowMediumButton

## Glow "High" toggle [Button].
@onready var glow_high_button: Button = %GlowHighButton

## Clouds "Off" toggle [Button].
@onready var clouds_off_button: Button = %CloudsOffButton

## Clouds "Low" toggle [Button].
@onready var clouds_low_button: Button = %CloudsLowButton

## Clouds "Medium" toggle [Button].
@onready var clouds_medium_button: Button = %CloudsMediumButton

## Clouds "High" toggle [Button].
@onready var clouds_high_button: Button = %CloudsHighButton


## Initializes effect button groups, tonemap dropdown, and live signal listeners.
func _ready() -> void:
	print("EffectsSection: Initializing effects settings UI.")
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(clouds_off_button), "EffectsSection: Missing %CloudsOffButton.")
	assert(is_instance_valid(clouds_low_button), "EffectsSection: Missing %CloudsLowButton.")
	assert(is_instance_valid(clouds_medium_button), "EffectsSection: Missing %CloudsMediumButton.")
	assert(is_instance_valid(clouds_high_button), "EffectsSection: Missing %CloudsHighButton.")
	_setup_button_mappings()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Synchronizes all effect widgets with saved settings without emitting signals.
func load_settings() -> void:
	print("EffectsSection: Synchronizing effects UI with active configuration.")
	var saved_tonemap: String = str(
		GlobalSettings.get_setting("Settings", "tonemap_mode", VideoConfig.DEFAULT_TONEMAP)
	)
	if not VideoConfig.TONEMAP_MODES.has(saved_tonemap):
		saved_tonemap = VideoConfig.DEFAULT_TONEMAP
	_select_dropdown_text(tonemap_options, saved_tonemap)

	var exp_val: float = GlobalSettings.get_setting_float(
		"Settings", "exposure", VideoConfig.DEFAULT_EXPOSURE
	)
	exposure_slider.set_value_no_signal(exp_val)
	exposure_line.text = "%.2f" % exp_val

	var deband_val: bool = GlobalSettings.get_setting_bool(
		"Settings", "debanding", VideoConfig.DEFAULT_DEBANDING
	)
	debanding_checkbox.set_pressed_no_signal(deband_val)

	var dof_enabled: bool = GlobalSettings.get_setting_bool(
		"Settings", "dof_enabled", VideoConfig.DEFAULT_DOF
	)
	var dof_amt: float = GlobalSettings.get_setting_float(
		"Settings", "dof_amount", VideoConfig.DEFAULT_DOF_AMOUNT
	)
	var effective_dof: float = dof_amt if dof_enabled else 0.0
	dof_slider.set_value_no_signal(effective_dof)
	dof_line.text = "%.2f" % effective_dof

	var mb_val: float = GlobalSettings.get_setting_float(
		"Settings", "motion_blur", VideoConfig.DEFAULT_MOTION_BLUR
	)
	motion_blur_slider.set_value_no_signal(mb_val)
	motion_blur_line.text = "%.2f" % mb_val

	_sync_button_row(_ssao_btn_map, "ssao", VideoConfig.DEFAULT_SSAO)
	_sync_button_row(_ssi_btn_map, "ssi", VideoConfig.DEFAULT_SSI)
	_sync_button_row(_ssr_btn_map, "ssr", VideoConfig.DEFAULT_SSR)
	_sync_button_row(_sdfgi_btn_map, "sdfgi", VideoConfig.DEFAULT_SDFGI)
	_sync_button_row(_fog_btn_map, "volumetric_fog", VideoConfig.DEFAULT_FOG)
	_sync_button_row(_glow_btn_map, "glow", VideoConfig.DEFAULT_GLOW)
	_sync_button_row(_clouds_btn_map, "clouds", VideoConfig.DEFAULT_CLOUDS)


## Updates local effect widgets from a preset dictionary without emitting signals.
func apply_preset_dict(data: Dictionary) -> void:
	if data.has("tonemap_mode"):
		_select_dropdown_text(tonemap_options, str(data["tonemap_mode"]))
	if data.has("exposure"):
		var exp_v: float = VideoApplier._get_float(data, "exposure", 1.0)
		exposure_slider.set_value_no_signal(exp_v)
		exposure_line.text = "%.2f" % exp_v
	if data.has("debanding"):
		debanding_checkbox.set_pressed_no_signal(VideoApplier._get_bool(data, "debanding", true))

	if data.has("dof_amount") or data.has("dof_enabled"):
		var dof_on: bool = VideoApplier._get_bool(data, "dof_enabled", false)
		var dof_a: float = VideoApplier._get_float(
			data, "dof_amount", VideoConfig.DEFAULT_DOF_AMOUNT if dof_on else 0.0
		)
		var effective: float = dof_a if dof_on else 0.0
		dof_slider.set_value_no_signal(effective)
		dof_line.text = "%.2f" % effective

	if data.has("motion_blur"):
		var mb_v: float = VideoApplier._get_float(data, "motion_blur", 0.0)
		motion_blur_slider.set_value_no_signal(mb_v)
		motion_blur_line.text = "%.2f" % mb_v

	if data.has("ssao"):
		_set_group_button_silent(_ssao_btn_map, str(data["ssao"]))
	if data.has("ssi"):
		_set_group_button_silent(_ssi_btn_map, str(data["ssi"]))
	if data.has("ssr"):
		_set_group_button_silent(_ssr_btn_map, str(data["ssr"]))
	if data.has("sdfgi"):
		_set_group_button_silent(_sdfgi_btn_map, str(data["sdfgi"]))
	if data.has("volumetric_fog"):
		_set_group_button_silent(_fog_btn_map, str(data["volumetric_fog"]))
	if data.has("glow"):
		_set_group_button_silent(_glow_btn_map, str(data["glow"]))
	if data.has("clouds"):
		_set_group_button_silent(_clouds_btn_map, str(data["clouds"]))


## Configures button group mappings for SSAO, SSIL, SSR, SDFGI, Fog, Glow, and Clouds rows.
func _setup_button_mappings() -> void:
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

	_clouds_btn_map = {
		"Off": clouds_off_button,
		"Low": clouds_low_button,
		"Medium": clouds_medium_button,
		"High": clouds_high_button,
	}
	_setup_group(_clouds_btn_map)


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


## Populates tonemapper dropdown options from [VideoConfig].
func _populate_dropdowns() -> void:
	tonemap_options.clear()
	for key: String in VideoConfig.TONEMAP_MODES.keys():
		tonemap_options.add_item(key)


## Connects all effect buttons, checkboxes, dropdowns, and sliders.
func _connect_signals() -> void:
	tonemap_options.item_selected.connect(_on_tonemap_selected)
	debanding_checkbox.toggled.connect(_on_debanding_toggled)

	_connect_slider(exposure_slider, exposure_line, "exposure", 0.5, 2.0, 0.05)
	_connect_dof_slider()
	_connect_slider(motion_blur_slider, motion_blur_line, "motion_blur", 0.0, 1.5, 0.05)

	_connect_button_row(_ssao_btn_map, "ssao")
	_connect_button_row(_ssi_btn_map, "ssi")
	_connect_button_row(_ssr_btn_map, "ssr")
	_connect_button_row(_sdfgi_btn_map, "sdfgi")
	_connect_button_row(_fog_btn_map, "volumetric_fog")
	_connect_button_row(_glow_btn_map, "glow")
	_connect_button_row(_clouds_btn_map, "clouds")


## Connects button presses in [param mapping] to [param config_key].
func _connect_button_row(mapping: Dictionary[String, Button], config_key: String) -> void:
	for mode_key: String in mapping.keys():
		var btn: Button = mapping[mode_key]
		if is_instance_valid(btn):
			btn.pressed.connect(_on_effect_button_pressed.bind(config_key, mode_key))


## Connects the Depth of Field slider and numerical [LineEdit] for instant feedback.
func _connect_dof_slider() -> void:
	dof_slider.min_value = 0.0
	dof_slider.max_value = 0.5
	dof_slider.step = 0.01

	dof_slider.value_changed.connect(
		func(val: float) -> void:
			if not dof_line.has_focus():
				dof_line.text = "%.2f" % val
			_commit_dof_value(val)
	)

	dof_line.focus_entered.connect(
		func() -> void:
			dof_line.set_meta("pre_focus_text", dof_line.text)
			dof_line.text = ""
	)

	dof_line.text_submitted.connect(
		func(_text: String) -> void:
			_commit_dof_line()
			dof_line.release_focus()
	)

	dof_line.focus_exited.connect(func() -> void: _commit_dof_line())


## Commits DoF amount and enabled state directly to [GraphicsManager].
func _commit_dof_value(amt: float) -> void:
	var is_active: bool = amt > 0.005
	GraphicsManager.set_setting("dof_enabled", is_active, false)
	GraphicsManager.set_setting("dof_amount", amt, true)
	effects_settings_changed.emit()


## Validates and commits manual DoF text input.
func _commit_dof_line() -> void:
	var trimmed: String = dof_line.text.strip_edges()
	var fallback: String = str(dof_line.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		dof_line.text = fallback
		return

	var amt: float = snappedf(clampf(trimmed.to_float(), 0.0, 0.5), 0.01)
	var formatted: String = "%.2f" % amt
	dof_line.text = formatted
	dof_line.set_meta("pre_focus_text", formatted)
	dof_slider.set_value_no_signal(amt)
	_commit_dof_value(amt)


## Connects an [HSlider] and [LineEdit] pair for instant real-time diorama updates.
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
			GraphicsManager.set_setting(key, val)
			effects_settings_changed.emit()
	)

	line.focus_entered.connect(
		func() -> void:
			line.set_meta("pre_focus_text", line.text)
			line.text = ""
	)

	line.text_submitted.connect(
		func(_text: String) -> void:
			_commit_effect_line(slider, line, key, min_v, max_v, step_val)
			line.release_focus()
	)

	line.focus_exited.connect(
		func() -> void: _commit_effect_line(slider, line, key, min_v, max_v, step_val)
	)


## Validates and commits manual [LineEdit] numerical input for effect sliders.
func _commit_effect_line(
	slider: HSlider, line: LineEdit, key: String, min_v: float, max_v: float, step_val: float
) -> void:
	var trimmed: String = line.text.strip_edges()
	var fallback: String = str(line.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		line.text = fallback
		return

	var clamped: float = snappedf(clampf(trimmed.to_float(), min_v, max_v), step_val)
	var formatted: String = "%.2f" % clamped
	line.text = formatted
	line.set_meta("pre_focus_text", formatted)
	slider.set_value_no_signal(clamped)
	GraphicsManager.set_setting(key, clamped)
	effects_settings_changed.emit()


## Syncs an effect button row with saved settings silently.
func _sync_button_row(
	mapping: Dictionary[String, Button], config_key: String, default_val: String
) -> void:
	var saved: String = str(GlobalSettings.get_setting("Settings", config_key, default_val))
	var resolved: String = saved if VALID_EFFECT_TIERS.has(saved) else default_val
	_set_group_button_silent(mapping, resolved)


## Activates the button matching [param target_key] without firing signals.
func _set_group_button_silent(mapping: Dictionary[String, Button], target_key: String) -> void:
	var resolved_key: String = target_key if mapping.has(target_key) else "Off"
	for key: String in mapping.keys():
		var btn: Button = mapping[key]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(key == resolved_key)


## Selects the dropdown item matching [param target_text].
func _select_dropdown_text(dropdown: OptionButton, target_text: String) -> void:
	for idx: int in range(dropdown.get_item_count()):
		if dropdown.get_item_text(idx) == target_text:
			dropdown.select(idx)
			return


## Handles tonemapper dropdown selection.
func _on_tonemap_selected(index: int) -> void:
	var label: String = tonemap_options.get_item_text(index)
	print("EffectsSection: Player selected tonemap mode -> ", label)
	GraphicsManager.set_setting("tonemap_mode", label)
	effects_settings_changed.emit()


## Handles color debanding checkbox toggle.
func _on_debanding_toggled(toggled_on: bool) -> void:
	print("EffectsSection: Player toggled debanding -> ", toggled_on)
	GraphicsManager.set_setting("debanding", toggled_on)
	effects_settings_changed.emit()


## Handles effect tier button selection.
func _on_effect_button_pressed(config_key: String, mode_key: String) -> void:
	print("EffectsSection: Player selected ", config_key, " -> ", mode_key)
	GraphicsManager.set_setting(config_key, mode_key)
	effects_settings_changed.emit()
