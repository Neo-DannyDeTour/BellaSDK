## Manages on-screen subtitle rendering, speaker identification, and accessibility styling.
# class_name SubtitleLayer
extends CanvasLayer

## Additional time in seconds to keep the text visible after typing finishes.
const READING_GRACE_PERIOD: float = 3.0

## Speed threshold fallback in characters per second if duration is zero.
const DEFAULT_CPS: float = 25.0

## Transition animation speed in seconds for alpha fade transitions.
const FADE_DURATION: float = 0.2

## Canvas layer priority ensuring subtitles render above menus.
const SUBTITLE_LAYER_INDEX: int = 125

## Main background panel providing contrast backing behind subtitle text.
@onready var background_panel: PanelContainer = $MarginContainer/BackgroundPanel

## Container managing layout margins and internal padding for text.
@onready var margin_container: MarginContainer = $MarginContainer

## Label displaying speaker names and dialogue text.
@onready
var subtitle_label: RichTextLabel = $MarginContainer/BackgroundPanel/MarginContainer/SubtitleLabel

## Active tween handling subtitle fade-in, text typing, delay, and fade-out.
var fade_tween: Tween

## Current configured font size for subtitle rendering.
var active_font_size: float = 24.0

## Current background panel opacity scalar (0.0 to 1.0).
var active_bg_opacity: float = 0.7

## Base text color code or name applied to dialogue body text.
var active_text_color: String = "white"

## Color code or name applied to the speaker identifier tag.
var active_speaker_color: String = "cyan"

## Color code or name applied to the background panel backing.
var active_bg_color: String = "black"

## Controls whether speaker names are rendered before dialogue text.
var is_speaker_name_shown: bool = true

## Master toggle determining if subtitles are permitted to render on screen.
var is_subtitles_enabled: bool = true

## Cached raw text string of the dialogue currently displayed.
var _current_raw_text: String = ""

## Cached speaker name of the dialogue currently displayed.
var _current_speaker: String = ""


## Initializes layer priority, node properties, saved settings, and signals.
func _ready() -> void:
	print("SubtitleLayer: _ready() called. Initializing subtitle display.")
	layer = SUBTITLE_LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true

	if is_instance_valid(margin_container):
		margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(background_panel):
		background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_instance_valid(subtitle_label):
		subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle_label.visible_characters_behavior = (TextServer.VC_CHARS_BEFORE_SHAPING)
		subtitle_label.scroll_following = false
		subtitle_label.add_theme_constant_override("line_separation", 4)

	_load_saved_settings()
	_hide_subtitles_immediate()
	_connect_signals()


## Pulls active settings directly from [GlobalSettings] at launch.
func _load_saved_settings() -> void:
	print("SubtitleLayer: Loading settings from GlobalSettings.")
	var gs: Node = get_node_or_null("/root/GlobalSettings")
	if not is_instance_valid(gs) or not gs.has_method("get_setting"):
		return

	var sub_enabled_raw: Variant = gs.call(
		&"get_setting", "Accessibility", "subtitles_enabled", true
	)
	is_subtitles_enabled = sub_enabled_raw == true

	var font_size_raw: Variant = gs.call(&"get_setting", "Accessibility", "subtitle_size", 24.0)
	if font_size_raw is float:
		var size_f: float = font_size_raw
		active_font_size = size_f
	elif font_size_raw is int:
		var size_i: int = font_size_raw
		active_font_size = float(size_i)
	_on_subtitle_size_changed(active_font_size)

	var bg_pct_raw: Variant = gs.call(&"get_setting", "Accessibility", "subtitle_bg_opacity", 50.0)
	var bg_pct: float = 50.0
	if bg_pct_raw is float:
		bg_pct = bg_pct_raw
	elif bg_pct_raw is int:
		var pct_int: int = bg_pct_raw
		bg_pct = float(pct_int)
	active_bg_opacity = clampf(bg_pct / 100.0, 0.0, 1.0)

	var color_names: Array[String] = [
		"Cyan", "Blue", "Yellow", "Green", "Red", "Magenta", "White", "Black"
	]

	var text_idx_raw: Variant = gs.call(&"get_setting", "Accessibility", "subtitle_text_color", 6)
	var text_idx: int = text_idx_raw if text_idx_raw is int else 6
	if text_idx >= 0 and text_idx < color_names.size():
		active_text_color = color_names[text_idx].to_lower()

	var spk_idx_raw: Variant = gs.call(&"get_setting", "Accessibility", "subtitle_speaker_color", 0)
	var spk_idx: int = spk_idx_raw if spk_idx_raw is int else 0
	if spk_idx >= 0 and spk_idx < color_names.size():
		active_speaker_color = color_names[spk_idx].to_lower()

	var bg_idx_raw: Variant = gs.call(&"get_setting", "Accessibility", "subtitle_bg_color", 7)
	var bg_idx: int = bg_idx_raw if bg_idx_raw is int else 7
	if bg_idx >= 0 and bg_idx < color_names.size():
		active_bg_color = color_names[bg_idx].to_lower()

	_update_panel_stylebox()
	var show_names_raw: Variant = gs.call(
		&"get_setting", "Accessibility", "subtitle_show_names", true
	)
	is_speaker_name_shown = show_names_raw == true
	print("SubtitleLayer: Subtitles enabled state: ", is_subtitles_enabled)


