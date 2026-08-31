## Manages central crosshair reticle states, aim zoom visuals, and terminal focus scaling.
class_name CrosshairHUD
extends CenterContainer

## The central dot texture of the crosshair.
@onready var center_dot: TextureRect = $CenterDot

## The outer circular texture shown when zooming.
@onready var ui_circle_zoom: TextureRect = $UICircleZoom

## The inner circular texture shown when zooming.
@onready var ui_circle_zoom_inner: TextureRect = $UICircleZoomInner

## Animates the crosshair scaling and transformations.
var crosshair_tween: Tween

## Animates the UI elements when the player enters or exits zoom mode.
var zoom_tween: Tween

## Stores the default dimensions of the center crosshair dot.
var default_crosshair_size: Vector2


## Initializes crosshair element default transforms and connects event listeners.
func _ready() -> void:
	print("CrosshairHUD: _ready() called. Initializing reticle elements.")
	_initialize_reticle_elements()
	_connect_signals()


## Sets default sizes, pivot offsets, and initial visibility for zoom reticles.
func _initialize_reticle_elements() -> void:
	print("CrosshairHUD: Setting initial reticle transformations and pivots.")
	ui_circle_zoom.pivot_offset = ui_circle_zoom.custom_minimum_size / 2.0
	ui_circle_zoom.scale = Vector2.ZERO
	ui_circle_zoom.modulate.a = 0.0
	ui_circle_zoom.hide()

	ui_circle_zoom_inner.pivot_offset = ui_circle_zoom_inner.custom_minimum_size / 2.0
	ui_circle_zoom_inner.scale = Vector2.ZERO
	ui_circle_zoom_inner.modulate.a = 0.0
	ui_circle_zoom_inner.hide()

	default_crosshair_size = center_dot.custom_minimum_size
	if default_crosshair_size == Vector2.ZERO:
		default_crosshair_size = center_dot.size


## Connects global zoom and terminal interaction signals.
func _connect_signals() -> void:
	print("CrosshairHUD: Connecting global event bus signals.")
	if not Events.player_zoomed.is_connected(_on_player_zoomed):
		Events.player_zoomed.connect(_on_player_zoomed)
	if not Events.terminal_mode_toggled.is_connected(_on_terminal_mode_toggled):
		Events.terminal_mode_toggled.connect(_on_terminal_mode_toggled)


## Tweens reticle rings when entering or exiting aim zoom.
## [param is_zooming] True if the player is actively zoomed in.
func _on_player_zoomed(is_zooming: bool) -> void:
	print("CrosshairHUD: _on_player_zoomed() called. State: ", is_zooming)
	if zoom_tween and zoom_tween.is_valid():
		zoom_tween.kill()

	zoom_tween = (create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	))

	if is_zooming:
		center_dot.hide()
		ui_circle_zoom.show()
		ui_circle_zoom_inner.show()

		ui_circle_zoom.scale = Vector2.ZERO
		ui_circle_zoom.modulate.a = 0.0
		ui_circle_zoom_inner.scale = Vector2.ZERO
		ui_circle_zoom_inner.modulate.a = 0.0

		zoom_tween.tween_property(ui_circle_zoom, "scale", Vector2.ONE, 0.5).from(Vector2.ZERO)
		zoom_tween.tween_property(ui_circle_zoom, "modulate:a", 1.0, 0.3).from(0.0)
		zoom_tween.tween_property(ui_circle_zoom, "rotation", deg_to_rad(15), 1.0).from(0.0)

		zoom_tween.tween_property(ui_circle_zoom_inner, "scale", Vector2.ONE, 0.5).from(
			Vector2.ZERO
		)
		zoom_tween.tween_property(ui_circle_zoom_inner, "modulate:a", 0.1, 0.3).from(0.0)
		zoom_tween.tween_property(ui_circle_zoom_inner, "rotation", deg_to_rad(-45), 1.0).from(0.0)
	else:
		center_dot.show()
		zoom_tween.tween_property(ui_circle_zoom, "scale", Vector2.ZERO, 0.5)
		zoom_tween.tween_property(ui_circle_zoom, "modulate:a", 0.0, 0.3)
		zoom_tween.tween_property(ui_circle_zoom, "rotation", deg_to_rad(0), 0.25)

		zoom_tween.tween_property(ui_circle_zoom_inner, "scale", Vector2.ZERO, 0.5)
		zoom_tween.tween_property(ui_circle_zoom_inner, "modulate:a", 0.0, 0.3)
		zoom_tween.tween_property(ui_circle_zoom_inner, "rotation", deg_to_rad(0), 0.25)

		zoom_tween.finished.connect(_on_zoom_out_finished)


## Callback triggered when zoom out tween completes to hide inner nodes.
func _on_zoom_out_finished() -> void:
	ui_circle_zoom.hide()
	ui_circle_zoom_inner.hide()


## Expands the crosshair dot into terminal interaction bounds.
## [param is_active] True if the player is currently focused on an active terminal.
func _on_terminal_mode_toggled(is_active: bool) -> void:
	print("CrosshairHUD: Terminal mode toggled: ", is_active)

	if crosshair_tween and crosshair_tween.is_valid():
		crosshair_tween.kill()

	crosshair_tween = (create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	))

	if is_active:
		var target_size: Vector2 = Vector2(16.0, 16.0)
		crosshair_tween.tween_property(center_dot, "custom_minimum_size", target_size, 0.3)
		crosshair_tween.tween_property(center_dot, "size", target_size, 0.3)
	else:
		crosshair_tween.tween_property(
			center_dot, "custom_minimum_size", default_crosshair_size, 0.3
		)
		crosshair_tween.tween_property(center_dot, "size", default_crosshair_size, 0.3)
