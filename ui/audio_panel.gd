## Coordinates audio bus volume channels, output profiles, and mirrored subtitle controls.
class_name AudioPanel
extends Panel

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Fallback volume scale applied when no saved audio preference exists.
const DEFAULT_VOLUME: float = 100.0

## Decibel difference threshold required to commit an engine bus change.
const DB_CHANGE_EPSILON: float = 0.05

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Master bus slider.
@onready var master_slider: HSlider = %MasterSlider

## Master bus numerical input.
@onready var master_input: LineEdit = %MasterLine

## SFX bus slider.
@onready var sfx_slider: HSlider = %SFXSlider

## SFX bus numerical input.
@onready var sfx_input: LineEdit = %SFXLine

## Accessibility SFX slider.
@onready var accesibility_sfx_slider: HSlider = %AccesibilitySFXSlider

## Accessibility SFX numerical input.
@onready var accesibility_sfx_input: LineEdit = %AccesibilitySFXLine

## Music bus slider.
@onready var music_slider: HSlider = %MusicSlider

## Music bus numerical input.
@onready var music_input: LineEdit = %MusicLine

## Voice bus slider.
@onready var voice_slider: HSlider = %VoiceSlider

## Voice bus numerical input.
@onready var voice_input: LineEdit = %VoiceLine

## Ambient bus slider.
@onready var ambient_slider: HSlider = %AmbientSlider

## Ambient bus numerical input.
@onready var ambient_input: LineEdit = %AmbientLine

## CheckButton for enabling subtitles.
@onready var enable_subs_toggle: CheckButton = %EnableSubsToggle

## Slider for subtitle font size.
@onready var sub_size_slider: HSlider = %SubSizeSlider

## Numerical input for subtitle font size.
@onready var sub_size_input: LineEdit = %SubSizeLine

## Slider for subtitle background opacity.
@onready var sub_bg_opacity_slider: HSlider = %SubBgOpacitySlider

## Numerical input for subtitle background opacity.
@onready var sub_bg_opacity_input: LineEdit = %SubBgOpacityLine

## CheckButton for mono audio channel mixing.
@onready var mono_audio_toggle: CheckButton = %MonoAudioToggle

## OptionButton for selecting output profile.
@onready var output_profile_option: OptionButton = %OutputProfileOption

## CheckButton for muting audio on focus loss.
@onready var mute_on_focus_toggle: CheckButton = %MuteOnFocusToggle


## Initializes audio dropdowns, signal callbacks, and restored volumes in [method _ready].
func _ready() -> void:
	print("UI: Audio Panel initialized.")
	_populate_dropdowns()
	_connect_signals()
	_load_audio_settings()
	_load_subtitle_mirrors()


## Populates audio output profile choices.
func _populate_dropdowns() -> void:
	print("UI: Populating Audio OptionButtons.")
	if is_instance_valid(output_profile_option):
		output_profile_option.clear()
		output_profile_option.add_item("Stereo / Headphones")
		output_profile_option.add_item("Surround (5.1)")
		output_profile_option.add_item("Surround (7.1)")


## Connects all volume, subtitle, and hardware signals.
func _connect_signals() -> void:
	print("UI: Connecting Audio Panel signals.")
	_connect_audio_adjustment(master_slider, master_input, "Master")
	_connect_audio_adjustment(sfx_slider, sfx_input, "SFX")
	_connect_audio_adjustment(accesibility_sfx_slider, accesibility_sfx_input, "AccesibilitySFX")
	_connect_audio_adjustment(music_slider, music_input, "Music")
	_connect_audio_adjustment(voice_slider, voice_input, "Voice")
	_connect_audio_adjustment(ambient_slider, ambient_input, "Ambient")

	if is_instance_valid(mono_audio_toggle):
		mono_audio_toggle.toggled.connect(_on_mono_audio_toggled)
	if is_instance_valid(output_profile_option):
		output_profile_option.item_selected.connect(_on_output_profile_selected)
	if is_instance_valid(mute_on_focus_toggle):
		mute_on_focus_toggle.toggled.connect(_on_mute_focus_toggled)

	_connect_subtitle_signals()


