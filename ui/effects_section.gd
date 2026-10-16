## Controls post-processing, tonemapping, and environment visual effects.
class_name EffectsSection
extends VBoxContainer

# --------------------------------------
# SIGNALS
# --------------------------------------
## Emitted when effect options change to trigger viewport environment updates.
@warning_ignore("unused_signal")
signal effects_settings_changed

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Valid quality tier keys for multi-button environment effect rows.
const VALID_EFFECT_TIERS: Array[String] = ["Off", "Low", "Medium", "High"]

## Default Depth of Field blur amount when enabled via preset.
const DEFAULT_ACTIVE_DOF_AMOUNT: float = 0.15

# --------------------------------------
# RUNTIME LOOKUP MAPPINGS
# --------------------------------------
## Lookup map associating SSAO mode keys with toggle buttons.
var _ssao_btn_map: Dictionary[String, Button] = {}

## Lookup map associating SSIL mode keys with toggle buttons.
var _ssi_btn_map: Dictionary[String, Button] = {}

## Lookup map associating SSR mode keys with toggle buttons.
var _ssr_btn_map: Dictionary[String, Button] = {}

## Lookup map associating SDFGI mode keys with toggle buttons.
var _sdfgi_btn_map: Dictionary[String, Button] = {}

## Lookup map associating volumetric fog mode keys with toggle buttons.
var _fog_btn_map: Dictionary[String, Button] = {}

## Lookup map associating glow mode keys with toggle buttons.
var _glow_btn_map: Dictionary[String, Button] = {}

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
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


## Populates tonemapper algorithms and hooks widget state listeners.
func _ready() -> void:
	print("EffectsSection: Initializing effects UI.")
	set_process(false)
	set_physics_process(false)
	_setup_button_mappings()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Configures [ButtonGroup] instances and dictionary mappings for effect rows.
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
		if not is_instance_valid(btn):
			continue
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


## Connects pressed events for each button in a dictionary to save settings.
func _connect_button_row(mapping: Dictionary[String, Button], config_key: String) -> void:
	for mode_key: String in mapping.keys():
		var btn: Button = mapping[mode_key]
		if is_instance_valid(btn):
			btn.pressed.connect(_on_effect_button_pressed.bind(config_key, mode_key))