## Binds subtitle and dialogue customization signals from the global [Events] bus.
func _connect_signals() -> void:
	print("SubtitleLayer: Connecting subtitle event bus signals.")
	if not Events.subtitle_requested.is_connected(show_subtitle):
		Events.subtitle_requested.connect(show_subtitle)
	if not Events.subtitle_canceled.is_connected(hide_subtitle):
		Events.subtitle_canceled.connect(hide_subtitle)
	if not Events.subtitles_toggled.is_connected(_on_subtitles_toggled):
		Events.subtitles_toggled.connect(_on_subtitles_toggled)
	if not Events.subtitle_size_changed.is_connected(_on_subtitle_size_changed):
		Events.subtitle_size_changed.connect(_on_subtitle_size_changed)
	if not Events.subtitle_bg_opacity_changed.is_connected(_on_subtitle_bg_opacity_changed):
		Events.subtitle_bg_opacity_changed.connect(_on_subtitle_bg_opacity_changed)
	if not Events.subtitle_text_color_changed.is_connected(_on_subtitle_text_color_changed):
		Events.subtitle_text_color_changed.connect(_on_subtitle_text_color_changed)
	if not Events.subtitle_bg_color_changed.is_connected(_on_subtitle_bg_color_changed):
		Events.subtitle_bg_color_changed.connect(_on_subtitle_bg_color_changed)
	if not Events.subtitle_speaker_color_changed.is_connected(_on_subtitle_speaker_color_changed):
		Events.subtitle_speaker_color_changed.connect(_on_subtitle_speaker_color_changed)
	if not Events.subtitle_show_names_toggled.is_connected(_on_subtitle_show_names_toggled):
		Events.subtitle_show_names_toggled.connect(_on_subtitle_show_names_toggled)
	if Events.has_signal("font_changed"):
		if not Events.font_changed.is_connected(_on_font_changed):
			Events.font_changed.connect(_on_font_changed)


## Instantly resets subtitle visibility, scrolls, and alpha modulation to zero.
func _hide_subtitles_immediate() -> void:
	print("SubtitleLayer: Resetting subtitle layer to hidden state.")
	if is_instance_valid(subtitle_label):
		subtitle_label.scroll_following = false
		subtitle_label.visible_characters = 0
		var scroll_bar: VScrollBar = subtitle_label.get_v_scroll_bar()
		if is_instance_valid(scroll_bar):
			scroll_bar.value = 0.0
	if is_instance_valid(background_panel):
		background_panel.visible = false
		background_panel.modulate.a = 0.0