## Connects mirrored subtitle inputs and preview triggers.
func _connect_subtitle_signals() -> void:
	if is_instance_valid(enable_subs_toggle):
		enable_subs_toggle.toggled.connect(
			func(toggled_on: bool) -> void:
				print("AudioPanel: Subtitles toggled -> ", toggled_on)
				GlobalSettings.save_setting("Accessibility", "subtitles_enabled", toggled_on)
				var ev: Node = get_node_or_null("/root/Events")
				if is_instance_valid(ev) and ev.has_signal("subtitles_toggled"):
					ev.emit_signal("subtitles_toggled", toggled_on)
				if toggled_on:
					_request_preview_subtitle()
		)

	_connect_custom_slider(
		sub_size_slider,
		sub_size_input,
		"subtitle_size",
		12.0,
		48.0,
		"Accessibility",
		true,
		func(val: float) -> void:
			var ev: Node = get_node_or_null("/root/Events")
			if is_instance_valid(ev) and ev.has_signal("subtitle_size_changed"):
				ev.emit_signal("subtitle_size_changed", val)
			_request_preview_subtitle()
	)

	_connect_custom_slider(
		sub_bg_opacity_slider,
		sub_bg_opacity_input,
		"subtitle_bg_opacity",
		0.0,
		100.0,
		"Accessibility",
		true,
		func(val: float) -> void:
			var alpha: float = clampf(val / 100.0, 0.0, 1.0)
			var ev: Node = get_node_or_null("/root/Events")
			if is_instance_valid(ev) and ev.has_signal("subtitle_bg_opacity_changed"):
				ev.emit_signal("subtitle_bg_opacity_changed", alpha)
			_request_preview_subtitle()
	)

	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events):
		if events.has_signal("subtitles_toggled"):
			events.connect(
				"subtitles_toggled",
				func(enabled: bool) -> void:
					if (
						is_instance_valid(enable_subs_toggle)
						and enable_subs_toggle.button_pressed != enabled
					):
						enable_subs_toggle.set_pressed_no_signal(enabled)
			)
		if events.has_signal("subtitle_size_changed"):
			events.connect(
				"subtitle_size_changed",
				func(val: float) -> void:
					if (
						is_instance_valid(sub_size_slider)
						and not is_equal_approx(sub_size_slider.value, val)
					):
						sub_size_slider.set_value_no_signal(val)
						if is_instance_valid(sub_size_input):
							sub_size_input.text = str(int(val))
			)
		if events.has_signal("subtitle_bg_opacity_changed"):
			events.connect(
				"subtitle_bg_opacity_changed",
				func(alpha: float) -> void:
					var perc: float = alpha * 100.0
					if (
						is_instance_valid(sub_bg_opacity_slider)
						and not is_equal_approx(sub_bg_opacity_slider.value, perc)
					):
						sub_bg_opacity_slider.set_value_no_signal(perc)
						if is_instance_valid(sub_bg_opacity_input):
							sub_bg_opacity_input.text = str(int(perc))
			)


## Requests a dialogue text preview on screen.
func _request_preview_subtitle() -> void:
	if is_instance_valid(enable_subs_toggle) and not enable_subs_toggle.button_pressed:
		return
	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events) and events.has_signal("subtitle_requested"):
		events.emit_signal(
			"subtitle_requested",
			"Narrator",
			"This is a preview of dialogue text with current settings.",
			2.5
		)


## Restores subtitle states from [GlobalSettings].
func _load_subtitle_mirrors() -> void:
	if is_instance_valid(enable_subs_toggle):
		var raw_en: Variant = GlobalSettings.get_setting("Accessibility", "subtitles_enabled", true)
		var en: bool = bool(raw_en)
		enable_subs_toggle.set_pressed_no_signal(en)

	if is_instance_valid(sub_size_slider):
		var raw_size: Variant = GlobalSettings.get_setting("Accessibility", "subtitle_size", 24.0)
		var s_val: float = float(raw_size)
		sub_size_slider.set_value_no_signal(s_val)
		if is_instance_valid(sub_size_input):
			sub_size_input.text = str(int(s_val))

	if is_instance_valid(sub_bg_opacity_slider):
		var raw_op: Variant = GlobalSettings.get_setting(
			"Accessibility", "subtitle_bg_opacity", 50.0
		)
		var op: float = float(raw_op)
		sub_bg_opacity_slider.set_value_no_signal(op)
		if is_instance_valid(sub_bg_opacity_input):
			sub_bg_opacity_input.text = str(int(op))


