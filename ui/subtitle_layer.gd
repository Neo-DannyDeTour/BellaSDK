## Manages on-screen subtitle rendering, speaker identification, and accessibility styling.
# class_name SubtitleLayer
extends CanvasLayer

## Additional time in seconds to keep the text visible after typing finishes.
const READING_GRACE_PERIOD: float = 3.0

## Speed threshold fallback in characters per second if duration is zero.
const DEFAULT_CPS: float = 25.0

## Transition animation speed in seconds for alpha fade transitions.
const FADE_DURATION: float = 0.2

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


## Lifecycle method called when the node enters the scene tree.
## Sets process mode, loads saved settings, and connects signal listeners.
func _ready() -> void:
	print("SubtitleLayer: _ready() called. Initializing subtitle display.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true

	if is_instance_valid(subtitle_label):
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		subtitle_label.visible_characters_behavior = (TextServer.VC_CHARS_AFTER_SHAPING)
		subtitle_label.scroll_following = false
		subtitle_label.add_theme_constant_override("line_separation", 4)

	_load_saved_settings()
	_hide_subtitles_immediate()
	_connect_signals()


## Pulls active settings directly from GlobalSettings at launch.
func _load_saved_settings() -> void:
	print("SubtitleLayer: Loading settings from GlobalSettings.")
	var gs: Node = get_node_or_null("/root/GlobalSettings")
	if not is_instance_valid(gs):
		return

	is_subtitles_enabled = bool(gs.get_setting("Accessibility", "subtitles_enabled", true))
	active_font_size = float(gs.get_setting("Accessibility", "subtitle_size", 24.0))
	_on_subtitle_size_changed(active_font_size)

	var bg_pct: float = float(gs.get_setting("Accessibility", "subtitle_bg_opacity", 50.0))
	active_bg_opacity = clampf(bg_pct / 100.0, 0.0, 1.0)

	var color_names: Array[String] = [
		"Cyan", "Blue", "Yellow", "Green", "Red", "Magenta", "White", "Black"
	]
	var text_idx: int = int(gs.get_setting("Accessibility", "subtitle_text_color", 6))
	if text_idx >= 0 and text_idx < color_names.size():
		active_text_color = color_names[text_idx].to_lower()

	var spk_idx: int = int(gs.get_setting("Accessibility", "subtitle_speaker_color", 0))
	if spk_idx >= 0 and spk_idx < color_names.size():
		active_speaker_color = color_names[spk_idx].to_lower()

	var bg_idx: int = int(gs.get_setting("Accessibility", "subtitle_bg_color", 7))
	if bg_idx >= 0 and bg_idx < color_names.size():
		active_bg_color = color_names[bg_idx].to_lower()

	_update_panel_stylebox()

	is_speaker_name_shown = bool(gs.get_setting("Accessibility", "subtitle_show_names", true))


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
	if Events.has_signal("font_changed") and not Events.font_changed.is_connected(_on_font_changed):
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
## [param speaker] Name identifier of the entity speaking.
## [param text] Dialogue body string to display.
## [param duration] Visible display duration in seconds.
func show_subtitle(speaker: String, text: String, duration: float) -> void:
	if not is_subtitles_enabled:
		print("SubtitleLayer: Subtitles disabled; dropping request.")
		return

	if not is_instance_valid(subtitle_label) or not is_instance_valid(background_panel):
		push_warning("SubtitleLayer: Subtitle UI nodes are invalid.")
		return

	print("SubtitleLayer: Displaying dialogue from '", speaker, "'.")

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	var formatted_body: String = ""
	if is_speaker_name_shown and not speaker.is_empty():
		formatted_body = ("[color=" + active_speaker_color + "]" + speaker + ":[/color] ")
	formatted_body += ("[color=" + active_text_color + "]" + text + "[/color]")

	subtitle_label.scroll_following = false
	subtitle_label.text = formatted_body
	subtitle_label.visible_characters = 0

	var scroll_bar: VScrollBar = subtitle_label.get_v_scroll_bar()
	if is_instance_valid(scroll_bar):
		scroll_bar.value = 0.0

	background_panel.visible = true

	var total_chars: int = subtitle_label.get_total_character_count()
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


## Updates visible character count and forces the active line fully into frame.
## [param char_count] Count of visible characters to reveal.
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

	fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_tween.tween_property(background_panel, "modulate:a", 0.0, FADE_DURATION)
	fade_tween.tween_callback(_hide_subtitles_immediate)


## Updates the subtitle font resource dynamically when selected.
## [param font_id] Identifier or path of the chosen font.
func _on_font_changed(font_id: String) -> void:
	print("SubtitleLayer: Updating subtitle label font -> ", font_id)
	if not is_instance_valid(subtitle_label):
		return

	var gs: Node = get_node_or_null("/root/GlobalSettings")
	var font_res: Font = null
	if is_instance_valid(gs) and gs.has_method("get_font_resource"):
		font_res = gs.get_font_resource(font_id)

	if is_instance_valid(font_res):
		subtitle_label.add_theme_font_override("normal_font", font_res)
	else:
		subtitle_label.remove_theme_font_override("normal_font")


## Toggles global master visibility for the subtitle layer.
## [param is_active] True if subtitles should be rendered.
func _on_subtitles_toggled(is_active: bool) -> void:
	print("SubtitleLayer: Master subtitle visibility toggled -> ", is_active)
	is_subtitles_enabled = is_active
	if not is_active:
		_hide_subtitles_immediate()


## Updates default font size for subtitle rendering.
## [param font_size] New font size in pixels.
func _on_subtitle_size_changed(font_size: float) -> void:
	print("SubtitleLayer: Subtitle font size adjusted -> ", font_size)
	active_font_size = font_size
	if is_instance_valid(subtitle_label):
		subtitle_label.add_theme_font_size_override("normal_font_size", int(font_size))


## Rebuilds the background panel StyleBoxFlat with current color and opacity.
func _update_panel_stylebox() -> void:
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
## [param opacity] Normalized opacity value from 0.0 to 1.0.
func _on_subtitle_bg_opacity_changed(opacity: float) -> void:
	print("SubtitleLayer: Background opacity adjusted -> ", opacity)
	active_bg_opacity = clampf(opacity, 0.0, 1.0)
	_update_panel_stylebox()


## Updates dialogue body text color string.
## [param color_key] Color name representation.
func _on_subtitle_text_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Dialogue text color updated -> ", color_key)
	active_text_color = color_key


## Updates background panel tint color.
## [param color_key] Color name representation.
func _on_subtitle_bg_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Subtitle background color updated -> ", color_key)
	active_bg_color = color_key
	_update_panel_stylebox()


## Updates speaker tag highlight color string.
## [param color_key] Color name representation.
func _on_subtitle_speaker_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Speaker tag color updated -> ", color_key)
	active_speaker_color = color_key


## Toggles whether speaker names precede dialogue text.
## [param enabled] True to display speaker prefix tags.
func _on_subtitle_show_names_toggled(enabled: bool) -> void:
	print("SubtitleLayer: Show speaker names toggled -> ", enabled)
	is_speaker_name_shown = enabled
