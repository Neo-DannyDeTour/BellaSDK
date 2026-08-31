## Manages on-screen warning messages, contextual prompts, and note reading overlays.
class_name NotificationHUD
extends Control

## Grouping canvas item used to control warning label opacity and positioning.
@onready var warning_canvas_group: CanvasGroup = $WarningCanvasGroup

## Label displaying temporary hint or warning text to the player.
@onready var warning_label: Label = $WarningCanvasGroup/WarningLabel

## Container for the note reading screen dimming and text presentation.
@onready var note_overlay_ui: CanvasLayer = $NoteOverlayUI

## Rich text label displaying the formatted note content.
@onready var note_text_label: RichTextLabel = $NoteOverlayUI/NoteText

## Animates the visibility fade in and fade out of on-screen warning messages.
var warning_tween: Tween


## Lifecycle method called when the node enters the scene tree.
## Initializes note overlay visibility and binds event bus signals.
func _ready() -> void:
	print("NotificationHUD: _ready() called. Initializing notification elements.")
	if is_instance_valid(note_overlay_ui):
		note_overlay_ui.hide()

	if is_instance_valid(warning_label):
		warning_label.modulate.a = 0.0
		warning_label.add_theme_color_override("font_outline_color", Color.BLACK)
		warning_label.add_theme_constant_override("outline_size", 12)

	if is_instance_valid(warning_canvas_group):
		warning_canvas_group.material = null

	_recenter_warning_ui()
	get_viewport().size_changed.connect(_recenter_warning_ui)
	_connect_signals()


## Binds notification and note reading events from the global [Events] bus.
func _connect_signals() -> void:
	print("NotificationHUD: Connecting global event bus signals.")
	if not Events.hint_requested.is_connected(show_warning_message):
		Events.hint_requested.connect(show_warning_message)
	if not Events.note_opened.is_connected(_on_note_opened):
		Events.note_opened.connect(_on_note_opened)
	if not Events.note_closed.is_connected(_on_note_closed):
		Events.note_closed.connect(_on_note_closed)


## Repositions hint and warning notifications relative to the screen center.
func _recenter_warning_ui() -> void:
	print("NotificationHUD: _recenter_warning_ui() positioning warning banner.")
	if not is_instance_valid(warning_canvas_group) or not is_instance_valid(warning_label):
		return

	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	warning_canvas_group.position = Vector2(screen_size.x / 2.0, (screen_size.y / 2.0) + 70.0)
	warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)


## Fades in a centered notification banner with the provided text.
## [param message] String content to present to the user.
## [param duration] Visible display duration before fading out.
func show_warning_message(message: String, duration: float = 2.0) -> void:
	print("NotificationHUD: Displaying warning '", message, "' for ", duration, "s.")
	if not is_instance_valid(warning_label):
		return

	warning_label.text = message

	if warning_tween and warning_tween.is_valid():
		warning_tween.kill()

	warning_tween = create_tween().set_trans(Tween.TRANS_SINE)
	warning_tween.tween_property(warning_label, "modulate:a", 1.0, 0.1)
	warning_tween.tween_interval(duration)
	warning_tween.tween_property(warning_label, "modulate:a", 0.0, 0.5)


## Shows the note reading interface populated with formatted note text.
## [param note_text] The unformatted raw text string loaded from the note entity.
func _on_note_opened(note_text: String) -> void:
	print("NotificationHUD: _on_note_opened() received. Displaying note.")
	if is_instance_valid(note_overlay_ui) and is_instance_valid(note_text_label):
		var formatted_text: String = note_text.replace("\\n", "\n")
		note_text_label.text = formatted_text
		note_overlay_ui.show()


## Hides the note reading canvas layer.
func _on_note_closed() -> void:
	print("NotificationHUD: _on_note_closed() received. Hiding note UI.")
	if is_instance_valid(note_overlay_ui):
		note_overlay_ui.hide()