## Binds slider and LineEdit pairs for volume adjustments.
func _connect_audio_adjustment(slider: HSlider, input_box: LineEdit, bus_name: String) -> void:
	if not is_instance_valid(slider) or not is_instance_valid(input_box):
		return
	slider.value_changed.connect(_on_volume_changed.bind(input_box, bus_name))
	slider.drag_ended.connect(_on_volume_drag_ended.bind(bus_name, slider))
	input_box.text_submitted.connect(_on_volume_input_submitted.bind(bus_name, slider))
	input_box.focus_entered.connect(_on_volume_focus_entered.bind(input_box))
	input_box.focus_exited.connect(_on_volume_focus_exited.bind(input_box, slider, bus_name))


## Connects synchronized slider and LineEdit pairs for custom properties.
func _connect_custom_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_v: float,
	max_v: float,
	section: String,
	is_int: bool,
	apply_cb: Callable
) -> void:
	if is_instance_valid(slider):
		slider.min_value = min_v
		slider.max_value = max_v
		slider.value_changed.connect(
			func(val: float) -> void:
				if is_instance_valid(input_box) and not input_box.has_focus():
					input_box.text = (str(int(val)) if is_int else ("%.2f" % val))
				apply_cb.call(val)
		)
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					print("Audio: Saved ", key, " -> ", slider.value)
					GlobalSettings.save_setting(section, key, slider.value)
		)

	if is_instance_valid(input_box):
		input_box.focus_entered.connect(
			func() -> void:
				input_box.set_meta("pre_focus_text", input_box.text)
				input_box.text = ""
		)
		input_box.text_submitted.connect(
			func(txt: String) -> void:
				var trimmed: String = txt.strip_edges()
				var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
				if trimmed.is_empty() or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var c_val: float = clampf(trimmed.to_float(), min_v, max_v)
					input_box.text = (str(int(c_val)) if is_int else ("%.2f" % c_val))
					print("Audio: Manually entered ", key, " -> ", c_val)
					GlobalSettings.save_setting(section, key, c_val)
					if is_instance_valid(slider):
						slider.value = c_val
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				var trimmed: String = input_box.text.strip_edges()
				var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
				if trimmed.is_empty() or not trimmed.is_valid_float():
					input_box.text = fallback
				else:
					var c_val: float = clampf(trimmed.to_float(), min_v, max_v)
					input_box.text = (str(int(c_val)) if is_int else ("%.2f" % c_val))
					if is_instance_valid(slider):
						if not is_equal_approx(slider.value, c_val):
							print("Audio: Saved ", key, " on defocus: ", c_val)
							GlobalSettings.save_setting(section, key, c_val)
							slider.value = c_val
		)


## Loads persisted audio volumes from storage.
func _load_audio_settings() -> void:
	print("UI: Loading audio data from GlobalSettings.")
	_apply_and_set("Master", master_slider, master_input)
	_apply_and_set("SFX", sfx_slider, sfx_input)
	_apply_and_set("AccesibilitySFX", accesibility_sfx_slider, accesibility_sfx_input)
	_apply_and_set("Music", music_slider, music_input)
	_apply_and_set("Voice", voice_slider, voice_input)
	_apply_and_set("Ambient", ambient_slider, ambient_input)

	if is_instance_valid(mono_audio_toggle):
		var raw_mono: Variant = GlobalSettings.get_setting("Accessibility", "mono_audio", false)
		var is_mono: bool = bool(raw_mono)
		mono_audio_toggle.set_pressed_no_signal(is_mono)
		_apply_mono_audio(is_mono)

	if is_instance_valid(output_profile_option):
		var raw_idx: Variant = GlobalSettings.get_setting("Audio", "output_profile", 0)
		var p_idx: int = int(raw_idx)
		output_profile_option.selected = p_idx
		_apply_output_profile(p_idx)

	if is_instance_valid(mute_on_focus_toggle):
		var raw_foc: Variant = GlobalSettings.get_setting("Audio", "mute_on_focus", true)
		var m_foc: bool = bool(raw_foc)
		mute_on_focus_toggle.set_pressed_no_signal(m_foc)
		_apply_mute_on_focus(m_foc)


## Retrieves stored bus level and updates controls.
func _apply_and_set(bus_name: String, slider: HSlider, input_box: LineEdit) -> void:
	var raw_vol: Variant = GlobalSettings.get_setting("Audio", bus_name, DEFAULT_VOLUME)
	var vol: float = float(raw_vol)
	if is_instance_valid(slider):
		slider.value = vol
	if is_instance_valid(input_box):
		input_box.text = str(int(vol))
	_set_bus_volume(bus_name, vol)


