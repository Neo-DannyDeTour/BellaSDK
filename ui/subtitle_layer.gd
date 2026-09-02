## Manages on-screen subtitle rendering, speaker identification, and accessibility styling.
# class_name SubtitleLayer
extends CanvasLayer

## Additional time in seconds to keep the text visible after typing finishes.
const READING_GRACE_PERIOD: float = 3.0

## Speed threshold fallback in characters per second if duration is zero.
const DEFAULT_CPS: float = 25.0

## Main background panel providing contrast backing behind subtitle text.
@onready var background_panel: PanelContainer = $MarginContainer/BackgroundPanel

## Container managing layout margins and internal padding for text.
@onready var margin_container: MarginContainer = $MarginContainer

## Label displaying speaker names and dialogue text.
@onready var subtitle_label: RichTextLabel = $MarginContainer/BackgroundPanel/SubtitleLabel

## Active tween handling subtitle fade-in, text typing, and fade-out transitions.
var fade_tween: Tween

## Internal timer managing automatic dismissal of timed dialogue entries.
var display_timer: SceneTreeTimer

## Current configured font size for subtitle rendering.
var active_font_size: float = 24.0

## Current background panel opacity scalar (0.0 to 1.0).
var active_bg_opacity: float = 0.7

## Base text color code or name applied to dialogue body text.
var active_text_color: String = "#FFFFFF"

## Color code or name applied to the speaker identifier tag.
var active_speaker_color: String = "#FFFF00"

## Controls whether speaker names are rendered before dialogue text.
var is_speaker_name_shown: bool = true


