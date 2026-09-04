## Controls post-processing, tonemapping, and environment visual effects.
class_name EffectsSection
extends VBoxContainer

## Emitted when effect options change to trigger viewport environment updates.
signal effects_settings_changed

## Reference to the tonemapper algorithm [OptionButton].
@onready var tonemap_options: OptionButton = %TonemapOptionButton
## Reference to the color debanding toggle [CheckBox].
@onready var debanding_checkbox: CheckBox = %DebandingCheckBox
## Reference to the Screen Space Ambient Occlusion quality [OptionButton].
@onready var ssao_options: OptionButton = %SSAOOptionButton
## Reference to the Screen Space Indirect Lighting quality [OptionButton].
@onready var ssi_options: OptionButton = %SSIOptionButton
## Reference to the Screen Space Reflections quality [OptionButton].
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
	print("EffectsSection: Populating options for ", button.name)
	button.clear()
	for key: Variant in source.keys():
		button.add_item(str(key))


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("EffectsSection: Connecting effect UI signals.")
	tonemap_options.item_selected.connect(_on_tonemap_selected)
	debanding_checkbox.toggled.connect(_on_debanding_toggled)
	ssao_options.item_selected.connect(_on_ssao_selected)
	ssi_options.item_selected.connect(_on_ssi_selected)
	ssr_options.item_selected.connect(_on_ssr_selected)
	sdfgi_options.item_selected.connect(_on_sdfgi_selected)
	fog_options.item_selected.connect(_on_fog_selected)
	glow_options.item_selected.connect(_on_glow_selected)


## Synchronizes widgets with values persisted in [GlobalSettings].
func load_settings() -> void:
	print("EffectsSection: Loading effects settings from disk.")
	var saved_tonemap: String = _load_effect_setting("tonemap_mode", VideoConfig.DEFAULT_TONEMAP)
	_select_dropdown_text(tonemap_options, saved_tonemap)

	var deband_val: Variant = GlobalSettings.get_setting("Settings", "debanding", true)
	debanding_checkbox.button_pressed = bool(deband_val)

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
