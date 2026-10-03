## Controls subtitles formatting, palette colors, TTS narration, and audio mixing.
class_name AccessibilitySubsAudioSection
extends GridContainer

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Available palette color options for high contrast subtitle elements.
const COLOR_NAMES: Array[String] = [
	"Cyan", "Blue", "Yellow", "Green", "Red", "Magenta", "White", "Black"
]

## Default constant value for subtitle text font size in pixels.
const DEFAULT_SUB_SIZE: float = 24.0

## Default constant value for subtitle panel background opacity percentage.
const DEFAULT_SUB_BG_OPACITY: float = 50.0

## Default constant index for subtitle text color.
const DEFAULT_SUB_COLOR_INDEX: int = 6

## Default constant index for subtitle background color (Black).
const DEFAULT_SUB_BG_COLOR_INDEX: int = 7

## Default constant index for speaker name color (Cyan).
const DEFAULT_SUB_SPEAKER_COLOR_INDEX: int = 0

## Default constant value for distinct character subtitle colors.
const DEFAULT_SUB_COLORS: bool = true

## Default constant value for displaying speaker names.
const DEFAULT_SUB_SHOW_NAMES: bool = true

## Default constant value for master subtitles visibility.
const DEFAULT_SUBTITLES_ENABLED: bool = true

## Default constant value for Text-to-Speech narration system.
const DEFAULT_TTS_ENABLED: bool = false

## Default constant value for mono audio channel mixing.
const DEFAULT_MONO_AUDIO: bool = false

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Toggle switch for enabling or disabling subtitles system wide.
@onready var enable_subs_toggle: CheckButton = get_node_or_null("%EnableSubsToggle")

## Dropdown menu for secondary font override if defined.
@onready var font_option_2: OptionButton = get_node_or_null("%FontOption2")

## Slider for subtitle text font size.
@onready var sub_size_slider: HSlider = get_node_or_null("%SubSizeSlider")

## Text input for manual subtitle text font size entry.
@onready var sub_size_input: LineEdit = get_node_or_null("%SubSizeLine")

## Slider for subtitle background opacity percentage.
@onready var sub_bg_opacity_slider: HSlider = get_node_or_null("%SubBgOpacitySlider")

## Text input for manual subtitle background opacity percentage entry.
@onready var sub_bg_opacity_input: LineEdit = get_node_or_null("%SubBgOpacityLine")

## Dropdown menu for default subtitle body text color.
@onready var sub_text_color_option: OptionButton = get_node_or_null("%SubTextColorOption")

## Dropdown menu for subtitle background box color.
@onready var sub_bg_color_option: OptionButton = get_node_or_null("%SubBgColorOption")

## Dropdown menu for primary speaker label color.
@onready var sub_speaker_color_option: OptionButton = get_node_or_null("%SubSpeakerColorOption")

## Toggle switch for showing or hiding speaker names in subtitles.
@onready var sub_show_names_toggle: CheckButton = get_node_or_null("%SubShowNamesToggle")

## Toggle switch for colored character names in subtitles.
@onready var sub_colors_toggle: CheckButton = get_node_or_null("%SubColorsToggle")

## Toggle switch for text-to-speech audio narration.
@onready var tts_toggle: CheckButton = get_node_or_null("%TTSToggle")

## Toggle switch for mono audio mixing.
@onready var mono_audio_toggle: CheckButton = get_node_or_null("%MonoAudioToggle")


## Lifecycle initialization method registering dropdowns, signals, and stored settings.
func _ready() -> void:
	print("UI: Initializing Subtitles & Audio Section.")
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Populates [OptionButton] items for subtitle colors and typography.
func _populate_dropdowns() -> void:
	print("UI: Populating subtitle options dropdowns.")
	if is_instance_valid(font_option_2):
		font_option_2.clear()
		for font_name: String in GlobalSettings.get_font_display_names():
			font_option_2.add_item(font_name)

	var sub_color_dropdowns: Array[OptionButton] = [
		sub_text_color_option, sub_bg_color_option, sub_speaker_color_option
	]
	for dropdown: OptionButton in sub_color_dropdowns:
		if is_instance_valid(dropdown):
			dropdown.clear()
			for col: String in COLOR_NAMES:
				dropdown.add_item(col)


