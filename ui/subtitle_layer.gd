## Manages global subtitle presentation, typewriter animation, and accessibility formatting.
# class_name SubtitleLayer
extends CanvasLayer

## Default fallback duration for dialogue lines if none provided.
const DEFAULT_LINE_DURATION: float = 2.5
## Default font size in pixels if none is specified in settings.
const DEFAULT_FONT_SIZE: float = 26.0
## Default panel background opacity if none is specified in settings (0.0 to 1.0).
const DEFAULT_BG_OPACITY: float = 0.5
## Default subtitle body text color name.
const DEFAULT_TEXT_COLOR: String = "white"
## Default subtitle background color name.
const DEFAULT_BG_COLOR: String = "black"
## Default primary speaker label color name.
const DEFAULT_SPEAKER_COLOR: String = "cyan"
## Default setting state for displaying speaker names.
const DEFAULT_SHOW_NAMES: bool = true
## Default setting state for distinct speaker coloring.
const DEFAULT_SUB_COLORS: bool = true

## Palette color map resolving string names to engine [Color] objects.
const COLOR_MAP: Dictionary[String, Color] = {
	"cyan": Color(0.0, 1.0, 1.0, 1.0),
	"blue": Color(0.2, 0.4, 1.0, 1.0),
	"yellow": Color(1.0, 0.9, 0.0, 1.0),
	"green": Color(0.2, 0.9, 0.2, 1.0),
	"red": Color(1.0, 0.2, 0.2, 1.0),
	"magenta": Color(1.0, 0.2, 1.0, 1.0),
	"white": Color(1.0, 1.0, 1.0, 1.0),
	"black": Color(0.05, 0.05, 0.05, 1.0)
}

## Container managing layout bounds of the subtitle panel.
@onready var subtitle_margin: MarginContainer = $SubtitleMargin
## Panel node rendering the background box behind subtitle dialogue.
@onready var subtitle_panel: PanelContainer = $SubtitleMargin/SubtitlePanel
## RichTextLabel displaying formatted typewriter text.
@onready var subtitle_label: RichTextLabel = $SubtitleMargin/SubtitlePanel/SubtitleLabel

## Active tween handling fade and typewriter character reveals.
var _subtitle_tween: Tween
## Current font size in pixels applied to subtitle text.
var _font_size: float = DEFAULT_FONT_SIZE
## Current background opacity alpha value (0.0 to 1.0).
var _bg_opacity: float = DEFAULT_BG_OPACITY
## Current text body color name.
var _text_color_name: String = DEFAULT_TEXT_COLOR
## Current panel background color name.
var _bg_color_name: String = DEFAULT_BG_COLOR
## Current primary speaker label color name.
var _speaker_color_name: String = DEFAULT_SPEAKER_COLOR
## Flag indicating whether speaker names receive unique character color formatting.
var _use_speaker_colors: bool = DEFAULT_SUB_COLORS
## Flag indicating whether speaker names are rendered in dialogue boxes.
var _show_speaker_names: bool = DEFAULT_SHOW_NAMES