## Renders typewriter subtitle dialogue synced to duration with reading grace time.
func show_subtitle(speaker: String, text: String, duration: float) -> void:
	if not is_subtitles_enabled:
		print("SubtitleLayer: Subtitles disabled; dropping request.")
		return

	if not is_instance_valid(subtitle_label) or not is_instance_valid(background_panel):
		push_warning("SubtitleLayer: Subtitle UI nodes are invalid.")
		return

	print("SubtitleLayer: Displaying dialogue from '", speaker, "'.")
	_current_speaker = speaker
	_current_raw_text = text

	var is_already_showing: bool = background_panel.visible and background_panel.modulate.a > 0.2

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	_format_and_apply_text()

	var parsed_len: int = subtitle_label.get_parsed_text().length()
	var total_chars: int = maxi(parsed_len, subtitle_label.get_total_character_count())
	if total_chars <= 0:
		total_chars = text.length()

	background_panel.visible = true

	if is_already_showing:
		background_panel.modulate.a = 1.0
		subtitle_label.visible_characters = -1
		fade_tween = create_tween()
		fade_tween.tween_interval(duration + READING_GRACE_PERIOD)
		(
			fade_tween
			. tween_property(background_panel, "modulate:a", 0.0, FADE_DURATION)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN)
		)
		fade_tween.tween_callback(_hide_subtitles_immediate)
		return

	subtitle_label.scroll_following = false
	subtitle_label.visible_characters = 0

	var scroll_bar: VScrollBar = subtitle_label.get_v_scroll_bar()
	if is_instance_valid(scroll_bar):
		scroll_bar.value = 0.0

	var type_dur: float = duration if duration > 0.0 else (float(total_chars) / DEFAULT_CPS)

	fade_tween = create_tween()
	(
		fade_tween
		. tween_property(background_panel, "modulate:a", 1.0, FADE_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)

	fade_tween.tween_callback(
		func() -> void:
			if is_instance_valid(subtitle_label):
				subtitle_label.scroll_following = true
	)

	(
		fade_tween
		. tween_method(_animate_typing_and_scroll, 0, total_chars, type_dur)
		. set_trans(Tween.TRANS_LINEAR)
		. set_ease(Tween.EASE_IN_OUT)
	)

	fade_tween.tween_interval(READING_GRACE_PERIOD)
	(
		fade_tween
		. tween_property(background_panel, "modulate:a", 0.0, FADE_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)
	fade_tween.tween_callback(_hide_subtitles_immediate)


## Formats stored speaker and dialogue text using active BBCode palette colors.
func _format_and_apply_text() -> void:
	print("SubtitleLayer: Formatting dialogue text.")
	if not is_instance_valid(subtitle_label):
		return
	var formatted_body: String = ""
	if is_speaker_name_shown and not _current_speaker.is_empty():
		formatted_body = ("[color=" + active_speaker_color + "]" + _current_speaker + ":[/color] ")
	formatted_body += ("[color=" + active_text_color + "]" + _current_raw_text + "[/color]")
	subtitle_label.text = formatted_body


## Updates visible dialogue in real time when styling preferences change.
func _refresh_current_dialogue() -> void:
	if not is_instance_valid(background_panel) or not background_panel.visible:
		return
	print("SubtitleLayer: Refreshing active subtitle styling on screen.")
	_format_and_apply_text()
	subtitle_label.visible_characters = -1


## Updates visible character count and forces the active line fully into frame.
func _animate_typing_and_scroll(char_count: int) -> void:
	if not is_instance_valid(subtitle_label):
		return

	subtitle_label.visible_characters = char_count
	var scroll_bar: VScrollBar = subtitle_label.get_v_scroll_bar()
	if not is_instance_valid(scroll_bar):
		return

	if char_count <= 0:
		scroll_bar.value = 0.0
		return

	var current_line: int = subtitle_label.get_character_line(maxi(0, char_count - 1))
	var total_lines: int = subtitle_label.get_line_count()

	if current_line >= total_lines - 1 and char_count >= subtitle_label.get_total_character_count():
		scroll_bar.value = scroll_bar.max_value - scroll_bar.page
	else:
		subtitle_label.scroll_to_line(current_line)


## Fades out and hides active subtitle dialogs.
func hide_subtitle() -> void:
	print("SubtitleLayer: Hiding active subtitle dialogue.")
	if not is_instance_valid(background_panel):
		return

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	fade_tween = (create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN))
	fade_tween.tween_property(background_panel, "modulate:a", 0.0, FADE_DURATION)
	fade_tween.tween_callback(_hide_subtitles_immediate)


## Updates the subtitle font resource dynamically when selected.
func _on_font_changed(font_id: String) -> void:
	print("SubtitleLayer: Updating subtitle label font -> ", font_id)
	if not is_instance_valid(subtitle_label):
		return

	var gs: Node = get_node_or_null("/root/GlobalSettings")
	var font_res: Font = null
	if is_instance_valid(gs) and gs.has_method("get_font_resource"):
		var raw_font: Variant = gs.call(&"get_font_resource", font_id)
		if raw_font is Font:
			font_res = raw_font

	if is_instance_valid(font_res):
		subtitle_label.add_theme_font_override("normal_font", font_res)
	else:
		subtitle_label.remove_theme_font_override("normal_font")


## Toggles global master visibility for the subtitle layer.
func _on_subtitles_toggled(is_active: bool) -> void:
	print("SubtitleLayer: Master subtitle visibility toggled -> ", is_active)
	is_subtitles_enabled = is_active
	if not is_active:
		_hide_subtitles_immediate()


## Updates default font size for subtitle rendering.
func _on_subtitle_size_changed(font_size: float) -> void:
	print("SubtitleLayer: Subtitle font size adjusted -> ", font_size)
	active_font_size = font_size
	if is_instance_valid(subtitle_label):
		var size_int: int = int(font_size)
		subtitle_label.add_theme_font_size_override("normal_font_size", size_int)
		subtitle_label.add_theme_font_size_override("bold_font_size", size_int)
		subtitle_label.add_theme_font_size_override("italics_font_size", size_int)
		subtitle_label.add_theme_font_size_override("bold_italics_font_size", size_int)


## Rebuilds background [StyleBoxFlat] using active color and opacity.
func _update_panel_stylebox() -> void:
	print("SubtitleLayer: Updating background panel stylebox.")
	if not is_instance_valid(background_panel):
		return

	var base_col: Color = Color.from_string(active_bg_color, Color.BLACK)
	base_col.a = active_bg_opacity

	var style: StyleBoxFlat
	var existing_style: StyleBox = background_panel.get_theme_stylebox("panel")
	if existing_style is StyleBoxFlat:
		style = existing_style.duplicate() as StyleBoxFlat
	else:
		style = StyleBoxFlat.new()

	style.bg_color = base_col
	background_panel.add_theme_stylebox_override("panel", style)


## Updates background panel opacity.
func _on_subtitle_bg_opacity_changed(opacity: float) -> void:
	print("SubtitleLayer: Background opacity adjusted -> ", opacity)
	active_bg_opacity = clampf(opacity, 0.0, 1.0)
	_update_panel_stylebox()


## Updates dialogue body text color string.
func _on_subtitle_text_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Dialogue text color updated -> ", color_key)
	active_text_color = color_key
	_refresh_current_dialogue()


## Updates background panel tint color.
func _on_subtitle_bg_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Subtitle background color updated -> ", color_key)
	active_bg_color = color_key
	_update_panel_stylebox()


## Updates speaker tag highlight color string.
func _on_subtitle_speaker_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Speaker tag color updated -> ", color_key)
	active_speaker_color = color_key
	_refresh_current_dialogue()


## Toggles whether speaker names precede dialogue text.
func _on_subtitle_show_names_toggled(enabled: bool) -> void:
	print("SubtitleLayer: Show speaker names toggled -> ", enabled)
	is_speaker_name_shown = enabled
	_refresh_current_dialogue()