## Connects UI input signals for audio and subtitle controls.
func _connect_signals() -> void:
	print("UI: Binding subtitle and audio signals.")
	if is_instance_valid(enable_subs_toggle):
		enable_subs_toggle.toggled.connect(_on_enable_subs_toggled)

	if is_instance_valid(font_option_2):
		font_option_2.item_selected.connect(_on_font_option_selected)

	_connect_slider(
		sub_size_slider,
		sub_size_input,
		"subtitle_size",
		12.0,
		48.0,
		"Accessibility",
		true,
		_on_subtitle_size_committed
	)
	_connect_slider(
		sub_bg_opacity_slider,
		sub_bg_opacity_input,
		"subtitle_bg_opacity",
		0.0,
		100.0,
		"Accessibility",
		true,
		_on_subtitle_bg_opacity_committed
	)

	if is_instance_valid(sub_text_color_option):
		sub_text_color_option.item_selected.connect(_on_sub_text_color_selected)
	if is_instance_valid(sub_bg_color_option):
		sub_bg_color_option.item_selected.connect(_on_sub_bg_color_selected)
	if is_instance_valid(sub_speaker_color_option):
		sub_speaker_color_option.item_selected.connect(_on_sub_speaker_color_selected)
	if is_instance_valid(sub_show_names_toggle):
		sub_show_names_toggle.toggled.connect(_on_sub_show_names_toggled)
	if is_instance_valid(sub_colors_toggle):
		sub_colors_toggle.toggled.connect(_on_sub_colors_toggled)
	if is_instance_valid(tts_toggle):
		tts_toggle.toggled.connect(_on_tts_toggled)
	if is_instance_valid(mono_audio_toggle):
		mono_audio_toggle.toggled.connect(_on_mono_audio_toggled)

	if Events.has_signal(&"subtitles_toggled"):
		Events.subtitles_toggled.connect(sync_external_subtitles_enabled)
	if Events.has_signal(&"subtitle_size_changed"):
		Events.subtitle_size_changed.connect(sync_external_subtitle_size)
	if Events.has_signal(&"subtitle_bg_opacity_changed"):
		Events.subtitle_bg_opacity_changed.connect(sync_external_subtitle_opacity)


## Reads subtitle and audio preferences from [GlobalSettings] silently.
func load_settings() -> void:
	print("UI: Loading Subtitles and Audio settings.")
	var subs_enabled: bool = bool(
		GlobalSettings.get_setting("Accessibility", "subtitles_enabled", DEFAULT_SUBTITLES_ENABLED)
	)
	if is_instance_valid(enable_subs_toggle):
		enable_subs_toggle.set_pressed_no_signal(subs_enabled)

	_load_slider(
		sub_size_slider, sub_size_input, "subtitle_size", DEFAULT_SUB_SIZE, "Accessibility", true
	)

	_load_slider(
		sub_bg_opacity_slider,
		sub_bg_opacity_input,
		"subtitle_bg_opacity",
		DEFAULT_SUB_BG_OPACITY,
		"Accessibility",
		true
	)

	if is_instance_valid(sub_text_color_option):
		var color_idx: int = int(
			GlobalSettings.get_setting(
				"Accessibility", "subtitle_text_color", DEFAULT_SUB_COLOR_INDEX
			)
		)
		sub_text_color_option.selected = color_idx

	if is_instance_valid(sub_bg_color_option):
		var bg_idx: int = int(
			GlobalSettings.get_setting(
				"Accessibility", "subtitle_bg_color", DEFAULT_SUB_BG_COLOR_INDEX
			)
		)
		sub_bg_color_option.selected = bg_idx

	if is_instance_valid(sub_speaker_color_option):
		var spk_idx: int = int(
			GlobalSettings.get_setting(
				"Accessibility", "subtitle_speaker_color", DEFAULT_SUB_SPEAKER_COLOR_INDEX
			)
		)
		sub_speaker_color_option.selected = spk_idx

	if is_instance_valid(sub_show_names_toggle):
		var show_names: bool = bool(
			GlobalSettings.get_setting(
				"Accessibility", "subtitle_show_names", DEFAULT_SUB_SHOW_NAMES
			)
		)
		sub_show_names_toggle.set_pressed_no_signal(show_names)

	if is_instance_valid(sub_colors_toggle):
		sub_colors_toggle.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Accessibility", "subtitle_colors", DEFAULT_SUB_COLORS))
		)
	if is_instance_valid(tts_toggle):
		tts_toggle.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Accessibility", "tts_enabled", DEFAULT_TTS_ENABLED))
		)
	if is_instance_valid(mono_audio_toggle):
		mono_audio_toggle.set_pressed_no_signal(
			bool(GlobalSettings.get_setting("Audio", "mono_audio", DEFAULT_MONO_AUDIO))
		)