## Lifecycle initialization connecting to global event bus and configuring mouse pass-through.
func _ready() -> void:
	print("UI: SubtitleLayer global autoload initialized.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_setup_mouse_passthrough()

	if is_instance_valid(subtitle_margin):
		subtitle_margin.hide()
		subtitle_margin.modulate.a = 0.0

	_connect_event_signals()
	_load_initial_settings()


## Ensures subtitle controls do not intercept mouse input destined for interactive UI beneath.
func _setup_mouse_passthrough() -> void:
	print("UI: Configuring SubtitleLayer mouse passthrough.")
	if is_instance_valid(subtitle_margin):
		subtitle_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(subtitle_panel):
		subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(subtitle_label):
		subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Subscribes to global EventBus signals for subtitle triggers and accessibility updates.
func _connect_event_signals() -> void:
	if not has_node("/root/Events"):
		return
	var events: Node = get_node("/root/Events")
	if events.has_signal("subtitle_requested"):
		events.subtitle_requested.connect(_on_subtitle_requested)
	if events.has_signal("subtitle_canceled"):
		events.subtitle_canceled.connect(_on_subtitle_canceled)
	if events.has_signal("subtitle_size_changed"):
		events.subtitle_size_changed.connect(_on_subtitle_size_changed)
	if events.has_signal("subtitle_bg_opacity_changed"):
		events.subtitle_bg_opacity_changed.connect(_on_subtitle_bg_opacity_changed)
	if events.has_signal("subtitle_colors_changed"):
		events.subtitle_colors_changed.connect(_on_subtitle_colors_changed)
	if events.has_signal("subtitle_text_color_changed"):
		events.subtitle_text_color_changed.connect(_on_subtitle_text_color_changed)
	if events.has_signal("subtitle_bg_color_changed"):
		events.subtitle_bg_color_changed.connect(_on_subtitle_bg_color_changed)
	if events.has_signal("subtitle_speaker_color_changed"):
		events.subtitle_speaker_color_changed.connect(_on_subtitle_speaker_color_changed)
	if events.has_signal("subtitle_show_names_toggled"):
		events.subtitle_show_names_toggled.connect(_on_subtitle_show_names_toggled)


## Loads initial subtitle configuration from GlobalSettings.
func _load_initial_settings() -> void:
	if not has_node("/root/GlobalSettings"):
		return

	_font_size = (
		GlobalSettings.get_setting("Accessibility", "subtitle_size", DEFAULT_FONT_SIZE) as float
	)

	var raw_opacity: float = (
		GlobalSettings.get_setting("Accessibility", "subtitle_bg_opacity", 50.0) as float
	)
	_bg_opacity = clampf(raw_opacity / 100.0 if raw_opacity > 1.0 else raw_opacity, 0.0, 1.0)

	_use_speaker_colors = (
		GlobalSettings.get_setting("Accessibility", "subtitle_colors", DEFAULT_SUB_COLORS) as bool
	)

	_show_speaker_names = (
		GlobalSettings.get_setting("Accessibility", "subtitle_show_names", DEFAULT_SHOW_NAMES)
		as bool
	)

	var palette: Array[String] = [
		"cyan", "blue", "yellow", "green", "red", "magenta", "white", "black"
	]

	var text_idx: int = GlobalSettings.get_setting("Accessibility", "subtitle_text_color", 6) as int
	if text_idx >= 0 and text_idx < palette.size():
		_text_color_name = palette[text_idx]

	var bg_idx: int = GlobalSettings.get_setting("Accessibility", "subtitle_bg_color", 7) as int
	if bg_idx >= 0 and bg_idx < palette.size():
		_bg_color_name = palette[bg_idx]

	var spk_idx: int = (
		GlobalSettings.get_setting("Accessibility", "subtitle_speaker_color", 0) as int
	)
	if spk_idx >= 0 and spk_idx < palette.size():
		_speaker_color_name = palette[spk_idx]

	_apply_font_size(_font_size)
	_apply_background_styling()


## Formats and displays subtitle dialogue across any active scene or menu.
## [param speaker] Identifier name of the entity or announcer speaking.
## [param text] Dialogue content string.
## [param duration] Visible display duration in seconds.
func _on_subtitle_requested(
	speaker: String, text: String, duration: float = DEFAULT_LINE_DURATION
) -> void:
	print("UI: Global subtitle requested for: ", speaker)
	if not is_instance_valid(subtitle_label) or not is_instance_valid(subtitle_margin):
		return

	var formatted_speaker: String = ""
	if _show_speaker_names and not speaker.is_empty():
		var speaker_color: String = (
			_get_speaker_color(speaker) if _use_speaker_colors else _speaker_color_name
		)
		formatted_speaker = ("[color=" + speaker_color + "][b]" + speaker + ":[/b][/color] ")

	var formatted_body: String = "[color=" + _text_color_name + "]" + text + "[/color]"
	subtitle_label.text = formatted_speaker + formatted_body
	subtitle_label.visible_characters = 0
	subtitle_margin.show()

	if _subtitle_tween and _subtitle_tween.is_valid():
		_subtitle_tween.kill()

	_subtitle_tween = create_tween()
	_subtitle_tween.parallel().tween_property(subtitle_margin, "modulate:a", 1.0, 0.15)

	var total_chars: int = subtitle_label.get_total_character_count()
	var type_duration: float = maxf(0.1, duration)

	_subtitle_tween.parallel().tween_method(
		_update_visible_characters, 0, total_chars, type_duration
	)

	_subtitle_tween.chain().tween_interval(0.6)
	_subtitle_tween.chain().tween_property(subtitle_margin, "modulate:a", 0.0, 0.4)
	_subtitle_tween.finished.connect(subtitle_margin.hide)


## Updates visible character count for the typewriter reveal animation.
## [param current_chars] Total visible characters.
func _update_visible_characters(current_chars: int) -> void:
	if is_instance_valid(subtitle_label):
		subtitle_label.visible_characters = current_chars


## Cancels active typewriter animations and fades out subtitle display.
func _on_subtitle_canceled() -> void:
	print("UI: Subtitle canceled.")
	if _subtitle_tween and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	if is_instance_valid(subtitle_margin):
		subtitle_margin.hide()
		subtitle_margin.modulate.a = 0.0


## Adjusts subtitle font size when updated from accessibility settings.
## [param font_size] Target font size in pixels.
func _on_subtitle_size_changed(font_size: float) -> void:
	print("UI: Subtitle font size updated to: ", font_size)
	_font_size = font_size
	_apply_font_size(font_size)


## Adjusts subtitle background opacity when updated from accessibility settings.
## [param opacity] Target background opacity between 0.0 and 1.0.
func _on_subtitle_bg_opacity_changed(opacity: float) -> void:
	print("UI: Subtitle background opacity updated to: ", opacity)
	_bg_opacity = opacity
	_apply_background_styling()


## Updates default subtitle text color.
## [param color_key] Palette color string identifier.
func _on_subtitle_text_color_changed(color_key: String) -> void:
	print("UI: Subtitle text color updated to: ", color_key)
	_text_color_name = color_key


## Updates default subtitle background box color.
## [param color_key] Palette color string identifier.
func _on_subtitle_bg_color_changed(color_key: String) -> void:
	print("UI: Subtitle background color updated to: ", color_key)
	_bg_color_name = color_key
	_apply_background_styling()


## Updates primary speaker label color.
## [param color_key] Palette color string identifier.
func _on_subtitle_speaker_color_changed(color_key: String) -> void:
	print("UI: Subtitle speaker color updated to: ", color_key)
	_speaker_color_name = color_key


## Toggles speaker name visibility in subtitle boxes.
## [param enabled] Whether speaker names should be rendered.
func _on_subtitle_show_names_toggled(enabled: bool) -> void:
	print("UI: Subtitle show speaker names toggled: ", enabled)
	_show_speaker_names = enabled


## Toggles distinct speaker color formatting.
## [param enabled] Whether color tags are applied uniquely per speaker name.
func _on_subtitle_colors_changed(enabled: bool) -> void:
	print("UI: Subtitle speaker colors toggled: ", enabled)
	_use_speaker_colors = enabled


## Applies font sizing overrides directly to the subtitle text label.
## [param font_size] Pixel font size to apply.
func _apply_font_size(font_size: float) -> void:
	if not is_instance_valid(subtitle_label):
		return
	var target_px: int = int(maxf(font_size, 14.0))
	subtitle_label.add_theme_font_size_override("normal_font_size", target_px)
	subtitle_label.add_theme_font_size_override("bold_font_size", target_px)
	subtitle_label.add_theme_font_size_override("italics_font_size", target_px)
	subtitle_label.add_theme_font_size_override("bold_italics_font_size", target_px)


## Modulates subtitle background panel style color and alpha.
func _apply_background_styling() -> void:
	if not is_instance_valid(subtitle_panel):
		return

	var base_color: Color = COLOR_MAP.get(_bg_color_name, Color(0.05, 0.05, 0.05, 1.0))
	base_color.a = clampf(_bg_opacity, 0.0, 1.0)

	var panel_style: StyleBox = subtitle_panel.get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		var flat_box: StyleBoxFlat = panel_style.duplicate() as StyleBoxFlat
		flat_box.bg_color = base_color
		subtitle_panel.add_theme_stylebox_override("panel", flat_box)
	else:
		var new_box: StyleBoxFlat = StyleBoxFlat.new()
		new_box.bg_color = base_color
		new_box.set_corner_radius_all(6)
		subtitle_panel.add_theme_stylebox_override("panel", new_box)


## Returns a consistent hex color string for registered speakers.
## [param speaker] Speaker identifier name.
## [return] The BBCode hex color string or fallback color key.
func _get_speaker_color(speaker: String) -> String:
	match speaker.to_lower():
		"ttsandy":
			return "#00ffff"
		"system", "narrator":
			return "#ffd700"
		"player":
			return "#aaffaa"
		_:
			return _speaker_color_name