## Lifecycle method called when the node enters the scene tree.
## Hides initial subtitle nodes and connects subtitle event bus listeners.
func _ready() -> void:
	print("SubtitleLayer: _ready() called. Initializing subtitle display.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(subtitle_label):
		subtitle_label.scroll_following = false
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hide_subtitles_immediate()
	_connect_signals()


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
	if not Events.subtitle_speaker_color_changed.is_connected(_on_subtitle_speaker_color_changed):
		Events.subtitle_speaker_color_changed.connect(_on_subtitle_speaker_color_changed)
	if not Events.subtitle_show_names_toggled.is_connected(_on_subtitle_show_names_toggled):
		Events.subtitle_show_names_toggled.connect(_on_subtitle_show_names_toggled)


## Instantly resets subtitle visibility, scrolls, and alpha modulation to zero.
func _hide_subtitles_immediate() -> void:
	print("SubtitleLayer: Resetting subtitle layer to hidden state.")
	visible = false
	if is_instance_valid(subtitle_label):
		subtitle_label.visible_characters = 0
		subtitle_label.get_v_scroll_bar().value = 0.0
	if is_instance_valid(background_panel):
		background_panel.hide()
		background_panel.modulate.a = 0.0


## Renders typewriter subtitle dialogue synced to duration with grace reading time.
## [param speaker] Name identifier of the entity speaking.
## [param text] Dialogue body string to display.
## [param duration] Visible display duration in seconds.
func show_subtitle(speaker: String, text: String, duration: float) -> void:
	print("SubtitleLayer: Displaying dialogue from '", speaker, "' for ", duration, "s.")
	if not is_instance_valid(subtitle_label) or not is_instance_valid(background_panel):
		push_warning("SubtitleLayer: Subtitle UI nodes are invalid or not configured.")
		return

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	var formatted_body: String = ""
	if is_speaker_name_shown and not speaker.is_empty():
		formatted_body = "[color=" + active_speaker_color + "]" + speaker + ":[/color] "

	formatted_body += "[color=" + active_text_color + "]" + text + "[/color]"
	subtitle_label.text = formatted_body
	subtitle_label.visible_characters = 0
	subtitle_label.get_v_scroll_bar().value = 0.0

	visible = true
	background_panel.show()

	fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(background_panel, "modulate:a", 1.0, 0.2)

	var total_chars: int = subtitle_label.get_total_character_count()
	var type_duration: float = duration if duration > 0.0 else (total_chars / DEFAULT_CPS)

	fade_tween.tween_method(_animate_characters_and_scroll, 0, total_chars, type_duration)
	fade_tween.finished.connect(_on_typing_finished)


## Updates character count and only scrolls down when the typing cursor passes visible lines.
## [param char_count] Count of visible characters to reveal.
func _animate_characters_and_scroll(char_count: int) -> void:
	if not is_instance_valid(subtitle_label):
		return

	subtitle_label.visible_characters = char_count

	var scroll_bar: VScrollBar = subtitle_label.get_v_scroll_bar()
	var max_scroll: float = scroll_bar.max_value - scroll_bar.page

	if max_scroll <= 0.0 or char_count <= 0:
		scroll_bar.value = 0.0
		return

	var current_line: int = subtitle_label.get_character_line(maxi(0, char_count - 1))
	var visible_lines: int = subtitle_label.get_visible_line_count()
	var total_lines: int = subtitle_label.get_line_count()

	if current_line < visible_lines:
		scroll_bar.value = 0.0
	else:
		var overflow_lines: int = total_lines - visible_lines
		if overflow_lines > 0:
			var current_overflow: int = current_line - visible_lines + 1
			var step: float = max_scroll / float(overflow_lines)
			scroll_bar.value = clampf(float(current_overflow) * step, 0.0, max_scroll)


## Initiates grace period display timer after typewriter finishes.
func _on_typing_finished() -> void:
	print("SubtitleLayer: Typing completed. Starting ", READING_GRACE_PERIOD, "s grace timer.")
	display_timer = get_tree().create_timer(READING_GRACE_PERIOD)
	display_timer.timeout.connect(
		func() -> void:
			if visible:
				hide_subtitle()
	)


## Fades out and hides active subtitle dialogs.
func hide_subtitle() -> void:
	print("SubtitleLayer: Hiding active subtitle dialogue.")
	if not is_instance_valid(background_panel):
		return

	if fade_tween and fade_tween.is_valid():
		fade_tween.kill()

	fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_tween.tween_property(background_panel, "modulate:a", 0.0, 0.2)
	fade_tween.finished.connect(
		func() -> void:
			visible = false
			if is_instance_valid(background_panel):
				background_panel.hide()
			if is_instance_valid(subtitle_label):
				subtitle_label.visible_characters = 0
				subtitle_label.get_v_scroll_bar().value = 0.0
	)


## Toggles global master visibility for the subtitle layer.
## [param is_active] True if subtitles should be rendered.
func _on_subtitles_toggled(is_active: bool) -> void:
	print("SubtitleLayer: Master subtitle visibility toggled -> ", is_active)
	if not is_active:
		_hide_subtitles_immediate()


## Updates default font size for subtitle rendering.
## [param font_size] New font size in pixels.
func _on_subtitle_size_changed(font_size: float) -> void:
	print("SubtitleLayer: Subtitle font size adjusted -> ", font_size)
	active_font_size = font_size
	if is_instance_valid(subtitle_label):
		subtitle_label.add_theme_font_size_override("normal_font_size", int(font_size))


## Updates background panel opacity.
## [param opacity] Normalized opacity value from 0.0 to 1.0.
func _on_subtitle_bg_opacity_changed(opacity: float) -> void:
	print("SubtitleLayer: Background opacity adjusted -> ", opacity)
	active_bg_opacity = clampf(opacity, 0.0, 1.0)
	if is_instance_valid(background_panel):
		background_panel.self_modulate.a = active_bg_opacity


## Updates default body text color string.
## [param color_key] Hex or name representation of the font color.
func _on_subtitle_text_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Dialogue text color updated -> ", color_key)
	active_text_color = color_key


## Updates speaker tag highlight color string.
## [param color_key] Hex or name representation of the speaker color.
func _on_subtitle_speaker_color_changed(color_key: String) -> void:
	print("SubtitleLayer: Speaker tag color updated -> ", color_key)
	active_speaker_color = color_key


## Toggles whether speaker names precede dialogue text.
## [param enabled] True to display speaker prefix tags.
func _on_subtitle_show_names_toggled(enabled: bool) -> void:
	print("SubtitleLayer: Show speaker names toggled -> ", enabled)
	is_speaker_name_shown = enabled