## Connects companion slider and LineEdit pairs with throttled commit logic.
func _connect_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	is_int: bool,
	commit_cb: Callable
) -> void:
	if is_instance_valid(slider):
		slider.min_value = min_val
		slider.max_value = max_val
		slider.value_changed.connect(
			func(val: float) -> void:
				if is_instance_valid(input_box) and not input_box.has_focus():
					input_box.text = (str(int(val)) if is_int else ("%.2f" % val))
				if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					_commit_sub_slider_val(key, val, section, commit_cb)
		)
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					print("Player adjusted ", key, " to: ", slider.value)
					_commit_sub_slider_val(key, slider.value, section, commit_cb)
		)

	if is_instance_valid(input_box):
		input_box.focus_entered.connect(
			func() -> void:
				input_box.set_meta("pre_focus_text", input_box.text)
				input_box.text = ""
		)
		input_box.text_submitted.connect(
			func(_txt: String) -> void:
				_commit_sub_line_edit(
					slider, input_box, key, min_val, max_val, section, is_int, commit_cb
				)
				input_box.release_focus()
		)
		input_box.focus_exited.connect(
			func() -> void:
				_commit_sub_line_edit(
					slider, input_box, key, min_val, max_val, section, is_int, commit_cb
				)
		)


## Commits subtitle slider value to settings and triggers callback if modified.
func _commit_sub_slider_val(key: String, val: float, section: String, commit_cb: Callable) -> void:
	var current: float = float(GlobalSettings.get_setting(section, key, -999.0))
	if not is_equal_approx(current, val):
		GlobalSettings.save_setting(section, key, val)
		if commit_cb.is_valid():
			commit_cb.call(val)


## Commits LineEdit input to subtitle slider and storage safely.
func _commit_sub_line_edit(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	min_val: float,
	max_val: float,
	section: String,
	is_int: bool,
	commit_cb: Callable
) -> void:
	var trimmed: String = input_box.text.strip_edges()
	var fallback: String = str(input_box.get_meta("pre_focus_text", ""))
	if trimmed.is_empty() or not trimmed.is_valid_float():
		input_box.text = fallback
		return

	var clamped_val: float = clampf(trimmed.to_float(), min_val, max_val)
	var formatted: String = str(int(clamped_val)) if is_int else ("%.2f" % clamped_val)
	input_box.text = formatted
	input_box.set_meta("pre_focus_text", formatted)

	if is_instance_valid(slider):
		slider.set_value_no_signal(clamped_val)

	_commit_sub_slider_val(key, clamped_val, section, commit_cb)


## Reads a float setting and synchronizes slider and LineEdit representations.
func _load_slider(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	default_val: float,
	section: String,
	is_int: bool = false
) -> void:
	if is_instance_valid(slider):
		var val: float = float(GlobalSettings.get_setting(section, key, default_val))
		slider.set_value_no_signal(val)
		if is_instance_valid(input_box):
			input_box.text = str(int(val)) if is_int else ("%.2f" % val)


## Emits a temporary preview subtitle on screen when dialogue options change.
func _request_preview_subtitle() -> void:
	if is_instance_valid(enable_subs_toggle) and not enable_subs_toggle.button_pressed:
		return

	print("UI: Emitting subtitle preview request.")
	Events.subtitle_requested.emit(
		"Narrator", "This is a preview of dialogue text with current settings.", 3.0
	)