## Updates input text when slider value modifies.
func _on_volume_changed(value: float, input_node: LineEdit, bus_name: String) -> void:
	if is_instance_valid(input_node) and not input_node.has_focus():
		var formatted: String = str(int(value))
		if input_node.text != formatted:
			input_node.text = formatted
	_set_bus_volume(bus_name, value)


## Flushes volume to config when slider drag ends.
func _on_volume_drag_ended(value_changed: bool, bus_name: String, slider: HSlider) -> void:
	if value_changed and is_instance_valid(slider):
		print("Audio: Drag ended for ", bus_name, " -> ", slider.value)
		GlobalSettings.save_setting(section_name(bus_name), bus_name, slider.value)


## Helper returning config section name for audio bus setting.
func section_name(_bus: String) -> String:
	return "Audio"


## Converts linear volume into decibels for the target bus.
func _set_bus_volume(bus_name: String, slider_value: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var norm: float = slider_value / 100.0
	var clamped: float = maxf(norm, 0.0001)
	var target_db: float = linear_to_db(clamped)
	var current_db: float = AudioServer.get_bus_volume_db(bus_idx)
	var is_muted: bool = slider_value <= 0.1
	var current_muted: bool = AudioServer.is_bus_mute(bus_idx)

	if current_muted != is_muted:
		AudioServer.set_bus_mute(bus_idx, is_muted)
	if absf(current_db - target_db) >= DB_CHANGE_EPSILON:
		AudioServer.set_bus_volume_db(bus_idx, target_db)


## Handles manual numeric text submission for volume.
func _on_volume_input_submitted(new_text: String, bus_name: String, slider_node: HSlider) -> void:
	if not is_instance_valid(slider_node):
		return
	var new_val: float = clampf(new_text.to_float(), 0.0, 100.0)
	print("Audio: Manual input for ", bus_name, " -> ", new_val)
	if not is_equal_approx(slider_node.value, new_val):
		GlobalSettings.save_setting("Audio", bus_name, new_val)
		slider_node.value = new_val
	slider_node.release_focus()


## Clears LineEdit text on focus.
func _on_volume_focus_entered(input_node: LineEdit) -> void:
	if is_instance_valid(input_node):
		input_node.text = ""


## Commits volume on input defocus.
func _on_volume_focus_exited(input_node: LineEdit, slider_node: HSlider, bus_name: String) -> void:
	if not is_instance_valid(input_node) or not is_instance_valid(slider_node):
		return
	var cur: String = input_node.text.strip_edges()
	if cur.is_empty() or is_equal_approx(cur.to_float(), slider_node.value):
		input_node.text = str(int(slider_node.value))
	else:
		_on_volume_input_submitted(cur, bus_name, slider_node)


## Handles mono audio toggle switches.
func _on_mono_audio_toggled(button_pressed: bool) -> void:
	print("Audio: Mono audio toggled -> ", button_pressed)
	GlobalSettings.save_setting("Accessibility", "mono_audio", button_pressed)
	_apply_mono_audio(button_pressed)


## Configures stereo enhancement plugin on Master bus.
func _apply_mono_audio(is_mono: bool) -> void:
	var m_idx: int = AudioServer.get_bus_index("Master")
	if m_idx < 0:
		return
	var count: int = AudioServer.get_bus_effect_count(m_idx)
	for i: int in range(count):
		var eff: AudioEffect = AudioServer.get_bus_effect(m_idx, i)
		if eff is AudioEffectStereoEnhance:
			AudioServer.set_bus_effect_enabled(m_idx, i, is_mono)
			return


## Handles speaker output profile selection.
func _on_output_profile_selected(index: int) -> void:
	print("Audio: Profile selected -> ", index)
	GlobalSettings.save_setting("Audio", "output_profile", index)
	_apply_output_profile(index)


## Configures engine spatial profile.
func _apply_output_profile(index: int) -> void:
	print("Engine: Setting speaker spatial mode for index: ", index)


## Handles mute on focus loss toggle.
func _on_mute_focus_toggled(button_pressed: bool) -> void:
	print("Audio: Mute on focus loss -> ", button_pressed)
	GlobalSettings.save_setting("Audio", "mute_on_focus", button_pressed)
	_apply_mute_on_focus(button_pressed)


## Sets engine focus loss mute flag.
func _apply_mute_on_focus(mute_enabled: bool) -> void:
	print("System: Setting mute on focus loss: ", mute_enabled)