## Connects DoF slider and [LineEdit] with single-dispatch commit logic.
func _connect_dof_slider() -> void:
	print("EffectsSection: Connecting specialized DoF slider.")
	dof_slider.min_value = 0.0
	dof_slider.max_value = 0.5
	dof_slider.step = 0.01

	dof_slider.value_changed.connect(
		func(val: float) -> void:
			if not dof_line.has_focus():
				dof_line.text = "%.2f" % val
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_commit_dof_value(val)
	)

	dof_slider.drag_ended.connect(
		func(value_changed: bool) -> void:
			if value_changed:
				print("EffectsSection: Committed DoF drag: ", dof_slider.value)
				_commit_dof_value(dof_slider.value)
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


## Persists DoF amount and enabled state if value changed.
func _commit_dof_value(amt: float) -> void:
	var current: float = GlobalSettings.get_setting_float("Settings", "dof_amount", -1.0)
	var is_active: bool = amt > 0.005
	var current_enabled: bool = GlobalSettings.get_setting_bool(
		"Settings", "dof_enabled", not is_active
	)
	if not is_equal_approx(current, amt) or current_enabled != is_active:
		GlobalSettings.save_setting("Settings", "dof_amount", amt)
		GlobalSettings.save_setting("Settings", "dof_enabled", is_active)
		effects_settings_changed.emit()


## Commits manual text input to DoF slider and settings without double-emitting.
func _commit_dof_line() -> void:
	var trimmed: String = dof_line.text.strip_edges()
	var fallback: String = str(dof_line.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		dof_line.text = fallback
		return

	var amt: float = clampf(trimmed.to_float(), 0.0, 0.5)
	var formatted: String = "%.2f" % amt
	dof_line.text = formatted
	dof_line.set_meta("pre_focus_text", formatted)

	var current: float = GlobalSettings.get_setting_float("Settings", "dof_amount", -1.0)
	dof_slider.set_value_no_signal(amt)

	var is_active: bool = amt > 0.005
	var current_enabled: bool = GlobalSettings.get_setting_bool(
		"Settings", "dof_enabled", not is_active
	)
	if not is_equal_approx(current, amt) or current_enabled != is_active:
		print("EffectsSection: Committed new DoF text input: ", amt)
		GlobalSettings.save_setting("Settings", "dof_amount", amt)
		GlobalSettings.save_setting("Settings", "dof_enabled", is_active)
		effects_settings_changed.emit()


## Connects slider and [LineEdit] pairs with deferred save and signal dispatch.
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
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_commit_effect_slider_value(key, val)
	)

	slider.drag_ended.connect(
		func(value_changed: bool) -> void:
			if value_changed:
				print("EffectsSection: Drag ended for ", key, " -> ", slider.value)
				_commit_effect_slider_value(key, slider.value)
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


## Persists effect slider value if modified from storage.
func _commit_effect_slider_value(key: String, val: float) -> void:
	var current: float = GlobalSettings.get_setting_float("Settings", key, -999.0)
	if not is_equal_approx(current, val):
		print("EffectsSection: Persisting ", key, " -> ", val)
		GlobalSettings.save_setting("Settings", key, val)
		effects_settings_changed.emit()


## Commits [LineEdit] input to effect slider and settings safely.
func _commit_effect_line(
	slider: HSlider, line: LineEdit, key: String, min_v: float, max_v: float, step_val: float
) -> void:
	var trimmed: String = line.text.strip_edges()
	var fallback: String = str(line.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		line.text = fallback
		return

	var c_val: float = clampf(trimmed.to_float(), min_v, max_v)
	var s_val: float = snappedf(c_val, step_val)
	var formatted: String = "%.2f" % s_val
	line.text = formatted
	line.set_meta("pre_focus_text", formatted)

	var current: float = GlobalSettings.get_setting_float("Settings", key, -999.0)
	slider.set_value_no_signal(s_val)

	if not is_equal_approx(current, s_val):
		print("EffectsSection: Committed new ", key, " text input: ", s_val)
		GlobalSettings.save_setting("Settings", key, s_val)
		effects_settings_changed.emit()


## Synchronizes widgets with values persisted in [GlobalSettings].
func load_settings() -> void:
	print("EffectsSection: Loading effects settings from disk.")
	var raw_tonemap: Variant = GlobalSettings.get_setting(
		"Settings", "tonemap_mode", VideoConfig.DEFAULT_TONEMAP
	)
	var saved_tonemap: String = (
		raw_tonemap
		if (raw_tonemap is String and VideoConfig.TONEMAP_MODES.has(raw_tonemap))
		else VideoConfig.DEFAULT_TONEMAP
	)
	_select_dropdown_text(tonemap_options, saved_tonemap)

	var exp_val: float = GlobalSettings.get_setting_float(
		"Settings", "exposure", VideoConfig.DEFAULT_EXPOSURE
	)
	exposure_slider.set_value_no_signal(exp_val)
	exposure_line.text = "%.2f" % exp_val

	var deband_val: bool = GlobalSettings.get_setting_bool("Settings", "debanding", true)
	debanding_checkbox.set_pressed_no_signal(deband_val)

	var raw_dof_amt: float = GlobalSettings.get_setting_float(
		"Settings", "dof_amount", DEFAULT_ACTIVE_DOF_AMOUNT
	)
	var dof_enabled: bool = GlobalSettings.get_setting_bool(
		"Settings", "dof_enabled", VideoConfig.DEFAULT_DOF
	)
	var effective_dof: float = raw_dof_amt if dof_enabled else 0.0
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


## Reads a persisted setting and activates the matching button without signals.
func _sync_button_row(
	mapping: Dictionary[String, Button], config_key: String, default_val: String
) -> void:
	var mode: String = _load_effect_setting(config_key, default_val)
	_set_group_button_silent(mapping, mode)


## Sets the active button in [param mapping] matching [param target_key] silently.
func _set_group_button_silent(mapping: Dictionary[String, Button], target_key: String) -> void:
	var resolved_key: String = target_key if mapping.has(target_key) else "Off"
	for key: String in mapping.keys():
		var btn: Button = mapping[key]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(key == resolved_key)


## Safely reads an effect mode string, migrating booleans and invalid values.
func _load_effect_setting(key: String, default_val: String) -> String:
	var fallback: String = default_val if VALID_EFFECT_TIERS.has(default_val) else "Off"
	var raw: Variant = GlobalSettings.get_setting("Settings", key, fallback)

	if raw is bool:
		var active_tier: String = (
			fallback if (fallback != "Off" and not fallback.is_empty()) else "Medium"
		)
		var migrated: String = active_tier if (raw as bool) else "Off"
		GlobalSettings.save_setting("Settings", key, migrated)
		return migrated

	var str_val: String = str(raw)
	if VALID_EFFECT_TIERS.has(str_val):
		return str_val

	if not default_val.is_empty():
		GlobalSettings.save_setting("Settings", key, fallback)
	return fallback


## Updates widgets matching active preset data dictionary without signal storms.
func apply_preset_dict(data: Dictionary) -> void:
	print("EffectsSection: Applying environment preset flags.")
	if data.has("dof_amount"):
		var raw_dof: Variant = data["dof_amount"]
		var dof_a: float = 0.0
		if raw_dof is float:
			dof_a = raw_dof
		elif raw_dof is int:
			var int_dof: int = raw_dof
			dof_a = float(int_dof)
		dof_slider.set_value_no_signal(dof_a)
		dof_line.text = "%.2f" % dof_a
		GlobalSettings.save_setting("Settings", "dof_amount", dof_a)
		GlobalSettings.save_setting("Settings", "dof_enabled", dof_a > 0.005)
	elif data.has("dof_enabled"):
		var raw_enabled: Variant = data["dof_enabled"]
		var is_dof_on: bool = raw_enabled == true
		var fallback_amt: float = DEFAULT_ACTIVE_DOF_AMOUNT if is_dof_on else 0.0
		dof_slider.set_value_no_signal(fallback_amt)
		dof_line.text = "%.2f" % fallback_amt
		GlobalSettings.save_setting("Settings", "dof_amount", fallback_amt)
		GlobalSettings.save_setting("Settings", "dof_enabled", is_dof_on)

	if data.has("motion_blur"):
		var raw_mb: Variant = data["motion_blur"]
		var mb_v: float = 0.0
		if raw_mb is float:
			mb_v = raw_mb
		elif raw_mb is int:
			var int_mb: int = raw_mb
			mb_v = float(int_mb)
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
	var current: String = str(GlobalSettings.get_setting("Settings", "tonemap_mode", ""))
	if current != text:
		GlobalSettings.save_setting("Settings", "tonemap_mode", text)
		effects_settings_changed.emit()


## Handles color debanding toggles.
func _on_debanding_toggled(toggled_on: bool) -> void:
	print("EffectsSection: Debanding toggled: ", toggled_on)
	var current: bool = GlobalSettings.get_setting_bool("Settings", "debanding", not toggled_on)
	if current != toggled_on:
		GlobalSettings.save_setting("Settings", "debanding", toggled_on)
		effects_settings_changed.emit()


## Handles any effect button press, saving setting and notifying pipeline.
func _on_effect_button_pressed(config_key: String, mode_key: String) -> void:
	print("EffectsSection: Pressed ", config_key, " -> ", mode_key)
	var current_val: String = str(GlobalSettings.get_setting("Settings", config_key, ""))
	if current_val != mode_key:
		GlobalSettings.save_setting("Settings", config_key, mode_key)
		effects_settings_changed.emit()