## Handles master subtitle enabling and broadcasts changes.
func _on_enable_subs_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "subtitles_enabled", DEFAULT_SUBTITLES_ENABLED)
	)
	if current == toggled_on:
		return

	print("Player toggled Enable Subtitles to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "subtitles_enabled", toggled_on)
	_apply_subtitles_enabled(toggled_on)
	if toggled_on:
		_request_preview_subtitle()


## Broadcasts master subtitle visibility across [Events] bus.
func _apply_subtitles_enabled(enabled: bool) -> void:
	print("Engine: Applying Enable Subtitles: ", enabled)
	Events.subtitles_toggled.emit(enabled)


## Handles font dropdown selection for subtitle typography.
func _on_font_option_selected(index: int) -> void:
	var current: int = int(GlobalSettings.get_setting("Settings", "font_mode", 0))
	if current == index:
		return

	print("UI: Player selected Subtitle font index: ", index)
	GlobalSettings.save_setting("Settings", "font_mode", index)
	var font_ids: Array[String] = GlobalSettings.get_font_ids()
	if index >= 0 and index < font_ids.size():
		Events.font_changed.emit(font_ids[index])
	_request_preview_subtitle()


## Committed callback for subtitle font size changes.
func _on_subtitle_size_committed(val: float) -> void:
	_apply_subtitle_size(val)
	_request_preview_subtitle()


## Broadcasts subtitle font size adjustments across the [Events] bus.
func _apply_subtitle_size(size_val: float) -> void:
	print("Engine: Applying Subtitle Size: ", size_val)
	Events.subtitle_size_changed.emit(size_val)


## Committed callback for subtitle background opacity changes.
func _on_subtitle_bg_opacity_committed(val: float) -> void:
	_apply_subtitle_bg_opacity(val)
	_request_preview_subtitle()


## Broadcasts subtitle background opacity percentage adjustments across [Events].
func _apply_subtitle_bg_opacity(opacity_val: float) -> void:
	var normalized_alpha: float = clampf(opacity_val / 100.0, 0.0, 1.0)
	print("Engine: Applying Subtitle Background Opacity: ", opacity_val, "%")
	Events.subtitle_bg_opacity_changed.emit(normalized_alpha)


## Handles subtitle text color dropdown changes.
func _on_sub_text_color_selected(index: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting("Accessibility", "subtitle_text_color", DEFAULT_SUB_COLOR_INDEX)
	)
	if current == index:
		return

	print("Player selected Subtitle Text Color: ", COLOR_NAMES[index])
	GlobalSettings.save_setting("Accessibility", "subtitle_text_color", index)
	_apply_subtitle_text_color(index)
	_request_preview_subtitle()


## Broadcasts subtitle text color choice across the [Events] bus.
func _apply_subtitle_text_color(index: int) -> void:
	if index < 0 or index >= COLOR_NAMES.size():
		return
	var col_name: String = COLOR_NAMES[index].to_lower()
	print("Engine: Applying Subtitle Text Color: ", col_name)
	Events.subtitle_text_color_changed.emit(col_name)


## Handles subtitle background color dropdown changes.
func _on_sub_bg_color_selected(index: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting("Accessibility", "subtitle_bg_color", DEFAULT_SUB_BG_COLOR_INDEX)
	)
	if current == index:
		return

	print("Player selected Subtitle Background Color: ", COLOR_NAMES[index])
	GlobalSettings.save_setting("Accessibility", "subtitle_bg_color", index)
	_apply_subtitle_bg_color(index)
	_request_preview_subtitle()


## Broadcasts subtitle background box color choice across the [Events] bus.
func _apply_subtitle_bg_color(index: int) -> void:
	if index < 0 or index >= COLOR_NAMES.size():
		return
	var col_name: String = COLOR_NAMES[index].to_lower()
	print("Engine: Applying Subtitle Background Color: ", col_name)
	Events.subtitle_bg_color_changed.emit(col_name)


## Handles speaker name color dropdown changes.
func _on_sub_speaker_color_selected(index: int) -> void:
	var current: int = int(
		GlobalSettings.get_setting(
			"Accessibility", "subtitle_speaker_color", DEFAULT_SUB_SPEAKER_COLOR_INDEX
		)
	)
	if current == index:
		return

	print("Player selected Speaker Name Color: ", COLOR_NAMES[index])
	GlobalSettings.save_setting("Accessibility", "subtitle_speaker_color", index)
	_apply_subtitle_speaker_color(index)
	_request_preview_subtitle()


## Broadcasts speaker name color choice across the [Events] bus.
func _apply_subtitle_speaker_color(index: int) -> void:
	if index < 0 or index >= COLOR_NAMES.size():
		return
	var col_name: String = COLOR_NAMES[index].to_lower()
	print("Engine: Applying Speaker Name Color: ", col_name)
	Events.subtitle_speaker_color_changed.emit(col_name)


## Handles toggling speaker names visibility in subtitles.
func _on_sub_show_names_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "subtitle_show_names", DEFAULT_SUB_SHOW_NAMES)
	)
	if current == toggled_on:
		return

	print("Player toggled Show Speaker Names to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "subtitle_show_names", toggled_on)
	_apply_subtitle_show_names(toggled_on)
	_request_preview_subtitle()


## Broadcasts show/hide speaker names toggle across the [Events] bus.
func _apply_subtitle_show_names(enabled: bool) -> void:
	print("Engine: Applying Show Speaker Names: ", enabled)
	Events.subtitle_show_names_toggled.emit(enabled)


## Handles subtitle speaker color distinction toggling.
func _on_sub_colors_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "subtitle_colors", DEFAULT_SUB_COLORS)
	)
	if current == toggled_on:
		return

	print("Player toggled Subtitle Speaker Colors to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "subtitle_colors", toggled_on)
	_request_preview_subtitle()


## Handles Text-to-Speech narration toggling.
func _on_tts_toggled(toggled_on: bool) -> void:
	var current: bool = bool(
		GlobalSettings.get_setting("Accessibility", "tts_enabled", DEFAULT_TTS_ENABLED)
	)
	if current == toggled_on:
		return

	print("Player toggled Text-to-Speech to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "tts_enabled", toggled_on)
	Events.tts_state_changed.emit(toggled_on)


## Handles mono audio mix toggling.
func _on_mono_audio_toggled(toggled_on: bool) -> void:
	var current: bool = bool(GlobalSettings.get_setting("Audio", "mono_audio", DEFAULT_MONO_AUDIO))
	if current == toggled_on:
		return

	print("Player toggled Mono Audio to: ", toggled_on)
	GlobalSettings.save_setting("Audio", "mono_audio", toggled_on)


## Synchronizes toggle state from external events.
func sync_external_subtitles_enabled(enabled: bool) -> void:
	print("UI: Syncing external subtitles enabled toggle: ", enabled)
	if is_instance_valid(enable_subs_toggle) and enable_subs_toggle.button_pressed != enabled:
		enable_subs_toggle.set_pressed_no_signal(enabled)


## Synchronizes font size from external events.
func sync_external_subtitle_size(size_val: float) -> void:
	print("UI: Syncing external subtitle size: ", size_val)
	if is_instance_valid(sub_size_slider) and not is_equal_approx(sub_size_slider.value, size_val):
		sub_size_slider.set_value_no_signal(size_val)
		if is_instance_valid(sub_size_input):
			sub_size_input.text = str(int(size_val))


## Synchronizes background opacity from external events.
func sync_external_subtitle_opacity(norm_alpha: float) -> void:
	print("UI: Syncing external subtitle opacity: ", norm_alpha)
	var percent_val: float = norm_alpha * 100.0
	if (
		is_instance_valid(sub_bg_opacity_slider)
		and not is_equal_approx(sub_bg_opacity_slider.value, percent_val)
	):
		sub_bg_opacity_slider.set_value_no_signal(percent_val)
		if is_instance_valid(sub_bg_opacity_input):
			sub_bg_opacity_input.text = str(int(percent_val))
